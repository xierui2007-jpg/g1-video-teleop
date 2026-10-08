#!/bin/bash
# 不走 LFS batch API，直接从 media.githubusercontent.com 按 LFS 指针拉真身（并行版）
set -u
cd "$(dirname "$0")/.."
BASE="https://media.githubusercontent.com/media/NVlabs/GR00T-WholeBodyControl/main"
fetch_one() {
  local f="$1"
  if head -c 40 "$f" 2>/dev/null | grep -q "git-lfs"; then
    local code
    code=$(curl -sL --retry 2 --max-time 90 -o "$f.tmp" -w "%{http_code}" "$BASE/$f")
    if [ "$code" = "200" ] && ! head -c 40 "$f.tmp" | grep -q "git-lfs"; then
      mv "$f.tmp" "$f"; echo "OK $f"
    else
      rm -f "$f.tmp"; echo "FAIL($code) $f"
    fi
  fi
}
export -f fetch_one 2>/dev/null; export BASE
stage=${1:-all}
case "$stage" in
  pri)  find gear_sonic/data/assets/robot_description -type f 2>/dev/null ;;
  sec)  find gear_sonic/data/robots gear_sonic/data/robot_model -type f 2>/dev/null ;;
  all)  find gear_sonic/data -type f 2>/dev/null ;;
esac | xargs -P 6 -I{} bash -c 'fetch_one "$@"' _ {}
echo "STAGE $stage DONE"
