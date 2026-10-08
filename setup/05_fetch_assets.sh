#!/usr/bin/env bash
# 05 下载模型权重（走 hf-mirror，国内可用）
#   - SONIC 部署权重: 默认版 + low_latency（遥操作用这个）+ 运动规划器
#   - SONIC 训练 checkpoint + 示例动作（可选，调试用）
#   - GEM-X 权重: 首次运行视觉栈时自动下载（denoiser / SOMA / 检测器）
# 用法: bash setup/05_fetch_assets.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SONIC="$ROOT/third_party/GEAR-SONIC"
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"

HF() { "$ROOT/third_party/GEM-X/.venv/bin/python" -c "
from huggingface_hub import hf_hub_download as d
import sys
d('nvidia/GEAR-SONIC', sys.argv[1], local_dir=sys.argv[2])
" "$1" "$2"; }

cd "$SONIC"
echo "== 部署权重（ONNX + 规划器） =="
for f in config.json observation_config.yaml model_encoder.onnx model_decoder.onnx planner_sonic.onnx; do
  case "$f" in
    planner_sonic.onnx) dest="gear_sonic_deploy/planner/target_vel/V2" ;;
    observation_config.yaml) dest="gear_sonic_deploy/policy/release" ;;
    model_*.onnx) dest="gear_sonic_deploy/policy/release" ;;
    *) dest="gear_sonic_deploy/policy" ;;
  esac
  echo "  ↓ $f"; HF "$f" "$dest"
done

echo "== low_latency（实时遥操作用这个） =="
for f in model_encoder.onnx model_decoder.onnx observation_config.yaml; do
  echo "  ↓ low_latency/$f"; HF "low_latency/$f" "gear_sonic_deploy/policy/low_latency"
done

echo "== 示例动作 + 训练 checkpoint（可选） =="
HF low_latency/last.pt "low_latency" || true
HF sonic_release/last.pt "sonic_release" || true
for f in robot_filtered/210531/walk_forward_amateur_001__A001.pkl \
         smpl_filtered/walk_forward_amateur_001__A001.pkl; do
  HF "sample_data/$f" "sample_data/$(dirname $f)" || true
done

echo "完成。GEM-X 的视觉权重会在首次运行时自动下载（需 HF_ENDPOINT 指向镜像）。"
