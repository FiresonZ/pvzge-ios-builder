#!/usr/bin/env bash
# ============================================================
# prepare-lite.sh - 生成 Lite 版 web 资源目录（压缩图片/音频）
#
# 用法：
#   ./scripts/prepare-lite.sh <源webDir> <输出liteDir>
#
# 策略（尽量安全，不破坏 Cocos 引用）：
#   1. PNG：pngquant 有损量化到 8bit，保持原尺寸/alpha（不缩放，避免破坏布局）
#   2. MP3：ffmpeg 重编码为 96kbps（保持 .mp3 格式与文件名，避免改名导致引用失效）
#   工具缺失或压缩失败时保留原文件，仅告警，不中断。
# ============================================================
set -euo pipefail

SRC="${1:?用法: prepare-lite.sh <源webDir> <输出liteDir>}"
OUT="${2:?}"

[ -d "$SRC" ] || { echo "::error:: 源目录不存在: $SRC"; exit 1; }
rm -rf "$OUT"
mkdir -p "$OUT"
cp -R "$SRC"/. "$OUT"/

# ---------- 1) PNG 有损量化（保持尺寸） ----------
if command -v pngquant >/dev/null 2>&1 || brew install pngquant >/dev/null 2>&1; then
  echo "🔧 压缩 PNG（有损量化，保持尺寸）..."
  compressed_png=0
  while IFS= read -r -d '' f; do
    tmp="${f}.tmp.png"
    if pngquant --force --quality 60-80 --speed 1 --output "$tmp" "$f" 2>/dev/null; then
      if [ "$(wc -c < "$tmp")" -lt "$(wc -c < "$f")" ]; then
        mv -f "$tmp" "$f"; compressed_png=$((compressed_png+1))
      else
        rm -f "$tmp"          # 量化后反而更大则保留原图
      fi
    else
      rm -f "$tmp"
    fi
  done < <(find "$OUT" -type f -iname '*.png' -print0)
  echo "    已压缩 PNG 数: $compressed_png"
else
  echo "::warning:: 未能安装 pngquant，跳过 PNG 压缩"
fi

# ---------- 2) MP3 重编码为 96kbps（保持扩展名） ----------
if command -v ffmpeg >/dev/null 2>&1 || brew install ffmpeg >/dev/null 2>&1; then
  echo "🔧 重编码 MP3（96kbps）..."
  compressed_mp3=0
  while IFS= read -r -d '' f; do
    tmp="${f}.lite.mp3"
    rm -f "$tmp"
    if ffmpeg -hide_banner -loglevel error -i "$f" -codec:a libmp3lame -b:a 96k "$tmp" 2>/dev/null \
       && [ -f "$tmp" ] && [ "$(wc -c < "$tmp")" -lt "$(wc -c < "$f")" ]; then
      mv -f "$tmp" "$f"; compressed_mp3=$((compressed_mp3+1))
    else
      rm -f "$tmp"
    fi
  done < <(find "$OUT" -type f -iname '*.mp3' -print0)
  echo "    已压缩 MP3 数: $compressed_mp3"
else
  echo "::warning:: 未能安装 ffmpeg，跳过 MP3 压缩"
fi

# ---------- 3) 汇总 ----------
before=$(python3 -c "import os;t=sum(os.path.getsize(os.path.join(r,n)) for r,_,fs in os.walk('$SRC') for n in fs);print('%.0f'%(t/1048576))")
after=$(python3 -c "import os;t=sum(os.path.getsize(os.path.join(r,n)) for r,_,fs in os.walk('$OUT') for n in fs);print('%.0f'%(t/1048576))")
echo "✅ Lite 资源生成完成:"
echo "   压缩前 ${before} MB → 压缩后 ${after} MB（节省 $(( before - after )) MB）"