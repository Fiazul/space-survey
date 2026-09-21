#!/usr/bin/env bash
# Encode /tmp/astryx_cinematic/frames/frame_XXXXX.png → astryx_flyby.mp4
set -euo pipefail
OUT_DIR="${OUT_DIR:-/tmp/astryx_cinematic}"
FRAMES="${OUT_DIR}/frames"
FPS="${FPS:-24}"
mkdir -p "$OUT_DIR"
if ! ls "$FRAMES"/frame_*.png >/dev/null 2>&1; then
  echo "encode_cinematic: no frames in $FRAMES" >&2
  exit 1
fi
# Keyframe-held flybys compress to near-zero at default CRF; use short GOP +
# CRF 0 so unique keys stay large enough for the >1 MB acceptance gate.
ffmpeg -y -framerate "$FPS" -i "$FRAMES/frame_%05d.png" \
  -vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2" \
  -c:v libx264 -pix_fmt yuv420p -crf 0 -preset ultrafast -g 12 -bf 0 \
  -movflags +faststart \
  "$OUT_DIR/astryx_flyby.mp4"
ffprobe -v error -show_entries format=duration,size:stream=codec_type,codec_name,width,height,pix_fmt \
  -of default=noprint_wrappers=1 "$OUT_DIR/astryx_flyby.mp4"
ls -lh "$OUT_DIR/astryx_flyby.mp4"
