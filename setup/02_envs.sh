#!/usr/bin/env bash
# 02 建两个 Python 环境
#   a) third_party/GEAR-SONIC/.venv_sim  仿真 + 部署桥（**必须 py3.10**，cyclonedds 只提供 cp310 轮子）
#   b) third_party/GEM-X/.venv           视觉栈（本项目用 py3.11；官方也支持 3.12）
# 用法: bash setup/02_envs.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TP="$ROOT/third_party"
SONIC="$TP/GEAR-SONIC"; GEMX="$TP/GEM-X"
export UV_DEFAULT_INDEX="${UV_DEFAULT_INDEX:-https://pypi.tuna.tsinghua.edu.cn/simple}"

command -v uv >/dev/null || { echo "需要 uv: curl -LsSf https://astral.sh/uv/install.sh | sh"; exit 1; }

echo "== a) SONIC 仿真环境 (.venv_sim, py3.10) =="
# cyclonedds 0.10.2 需要 py3.10：这里用 conda 造一个 3.10 解释器（也可用 uv python install 3.10 走代理）
PY310="$SONIC/.venvs/py310/bin/python"
if [ ! -x "$PY310" ]; then
  conda create -y -p "$SONIC/.venvs/py310" python=3.10 >/dev/null
fi
( cd "$SONIC"
  rm -rf .venv_sim
  uv venv .venv_sim --python "$PY310" --prompt gear_sonic_sim
  source .venv_sim/bin/activate
  uv pip install -e "gear_sonic[sim]"
  uv pip install -e external_dependencies/unitree_sdk2_python )

echo "== b) GEM-X 视觉环境 (.venv, py3.11) =="
( cd "$GEMX"
  uv venv .venv --python 3.11
  source .venv/bin/activate
  # torch: 50 系显卡需要 cu128/cu130 构建
  uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
  uv pip install opencv-python pyzmq scipy cloudpickle fvcore iopath pycocotools braceexpand roma "setuptools<75" easydict matplotlib
  uv pip install onnxruntime-gpu onnx onnxconverter-common
  uv pip install -e third_party/soma
  bash scripts/install_env.sh     # gem 本体 + SAM-3D-Body 运行时 + detectron2
)

echo "完成。下一步: bash setup/03_build_deploy.sh"
echo "注意: 若 GEM-X venv 复用了别的环境的 torch（--system-site-packages），"
echo "      必须补装同版本 torchaudio/torchvision，否则 libtorchaudio 动态库报错（见 docs/SETUP_NOTES.md B）"
