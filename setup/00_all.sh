#!/usr/bin/env bash
# 00 一键安装（首次使用，约 1~2 小时，取决于网速）
# 顺序: 拉代码 → 建环境 → 编部署端 → 编 TRT 引擎 → 下权重
# 用法: bash setup/00_all.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "############################################################"
echo "# GEAR-SONIC Teleop 安装"
echo "# 依赖: Ubuntu 24.04 / NVIDIA GPU(建议 ≥8G) / 已装 uv / 已装 conda / sudo"
echo "# 网络: 无法直连 GitHub/HF 时先导出代理，例如:"
echo "#   export https_proxy=http://127.0.0.1:7897 http_proxy=http://127.0.0.1:7897"
echo "############################################################"
read -rp "继续？[y/N] " a; [ "$a" = y ] || exit 0

bash "$ROOT/setup/01_clone_upstream.sh"
bash "$ROOT/setup/02_envs.sh"
bash "$ROOT/setup/03_build_deploy.sh"
bash "$ROOT/setup/04_build_trt_vitpose.sh"
bash "$ROOT/setup/05_fetch_assets.sh"

cat <<'EOF'

全部完成！运行:
  bash scripts/run_teleop.sh                                  # 实时摄像头
  bash scripts/run_teleop.sh demo/videos/sub16_whitechair_033.mp4   # 用演示视频

窗口: GEM webcam(按 q 退出) / MuJoCo(可点 X)
急停: 部署端 tmux 窗口 sim:deploy 按 O
EOF
