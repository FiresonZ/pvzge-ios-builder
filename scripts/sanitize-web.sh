#!/usr/bin/env bash
# ============================================================
# sanitize-web.sh - 去除 web 资源里的广告/统计/隐私同意代码
#
# 用法：
#   ./scripts/sanitize-web.sh <webDir>
#
# 作用：
#   1. 移除 index.html 中由 `isGitHubPages` 门控的整段
#      Google Analytics + AdSense + 隐私同意(consent) 脚本。
#      该块只在 play.pvzge.com 域名下才会执行；
#      iOS 以 file:// 运行并不触发，此处为彻底清理死代码。
#   2. 删除已失效的 ads.txt（仅 AdSense 域名资质声明）。
#   仅作文本清理，不触碰其它游戏脚本。
# ============================================================
set -euo pipefail

WEB_DIR="${1:?用法: sanitize-web.sh <webDir>}"
[ -d "$WEB_DIR" ] || { echo "::error:: 目录不存在: $WEB_DIR"; exit 1; }

INDEX="$WEB_DIR/index.html"
if [ -f "$INDEX" ]; then
  python3 - "$INDEX" <<'PY'
import re, sys
p = sys.argv[1]
html = open(p, encoding="utf-8", errors="replace").read()
orig = html

def drop(m):
    # 移除包含 isGitHubPages 或 googlesyndication 的 <script> 块
    return "" if ("isGitHubPages" in m.group(0) or "googlesyndication" in m.group(0)) else m.group(0)

html = re.sub(r"<script(?:\s[^>]*)?>.*?</script>", drop, html, flags=re.S)
if html != orig:
    open(p, "w", encoding="utf-8").write(html)
    print("✅ 已从 index.html 移除广告/统计/同意脚本块")
else:
    print("ℹ️  index.html 中未发现广告脚本（无需处理）")
PY
else
  echo "::warning:: 未找到 index.html: $INDEX"
fi

# 删除失效的 ads.txt
if [ -f "$WEB_DIR/ads.txt" ]; then
  rm -f "$WEB_DIR/ads.txt"
  echo "🗑️  已删除 ads.txt"
else
  echo "ℹ️  无 ads.txt"
fi

echo "✅ 资源清理完成: $WEB_DIR"