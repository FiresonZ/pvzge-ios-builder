#!/usr/bin/env bash
# ============================================================
# build-ipa.sh - 初始化 Capacitor、无签名编译并打包 unsigned IPA
#
# 前提：本脚本运行前，workflow 已将官方源码 checkout 到
#       $GITHUB_WORKSPACE/_game_src，且脚本所在仓库位于 $GITHUB_WORKSPACE。
#
# 输入（通过环境变量）：
#   APP_NAME / APP_BUNDLE_ID / WEB_DIR / VERSION / COMMIT_SHORT
#   XCODE_SCHEME / CAPACITOR_CORE_VERSION
#   RUNNER_TEMP / GITHUB_WORKSPACE（GitHub Actions 自动提供）
#
# 输出：
#   $GITHUB_ENV   : APP_PATH
#   $GITHUB_OUTPUT: ipa_name、ipa_output_dir、size
# ============================================================
set -euo pipefail

APP_NAME="${APP_NAME:?APP_NAME 未设置}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:?APP_BUNDLE_ID 未设置}"
WEB_DIR="${WEB_DIR:?WEB_DIR 未设置}"
VERSION="${VERSION:?VERSION 未设置}"
COMMIT_SHORT="${COMMIT_SHORT:-}"
SUFFIX="${SUFFIX:-}"          # 空=正式版；lite = Lite 版
VTOK="${SUFFIX:-full}"        # 区分正式/Lite 的各类中间/产物目录，避免并行构建互相覆盖
CAP_VERSION="${CAPACITOR_CORE_VERSION:-6}"
SCHEME="${XCODE_SCHEME:-App}"
GITHUB_WORKSPACE="${GITHUB_WORKSPACE:?}"
RUNNER_TEMP="${RUNNER_TEMP:?}"

SRC="$GITHUB_WORKSPACE/_game_src"
# WEB_DIR 可能传绝对路径（如 prepare-lite 生成的临时目录），否则相对 SRC
WEB_DIR_ABS="${WEB_DIR}"
[ -d "$WEB_DIR_ABS" ] || WEB_DIR_ABS="$SRC/$WEB_DIR"
[ -d "$WEB_DIR_ABS" ] || { echo "::error:: Web 目录不存在: $WEB_DIR_ABS"; exit 1; }

# 每个变体用独立工程目录，避免多次构建相互覆盖
proj="${PROJ_DIR:-$RUNNER_TEMP/capacitor-project}"
mkdir -p "$proj"
cd "$proj"

# ---------- 1) 初始化 package.json ----------
cat > package.json <<'PKGJSON'
{
  "name": "pvzge-ios-wrapper",
  "version": "1.0.0",
  "private": true,
  "description": "Capacitor wrapper for PvZ2 Gardendless iOS"
}
PKGJSON

# ---------- 2) 安装 Capacitor 依赖 ----------
npm install --silent --no-audit --no-fund \
  "@capacitor/core@^$CAP_VERSION" \
  "@capacitor/cli@^$CAP_VERSION" \
  "@capacitor/ios@^$CAP_VERSION"

# ---------- 3) cap init（Capacitor 6 不支持 --app-version）----------
npx cap init "$APP_NAME" "$APP_BUNDLE_ID" --web-dir="$WEB_DIR_ABS"

# ---------- 4) 写入 appId/appName/appVersion/appVersionCode ----------
python3 - <<PYEOF
import json, os
p = "capacitor.config.json"
c = json.load(open(p))
c["appId"] = c.get("appId") or os.environ["APP_BUNDLE_ID"]
c["appName"] = c.get("appName") or os.environ["APP_NAME"]
c["appVersion"] = os.environ["VERSION"]
c["appVersionCode"] = 1
with open(p, "w") as f:
    f.write(json.dumps(c, indent=2) + "\n")
PYEOF

# ---------- 5) 添加 iOS 平台并同步 ----------
npx cap add ios
npx cap sync ios

# ---------- 6) 定位 iOS 工程根目录（含 Podfile / App.xcworkspace）----------
#    注意用 -prune 排除 .xcodeproj 内部自带的 project.xcworkspace，
#    避免把工作目录定位到工程容器（App.xcodeproj）而非工程根（App）。
cd ios
WS=$(find . -maxdepth 5 \( -name "*.xcodeproj" -prune \) -o \( -name "*.xcworkspace" -print \) | sort | head -1)
[ -n "$WS" ] || { echo "::error:: 未找到 .xcworkspace（cap add ios 是否成功？）"; exit 1; }
WS_DIR=$(cd "$(dirname "$WS")" && pwd)
WS_NAME=$(basename "$WS")
cd "$WS_DIR"
[ -f Podfile ] || { echo "::error:: $WS_DIR 下未找到 Podfile"; exit 1; }

# ---------- 7) CocoaPods ----------
pod install --repo-update || pod install

# ---------- 8) 强制无签名 ----------
PBXPROJ=$(find . -maxdepth 2 -name "project.pbxproj" | head -1)
[ -n "$PBXPROJ" ] || { echo "::error:: 未找到 project.pbxproj"; exit 1; }
/usr/bin/sed -i '' 's/DEVELOPMENT_TEAM = [^;]*;//g' "$PBXPROJ"
/usr/bin/sed -i '' 's/CODE_SIGN_IDENTITY = [^;]*;//g' "$PBXPROJ"
/usr/bin/sed -i '' 's/"CODE_SIGN_IDENTITY\[sdk=iphoneos\*\]" = [^;]*;//g' "$PBXPROJ"
/usr/bin/sed -i '' 's/CODE_SIGN_STYLE = [^;]*;//g' "$PBXPROJ"
/usr/bin/sed -i '' 's/PROVISIONING_PROFILE_SPECIFIER = [^;]*;//g' "$PBXPROJ"

# ---------- 9) 编译（Release / iphoneos，无签名）----------
DERIVED_DATA="$RUNNER_TEMP/derived_data_${VTOK}"
BUILD_DIR="$RUNNER_TEMP/build_output_${VTOK}"
mkdir -p "$DERIVED_DATA" "$BUILD_DIR"
set -o pipefail
xcodebuild \
  -workspace "$WS_NAME" \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$BUILD_DIR/xcresult" \
  CODE_SIGNING_ALLOWED="NO" \
  CODE_SIGNING_REQUIRED="NO" \
  CODE_SIGN_IDENTITY="" \
  "CODE_SIGN_IDENTITY[sdk=iphoneos*]"="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  CODE_SIGN_STYLE="Manual" \
  ENABLE_BITCODE="NO" \
  ONLY_ACTIVE_ARCH="NO" \
  SUPPORTS_MACCATALYST="NO" \
  build | xcbeautify

APP_PATH=$(find "$DERIVED_DATA/Build/Products/Release-iphoneos" -maxdepth 1 -name "*.app" -type d | head -1)
[ -n "$APP_PATH" ] || { echo "::error:: 编译后未找到 .app"; exit 1; }

# ---------- 9) 打包 unsigned IPA ----------
SAFE_NAME=$(printf '%s' "$APP_NAME" | sed 's/[^A-Za-z0-9._-]/_/g')
BASE="${SAFE_NAME}-${VERSION}"
[ -n "$COMMIT_SHORT" ] && BASE="${BASE}-${COMMIT_SHORT}"
if [ -n "$SUFFIX" ]; then
  IPA_NAME="${BASE}-${SUFFIX}-unsigned.ipa"
else
  IPA_NAME="${BASE}-unsigned.ipa"
fi
STAGE="$RUNNER_TEMP/ipa_stage_${VTOK}"
OUT="$RUNNER_TEMP/ipa_output_${VTOK}"
mkdir -p "$STAGE/Payload" "$OUT"
cp -R "$APP_PATH" "$STAGE/Payload/"

cd "$STAGE"
zip -qrX "$OUT/$IPA_NAME" Payload

echo "APP_PATH=$APP_PATH"       >> "$GITHUB_ENV"
echo "ipa_name=$IPA_NAME"       >> "$GITHUB_OUTPUT"
echo "ipa_output_dir=$OUT"      >> "$GITHUB_OUTPUT"
echo "✅ IPA: $OUT/$IPA_NAME ($(du -h "$OUT/$IPA_NAME" | cut -f1))"