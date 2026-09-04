#!/usr/bin/env bash
# ============================================================
# create-release.sh - 计算 IPA 哈希并生成 Release notes（支持正式版 + Lite 版）
#
# 输入（环境变量）：
#   RELEASE_ASSET_DIR 正式版 artifact 目录（默认 ./release_asset）
#   LITE_ASSET_DIR    Lite 版 artifact 目录（可选，为空则只发布正式版）
#   TAG / FULL_SHA / SRC_REPO / BRANCH / APP_NAME / IPA / IPA_LITE / RELEASE_NAME
#   GITHUB_REPOSITORY
#
# 输出：
#   $GITHUB_OUTPUT: ipa_path / ipa_lite_path / sha256 / size / lite_sha256 / lite_size
#   文件：RELEASE_NOTES.md
# ============================================================
set -euo pipefail

ASSET_DIR="${RELEASE_ASSET_DIR:-./release_asset}"
LITE_DIR="${LITE_ASSET_DIR:-}"
TAG="${TAG:?}"; FULL_SHA="${FULL_SHA:?}"; SRC_REPO="${SRC_REPO:?}"; BRANCH="${BRANCH:?}"
APP_NAME="${APP_NAME:?}"; IPA="${IPA:?}"; RELEASE_NAME="${RELEASE_NAME:?}"
IPA_LITE="${IPA_LITE:-}"
GH_REPO="${GITHUB_REPOSITORY:-}"

# ---------- 正式版 ----------
IPA_FILE=$(find "$ASSET_DIR" -maxdepth 2 -name "*.ipa" | head -1)
[ -n "$IPA_FILE" ] || { echo "::error:: 在 $ASSET_DIR 未找到 IPA"; exit 1; }
SHA256=$(sha256sum "$IPA_FILE" | awk '{print $1}')
SIZE=$(du -h "$IPA_FILE" | cut -f1)
echo "ipa_path=$IPA_FILE" >> "$GITHUB_OUTPUT"
echo "sha256=$SHA256"     >> "$GITHUB_OUTPUT"
echo "size=$SIZE"         >> "$GITHUB_OUTPUT"

# ---------- Lite 版（可选） ----------
LITE_FILE=""; LITE_SHA=""; LITE_SIZE=""
if [ -n "$LITE_DIR" ]; then
  LITE_FILE=$(find "$LITE_DIR" -maxdepth 2 -name "*.ipa" | head -1 || true)
  if [ -n "$LITE_FILE" ]; then
    LITE_SHA=$(sha256sum "$LITE_FILE" | awk '{print $1}')
    LITE_SIZE=$(du -h "$LITE_FILE" | cut -f1)
  else
    echo "::warning:: Lite 目录存在但未找到 ipa: $LITE_DIR，仅发布正式版"
    LITE_FILE=""
  fi
fi
echo "ipa_lite_path=$LITE_FILE" >> "$GITHUB_OUTPUT"
echo "lite_sha256=$LITE_SHA"    >> "$GITHUB_OUTPUT"
echo "lite_size=$LITE_SIZE"     >> "$GITHUB_OUTPUT"

SRC_COMMIT_LINK="https://github.com/$SRC_REPO/commit/$FULL_SHA"

# ---------- Release notes ----------
cat > RELEASE_NOTES.md <<EOF
## 📦 $RELEASE_NAME

| 项目 | 值 |
|---|---|
| 🏷️ Tag | \`${TAG}\` |
| 🌱 源仓库 | [${SRC_REPO}](https://github.com/${SRC_REPO}) |
| 🔀 源分支 | \`${BRANCH}\` |
| 📌 源 Commit | [${FULL_SHA:0:7}](${SRC_COMMIT_LINK}) |
| 🧩 App 名称 | ${APP_NAME} |
| ⏱️ 构建时间 | $(date -u '+%Y-%m-%d %H:%M UTC') |

---

### 📦 下载

**🟢 正式版**
- 文件：\`${IPA}\`
- 大小：${SIZE}
- SHA256：\`${SHA256}\`

EOF

if [ -n "$LITE_FILE" ]; then
  cat >> RELEASE_NOTES.md <<EOF
**⚡ Lite 版（资源压缩，更省体积/加载更快，适合低配机型）**
- 文件：\`${IPA_LITE}\`
- 大小：${LITE_SIZE}
- SHA256：\`${LITE_SHA}\`

EOF
fi

cat >> RELEASE_NOTES.md <<EOF
---

### 📥 iPhone 安装方式

1. **TrollStore（巨魔商店，推荐 iOS 15.0~16.6.1）**
   - 完全无需签名，用文件 App 或隔空投送打开 IPA 直接安装，永久有效。

2. **Sideloadly / AltStore（免费 Apple ID）**
   - Mac / PC 端安装 Sideloadly，登录 Apple ID，拖入 IPA，选择设备开始自签安装，7 天一续签。

3. **爱思助手 / 3uTools**
   - 数据线连接电脑 → 「工具箱 / 我的设备 → IPA 签名 → Apple ID 签名 → 安装」，简单直观。

4. **企业签 / 开发者证书（\$99/年）**
   - 用企业或个人开发者证书重签后可直接分发或上传 TestFlight。

---

### 💡 说明

- 本产物为**无签名 IPA**，需要按上述方式自签或利用巨魔商店安装。
- Lite 版仅对图片/音频做了有损压缩（图片保持尺寸、音频降码率），其余逻辑与正式版一致。
- 此 Release 由 [Build & Auto Release 工作流](https://github.com/${GH_REPO}/actions/workflows/auto-release.yml) 自动生成。
EOF

echo "✅ Release notes generated; full=$IPA_FILE ($SIZE) lite=${LITE_FILE:-无}"