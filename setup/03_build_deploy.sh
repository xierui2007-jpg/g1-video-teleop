#!/usr/bin/env bash
# 03 编译 C++ 部署端（TensorRT + onnxruntime）
# 前置: 已跑 01/02；磁盘需 ~17G（TensorRT 6.9G + onnxruntime 0.2G）
# 用法: bash setup/03_build_deploy.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SONIC="$ROOT/third_party/GEAR-SONIC"
TRT="${TENSORRT_ROOT:-$HOME/workspace/env/TensorRT}"
ORT="${ONNXRUNTIME_ROOT:-$HOME/.local/onnxruntime}"
CUDA_HOME_MINI="${CUDA_HOME_MINI:-$HOME/.local/cuda12}"
TRT_VER="${TRT_VER:-10.13.2.6}"      # 官方要求 10.13 精确版本
TRT_CUDA="${TRT_CUDA:-12.9}"

echo "== 1) TensorRT $TRT_VER =="
if [ ! -f "$TRT/lib/libnvinfer.so" ]; then
  URL="https://developer.download.nvidia.com/compute/machine-learning/tensorrt/10.13.2/tars/TensorRT-${TRT_VER}.Linux.x86_64-gnu.cuda-${TRT_CUDA}.tar.gz"
  curl -L --retry 10 -C - -o /tmp/trt.tar.gz "$URL"
  mkdir -p "$TRT" && tar -xzf /tmp/trt.tar.gz -C /tmp && \
    cp -a "/tmp/TensorRT-${TRT_VER}/." "$TRT/" && rm -f /tmp/trt.tar.gz
fi
echo "   TRT: $TRT"

echo "== 2) onnxruntime C++ 1.22 =="
if [ ! -d "$ORT/lib" ]; then
  curl -L --retry 5 -o /tmp/ort.tgz \
    https://github.com/microsoft/onnxruntime/releases/download/v1.22.0/onnxruntime-linux-x64-1.22.0.tgz
  mkdir -p "$ORT" && tar -xzf /tmp/ort.tgz -C "$ORT" --strip-components=1 && rm -f /tmp/ort.tgz
fi
echo "   ORT: $ORT"

echo "== 3) 迷你 CUDA（没有完整 toolkit 时用 pip 轮子拼） =="
if [ ! -f "$CUDA_HOME_MINI/include/cuda_runtime.h" ]; then
  pip download nvidia-cuda-runtime-cu12 nvidia-cuda-nvcc-cu12 --no-deps -d /tmp/cudaw -q
  mkdir -p "$CUDA_HOME_MINI/include" "$CUDA_HOME_MINI/lib64"
  for w in /tmp/cudaw/*.whl; do
    python3 -c "import zipfile,sys; zipfile.ZipFile('$w').extractall('/tmp/cudax')"
  done
  cp -rn /tmp/cudax/nvidia/*/include/* "$CUDA_HOME_MINI/include/" 2>/dev/null || true
  ln -sf "$(find /tmp/cudax -name 'libcudart.so.12' | head -1)" "$CUDA_HOME_MINI/lib64/libcudart.so" || true
  ln -sf "$(find /tmp/cudax -name 'libcudart.so.12' | head -1)" "$CUDA_HOME_MINI/lib64/libcudart.so.12" || true
  rm -rf /tmp/cudaw /tmp/cudax
fi
echo "   迷你 CUDA: $CUDA_HOME_MINI"

echo "== 4) 系统依赖（需要 sudo） =="
sudo apt-get install -y build-essential cmake just \
  libyaml-cpp-dev libeigen3-dev libmsgpack-dev libzmq3-dev nlohmann-json3-dev libgtest-dev

echo "== 5) 编译 =="
( cd "$SONIC/gear_sonic_deploy"
  export TensorRT_ROOT="$TRT" onnxruntime_ROOT="$ORT" onnxruntime_DIR="$ORT/lib/cmake/onnxruntime"
  export CUDAToolkit_ROOT="$CUDA_HOME_MINI" CUDA_HOME="$CUDA_HOME_MINI"
  source scripts/setup_env.sh
  cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
  cmake --build build -j"$(nproc)" )

echo "完成。产物: $SONIC/gear_sonic_deploy/target/release/g1_deploy_onnx_ref"
echo "下一步: bash setup/04_build_trt_vitpose.sh"
