#!/usr/bin/env bash
set -euo pipefail

count_files() {
  local pattern="$1"
  local root="$2"
  if [[ ! -d "$root" ]]; then
    echo "0"
    return
  fi
  if command -v rg >/dev/null 2>&1; then
    rg --files -g "$pattern" "$root" | wc -l
  else
    find "$root" -type f -name "$pattern" | wc -l
  fi
}

video_root="${XDG_VIDEOS_DIR:-$HOME/Videos}"
video_alt_root="$HOME/video"
steam_root="$HOME/.steam/steam/steamapps/workshop/content/431960"
steam_alt_root="$HOME/.local/share/Steam/steamapps/workshop/content/431960"

echo "video_root=$video_root"
echo "video_alt_root=$video_alt_root"
echo "steam_root=$steam_root"
echo "steam_alt_root=$steam_alt_root"
echo "video_mp4=$(count_files '*.mp4' "$video_root")"
echo "video_alt_mp4=$(count_files '*.mp4' "$video_alt_root")"
echo "steam_mp4=$(count_files '*.mp4' "$steam_root")"
echo "steam_alt_mp4=$(count_files '*.mp4' "$steam_alt_root")"
echo "steam_previews=$(count_files 'preview.*' "$steam_root")"
echo "steam_alt_previews=$(count_files 'preview.*' "$steam_alt_root")"
