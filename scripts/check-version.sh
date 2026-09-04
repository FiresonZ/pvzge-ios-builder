#!/usr/bin/env bash
# ============================================================
# check-version.sh - 检测官方仓库版本，决定是否构建发版
#
# 输入（通过环境变量）：
#   SOURCE_REPO   官方源码仓库 owner/repo（默认 Gzh0821/pvzge_web）
#   SOURCE_BRANCH 跟踪的分支，留空则用官方默认分支
#   WEB_DIR       Web 产物目录（默认 docs）
#   APP_NAME      App 显示名称（默认 PvZ2 Gardendless）
#   APP_BUNDLE_ID App Bundle Identifier（默认 com.pvzge.gardendless）
#   APP_VERSION   手动覆盖版本号（可选，优先级最高）
#   FORCE_BUILD   true 时即使版本无变化也强制构建
#   GITHUB_TOKEN  用于访问 GitHub API（workflow 自动提供）
#   GITHUB_REPOSITORY 本仓库（workflow 自动提供）
#
# 输出（写入 $GITHUB_OUTPUT）：
#   repo branch web_dir app_name app_bundle_id app_version force
#   version commit_sha commit_short should_release tag_name release_name
# ============================================================
set -euo pipefail

REPO="${SOURCE_REPO:-}"
BRANCH="${SOURCE_BRANCH:-}"
WEB_DIR="${WEB_DIR:-}"
APP_NAME="${APP_NAME:-}"
BUNDLE_ID="${APP_BUNDLE_ID:-}"
APP_VERSION="${APP_VERSION:-}"
FORCE="${FORCE_BUILD:-false}"
GH_REPO="${GITHUB_REPOSITORY:-}"
TOKEN="${GITHUB_TOKEN:-}"

[ -z "$REPO" ]      && REPO="Gzh0821/pvzge_web"
[ -z "$WEB_DIR" ]   && WEB_DIR="docs"
[ -z "$APP_NAME" ]  && APP_NAME="PvZ2 Gardendless"
[ -z "$BUNDLE_ID" ] && BUNDLE_ID="com.pvzge.gardendless"
[ -z "$FORCE" ]     && FORCE="false"

out() { echo "$1=$2" >> "$GITHUB_OUTPUT"; }

AUTH=()
[ -n "$TOKEN" ] && AUTH=(-H "Authorization: Bearer $TOKEN")

# ---------- 1) 解析默认分支 ----------
if [ -z "$BRANCH" ]; then
  BRANCH=$(curl -sfL "${AUTH[@]}" "https://api.github.com/repos/$REPO" \
    | python3 -c "import sys,json;print(json.load(sys.stdin).get('default_branch','master'))")
fi

# ---------- 2) 版本号 ----------
if [ -n "$APP_VERSION" ]; then
  VERSION="$APP_VERSION"
else
  URL="https://raw.githubusercontent.com/$REPO/$BRANCH/$WEB_DIR/index.html"
  # <title>PvZ2 Gardendless Online | 0.13.0</title>
  VERSION=$(curl -sfL --max-time 60 "$URL" | python3 -c "
import sys,re
html=sys.stdin.read()
m=re.search(r'<title>[^<]*?\|\s*([0-9][^<\s]+)\s*</title>', html, re.I)
if not m: m=re.search(r'<title>[^<]*?v?([0-9][0-9a-zA-Z._+-]*)\s*</title>', html, re.I)
print(m.group(1) if m else '')
")
  [ -n "$VERSION" ] || VERSION="0.0.0-unknown"
fi

# ---------- 3) 最新 commit SHA ----------
API="https://api.github.com/repos/$REPO/commits?sha=$BRANCH&path=$WEB_DIR&per_page=1"
SHA=$(curl -sfL "${AUTH[@]}" "$API" | python3 -c "import sys,json;arr=json.load(sys.stdin);print(arr[0]['sha'] if arr else '')")
[ -n "$SHA" ] || { echo "::error:: 无法获取 $WEB_DIR 的最新 commit"; exit 1; }
SHORT="${SHA:0:7}"

# ---------- 4) Tag / 是否构建 ----------
TAG="v${VERSION}+${SHORT}"
REL_NAME="$APP_NAME v${VERSION} (${SHORT})"

LATEST=""
[ -n "$GH_REPO" ] && LATEST=$(curl -sfL "${AUTH[@]}" \
  "https://api.github.com/repos/$GH_REPO/releases/latest" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('tag_name',''))" || echo "")

SHOULD="false"
if [ "$FORCE" = "true" ]; then
  SHOULD="true"
elif [ -z "$LATEST" ] || [ "$LATEST" != "$TAG" ]; then
  SHOULD="true"
fi

# ---------- 5) 写出 outputs ----------
out "repo"           "$REPO"
out "branch"         "$BRANCH"
out "web_dir"        "$WEB_DIR"
out "app_name"       "$APP_NAME"
out "app_bundle_id"  "$BUNDLE_ID"
out "app_version"    "$APP_VERSION"
out "force"          "$FORCE"
out "version"        "$VERSION"
out "commit_sha"     "$SHA"
out "commit_short"   "$SHORT"
out "should_release" "$SHOULD"
out "tag_name"       "$TAG"
out "release_name"   "$REL_NAME"

echo "==============================================="
echo " [check-version] tag=$TAG version=$VERSION sha=$SHORT build=$SHOULD"
echo "==============================================="