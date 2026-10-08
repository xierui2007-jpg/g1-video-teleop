#!/usr/bin/env bash
# 01 克隆上游仓库到 third_party/
# 用法: bash setup/01_clone_upstream.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TP="$ROOT/third_party"
mkdir -p "$TP"

# 网络不通时: 导出代理 export https_proxy=http://127.0.0.1:7897 http_proxy=...
# 或把 URL 换成镜像: https://gh-proxy.com/https://github.com/...
SONIC_URL="${SONIC_URL:-https://github.com/NVlabs/GR00T-WholeBodyControl.git}"
GEMX_URL="${GEMX_URL:-https://github.com/NVlabs/GEM-X.git}"

[ -d "$TP/GEAR-SONIC/gear_sonic" ] || git clone "$SONIC_URL" "$TP/GEAR-SONIC"

if [ ! -d "$TP/GEM-X/gem" ]; then
  git clone "$GEMX_URL" "$TP/GEM-X"
  ( cd "$TP/GEM-X"
    # 子模块 soma-retargeter 是 SSH 地址且本项目不需要，改写/跳过
    git config url."https://github.com/".insteadOf "git@github.com:"
    git submodule update --init --recursive --depth 1 || \
      echo "[warn] 子模块部分失败（soma-retargeter 可忽略），继续" )
fi

echo "[1/2] 拉 GEAR-SONIC 的 LFS 资产（mesh/USD，缺了 Isaac/URDF 会崩）"
( cd "$TP/GEAR-SONIC" && (git lfs pull || bash "$ROOT/tools/lfs_pull_media.sh") )

echo "[2/2] 拉 GEM-X 的 SOMA 人体资产"
( cd "$TP/GEM-X/third_party/soma" && git lfs pull || echo "[warn] soma lfs 失败，稍后可重试" )
ln -sfn "$TP/GEM-X/third_party/soma/assets" "$TP/GEM-X/inputs/soma_assets" 2>/dev/null || true

echo "完成。下一步: bash setup/02_envs.sh"
