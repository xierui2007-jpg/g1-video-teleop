#!/usr/bin/env bash
# 04 把 ViTPose 编成 TensorRT fp16 引擎（本机 8G 显存的关键一步）
#   收益: 显存 4.3G→2.0G，耗时 127ms→40ms；GEM-X 会优先加载该引擎
# 前置: 已有 GEM-X 的 ONNX 权重（首次运行 GEM-X 时自动下载，或见 setup/05）
# 用法: bash setup/04_build_trt_vitpose.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEMX="$ROOT/third_party/GEM-X"
TRT="${TENSORRT_ROOT:-$HOME/workspace/env/TensorRT}"

cd "$GEMX"
if [ ! -f inputs/onnx/vitpose.onnx ]; then
  echo "缺 inputs/onnx/vitpose.onnx —— 先跑一次 GEM-X（会自动下载），或手动:"
  echo "  HF_ENDPOINT=https://hf-mirror.com $GEMX/.venv/bin/python -c \\"
  echo "    \"from huggingface_hub import hf_hub_download as d; [d('nvidia/GEM-X', f'onnx/{f}', local_dir='inputs') for f in ('vitpose.onnx','vitpose.onnx.data')]\""
  exit 1
fi

mkdir -p outputs/trt
# 输入 [B,3,256,192] 动态 batch（流式逐帧=1，翻转测试=2）
LD_LIBRARY_PATH="$TRT/lib:$LD_LIBRARY_PATH" "$TRT/bin/trtexec" \
  --onnx=inputs/onnx/vitpose.onnx --fp16 \
  --minShapes=imgs:1x3x256x192 --optShapes=imgs:2x3x256x192 --maxShapes=imgs:32x3x256x192 \
  --saveEngine=outputs/trt/vitpose.engine \
  --memPoolSize=workspace:4096

echo "== 让 GEM-X 的 python 能用 TRT 引擎（TRTRunner 需要 tensorrt python 包） =="
"$GEMX/.venv/bin/pip" install "$TRT"/python/tensorrt-*-cp311-*.whl 2>/dev/null || \
  "$GEMX/.venv/bin/pip" install "$TRT"/python/tensorrt-*.whl

echo "完成。引擎: $GEMX/outputs/trt/vitpose.engine（约 1.6G）"
echo "注意: 运行时需要 LD_LIBRARY_PATH 含 $TRT/lib（scripts/run_teleop.sh 已处理）"
