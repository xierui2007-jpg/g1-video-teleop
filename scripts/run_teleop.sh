#!/bin/bash
# 一键(重)启摄像头→G1 实时遥操作三件套（tmux 会话 sim: 0=仿真 1=部署 2=摄像头）
# 用法: bash local_scripts/run_teleop.sh [视频文件]
#   不带参数 = 实时摄像头;  带视频路径 = 用视频代替摄像头(测 OMOMO 等素材)
# 之后: 站到摄像头前 2~3 米、全身入镜（含脚）→ 机器人跟着你动
#       部署端按键: ] 启动控制 | ENTER 开关流 | I 重置朝向 | 9(MuJoCo窗) 落地 | O 急停
set -e
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${SONIC_ROOT:-$PROJECT_ROOT/third_party/GEAR-SONIC}"
GEMX="${GEMX_ROOT:-$PROJECT_ROOT/third_party/GEM-X}"
TRT="${TENSORRT_ROOT:-$HOME/workspace/env/TensorRT}"
# 库路径(顺序重要):
#   TensorRT/lib  → ViTPose 的 TRT fp16 引擎 (outputs/trt/vitpose.engine, 40ms/帧 vs ONNX fp32 127ms)
#   venv cu13     → onnxruntime-gpu 1.30 需要 CUDA 13 (用 isaaclab 的 cu12 会让 CUDA EP 注册失败、denoiser 掉 CPU)
# 自动探测 venv 里的 CUDA 库目录（cu13 或 cu12）+ cudnn，兼容不同 torch 版本
NV=$GEMX/.venv/lib/python*/site-packages/nvidia
CU_LIB=$(ls -d $NV/cu1*/lib 2>/dev/null | tail -1)
CUDNN_LIB=$(ls -d $NV/cudnn/lib 2>/dev/null | tail -1)
LDP=$TRT/lib:${CU_LIB}:${CUDNN_LIB}
SOURCE="${1:-0}"
# 视频文件解析成绝对路径（视觉进程的 cwd 不在项目根，相对路径会失效）
LOOP=""
case "$SOURCE" in
  ''|*[!0-9]*)  # 非纯数字 => 视频文件
    SOURCE="$(cd "$(dirname "$SOURCE")" && pwd)/$(basename "$SOURCE")"
    LOOP="--loop-video" ;;
esac

TMUX="tmux -L sonic"
$TMUX kill-server 2>/dev/null || true
sleep 1
$TMUX new-session -d -s sim -c $REPO
$TMUX send-keys -t sim "source $REPO/.venv_sim/bin/activate && python gear_sonic/scripts/run_sim_loop.py 2>&1 | tee $REPO/logs/sim_live.log" Enter
$TMUX new-window  -t sim -n deploy -c $REPO/gear_sonic_deploy
$TMUX send-keys -t sim:deploy "export TensorRT_ROOT=\$HOME/workspace/env/TensorRT LD_LIBRARY_PATH=\$HOME/workspace/env/TensorRT/lib:\$HOME/.local/onnxruntime/lib:\$HOME/.local/cuda12/lib64:\$LD_LIBRARY_PATH; ./target/release/g1_deploy_onnx_ref lo policy/low_latency/model_decoder.onnx reference/example --obs-config policy/low_latency/observation_config.yaml --encoder-file policy/low_latency/model_encoder.onnx --input-type zmq --zmq-host localhost --zmq-port 5556 --zmq-topic pose --disable-crc-check 2>&1 | tee $REPO/logs/deploy_live.log" Enter
$TMUX new-window  -t sim -n cam -c $GEMX
$TMUX send-keys -t sim:cam "source $GEMX/.venv/bin/activate && export GEMX_ROOT=$GEMX SONIC_ROOT=$REPO HF_ENDPOINT=${HF_ENDPOINT:-https://hf-mirror.com} YOLOX_MODEL=m LD_LIBRARY_PATH=$LDP:\$LD_LIBRARY_PATH && python $PROJECT_ROOT/scripts/webcam_stream_teleop.py --source '$SOURCE' --resolution 1280x720 --cap-fps 30 --stream-sonic --window 30 --smooth 0.8 $LOOP --show 2>&1 | tee $GEMX/logs_cam_teleop_live.log" Enter

echo "等待部署端 Init Done..."
for i in $(seq 1 20); do
  sleep 5
  if $TMUX capture-pane -t sim:deploy -p 2>/dev/null | grep -q "Init Done"; then break; fi
done
$TMUX send-keys -t sim:deploy "]"          # 启动控制
sleep 2
WID=$(DISPLAY=:0 xdotool search --name "MuJoCo : g1" | tail -1)
DISPLAY=:0 xdotool windowactivate $WID 2>/dev/null; sleep 1
DISPLAY=:0 xdotool key --window $WID 9    # 落地
sleep 2
$TMUX send-keys -t sim:deploy Enter        # 启用 ZMQ streaming
echo "完成！摄像头流已接通。退到 2~3 米外全身入镜即可让 G1 跟你动。"
echo "窗口: GEM webcam(你+关键点) | MuJoCo(G1)。急停按部署端 O。"
