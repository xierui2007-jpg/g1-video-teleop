# 安装与踩坑记录（Ubuntu 24.04 / RTX 5060 Laptop 8G 实测）

按 `setup/00_all.sh` 走一遍即可；这里是每个坑的**原因与修法**，出问题时对照排查。

## A. 上游仓库与资产

1. **GitHub 直连不稳** → 用代理或镜像：
   `git clone https://gh-proxy.com/https://github.com/<owner>/<repo>.git`
2. **仓库用 Git LFS 存 mesh/USD**：直接 clone 后 `*.STL`/`*.usd` 是 132 字节的指针文本，
   Isaac Sim 的 URDF 导入器读到假 mesh 会在 `pelvis.tmp.usd` **硬崩**。
   - 有代理：`git lfs pull` 即可
   - 没代理：用 `tools/lfs_pull_media.sh`（从 `media.githubusercontent.com` 按指针直取真身）
3. **GEM-X 子模块**：`soma` 需要 `git lfs pull` 拿人体资产（~169M）；
   `soma-retargeter` 是 SSH 地址且本路径不需要，拉不动可跳过（用
   `git config submodule.third_party/soma-retargeter.url <https地址>` 或忽略报错）。
   `inputs/soma_assets` 必须软链到 `third_party/soma/assets`（**绝对路径**），缺了会在初始化后期崩。
4. **HuggingFace 直连不通** → `export HF_ENDPOINT=https://hf-mirror.com`。

## B. 环境（Python）

| 环境 | 要求 | 原因 |
|---|---|---|
| `third_party/GEAR-SONIC/.venv_sim` | **Python 3.10** | `cyclonedds==0.10.2` 只有 cp310 轮子，其它版本要现编（常失败） |
| GEM-X `.venv` | Python **3.11**（本项目做法）| 与 isaaclab env 的 torch 对齐；也可按官方用 3.12 全新装 |
| 评测环境（可选） | 复用已有 Isaac Sim 环境 | 本机 `isaaclab` 环境版本与 SONIC 要求一致 |

- 混装坑：若 GEM-X venv 用 `--system-site-packages` 复用别的环境的 torch，
  必须补装**同版本**的 `torchaudio/torchvision`，否则加载时
  `libtorchaudio.so` 动态库报错。

## C. 视觉栈（GEM-X）性能与显存

1. **onnxruntime-gpu 1.30 需要 CUDA 13**：若 `LD_LIBRARY_PATH` 指向 CUDA 12 的库，
   CUDA ExecutionProvider 会**静默注册失败、denoiser 掉回 CPU**（表现为极慢）。
   - 修法：用 venv 自带的 cu13/cudnn 库（torch cu130 会带来）：
     `LD_LIBRARY_PATH=$GEMX/.venv/lib/python3.11/site-packages/nvidia/cu13/lib:.../nvidia/cudnn/lib`
2. **ViTPose 是 DINOv3+ViTPose-Huge 巨型模型**：fp32 ONNX 要 4.3G 显存 / 127ms。
   - 修法：编 TensorRT fp16 引擎（`setup/04`），放 `outputs/trt/vitpose.engine`，
     GEM-X 会**优先加载**它 → **2.0G / 40ms**
   - TRT 路径还需要 venv 装 TensorRT 的 python 包（`$TENSORRT_ROOT/python/tensorrt-*-cp311-*.whl`
     与 `tensorrt_lean`/`tensorrt_dispatch` 或对应组合），并让 `$TENSORRT_ROOT/lib` 在
     `LD_LIBRARY_PATH` 里
3. **YOLOX 默认 yolox_x**（49ms）→ 本项目默认 `YOLOX_MODEL=m`（22ms，精度够用）
4. **视频文件默认播完即退**；本项目补丁加了 `--loop-video`（`run_teleop.sh` 对视频源自动开启）
5. **GEM 预览窗点 X 关不掉**：OpenCV(`cv2.imshow`) 不响应窗口管理器关闭事件——
   在预览窗上按 `q`，或 `pkill -f webcam_stream`

## D. C++ 部署端编译

依赖与坑（都在 `setup/03` 里处理）：

- **TensorRT 10.13**（官方要求精确版本；tar 包约 6.5G，解压到 `~/workspace/env/TensorRT`）
- **onnxruntime C++ 1.22**（解压到 `~/.local/onnxruntime`）
- **CUDA 头文件**：`find_package(CUDAToolkit)` 找不到完整 toolkit 时，用 pip 轮子拼一个迷你
  CUDA：`nvidia-cuda-runtime-cu12`（头文件+runtime）+ `nvidia-cuda-nvcc-cu12`（提供
  `crt/host_defines.h`，缺了会 `fatal error: crt/host_defines.h`）
- 系统包：`libyaml-cpp-dev libeigen3-dev libmsgpack-dev libzmq3-dev nlohmann-json3-dev libgtest-dev just`
- 构建：`cd third_party/GEAR-SONIC/gear_sonic_deploy && source scripts/setup_env.sh && just build`
  （或 `cmake -B build && cmake --build build -j`），产物 `target/release/g1_deploy_onnx_ref`

## E. 运行期

- **重启全栈时的 DDS 域冲突**：日志 `ChannelFactory create domain error` →
  旧进程没退干净。先 `pkill -f run_sim_loop; pkill -f g1_deploy`，**等 6 秒**再起
- **tmux 会话冲突**：本项目脚本用独立 socket（`tmux -L sonic`），避免与已有会话打架
- **评测渲染失控**（可选路径）：Isaac Lab 评测默认 `num_eval_episodes=150` 且每个
  episode 都渲染 1080p，必须加 `++algo.config.eval.num_eval_episodes=1`

## F. 8G 显存的账本（实测）

| 占用方 | 显存 |
|---|---|
| 桌面/浏览器基线 | ~1.1G |
| 部署端 TRT | ~2.2G |
| MuJoCo 仿真+窗口 | ~0.3G |
| ViTPose（TRT fp16） | 2.0G |
| denoiser（ONNX fp32） | ~1.3G |
| YOLOX-m | ~0.2G |
| **合计** | **峰值 5.4G / 8.1G** ✅ |

关掉浏览器能再腾 ~1G。想同时上更高帧率/更精细模型，需换大显存机器。

## G. 速率诊断（脚本自带逐段计时）

`scripts/webcam_stream_teleop.py` 每 5 帧打印 `[prof#N]` 行：

```
detect≈35ms  vitpose≈40ms  denoiser≈11ms  decode≈4ms   →  理论 ~11fps，实测 7.6~7.9fps
```

瓶颈在哪一目了然；若 `vitpose` 突然变几百 ms，说明 TRT 引擎没加载（回落 ONNX/PyTorch）。
