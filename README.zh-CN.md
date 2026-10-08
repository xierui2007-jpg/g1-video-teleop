# GEAR-SONIC Teleop — 摄像头/视频 → Unitree G1 实时动作模仿

**中文** | [English](README.md)

**一句话**：把普通摄像头（或一段视频）里人的动作，实时转成宇树 G1 人形机器人在 MuJoCo 里的动作——
本机 8GB 显存笔记本即可跑通，实测 **7.6~7.9 fps**、峰值显存 5.4G。

本项目是 NVIDIA 两个开源项目的**集成与本地优化补丁**（官方代码一行未改）：

| 组件 | 上游 | 作用 |
|---|---|---|
| 机器人策略 + C++ 部署 + MuJoCo 仿真 | [NVlabs/GR00T-WholeBodyControl](https://github.com/NVlabs/GR00T-WholeBodyControl)（GEAR-SONIC） | 吃人体动作流，输出 G1 关节指令（50Hz） |
| 视觉重建（视频→人体 3D） | [NVlabs/GEM-X](https://github.com/NVlabs/GEM-X) | 检测→2D 关键点→扩散模型抬升 3D→人体参数 |
| 两者接线 | 上游自带的 `gear_sonic/examples/live_camera_teleop/` + 本项目脚本 | ZMQ Protocol v3（SMPL 动作流） |

**关键设计**：不需要在线 IK/重定向。"人怎么动 → 机器人怎么动"是训练时学进策略里的（SMPL 编码器），
运行时只搬运人体信息。

```
[摄像头/视频]
   │ 帧
   ▼
① GEM-X（视觉, 本机 ~8fps）: YOLOX 检测 → ViTPose 77 关键点 → GEM 扩散去噪(3D) → 人体参数 → SMPL 24 关节
   │ ZMQ PUB tcp://*:5556  topic "pose"  (Protocol v3, ~125ms/帧)
   ▼
② C++ 部署端（TensorRT, 50Hz）: 帧合并进参考缓冲 → SMPL 编码器(4帧=80ms 前瞻) → 64维动作token → 29 关节目标角
   │ DDS (本机 lo 网卡, unitree_sdk2 协议)
   ▼
③ MuJoCo 仿真: G1 物理仿真, 回传关节状态/IMU 闭环
```

## 快速开始

```bash
# 0) 依赖: Ubuntu 24.04 + NVIDIA 显卡(本项目实测 RTX 5060 Laptop 8G) + 已装 TensorRT 10.13(~/workspace/env/TensorRT)
# 1) 拉上游 + 装环境 + 编译部署端 + 编 ViTPose TRT 引擎（首次约 1~2 小时，见 docs/SETUP_NOTES.md）
bash setup/00_all.sh

# 2) 跑演示（用视频代替摄像头；视频会自动循环播放）
bash scripts/run_teleop.sh demo/videos/sub16_whitechair_033.mp4

# 3) 用真实摄像头（自己站到 2~3 米外、全身入镜含脚）
bash scripts/run_teleop.sh
```

窗口与按键：
- **GEM webcam**：实时重建预览（自己+别人的关键点）。**点 X 关不掉是 OpenCV 的老毛病——在窗口上按 `q` 退出**
- **MuJoCo**：G1 机器人，可直接点 X 关（会一并结束仿真）
- 部署端（tmux 窗口 `sim:deploy`）：`]` 启动控制 / `ENTER` 开关流 / `O` 急停

## 目录结构

```
gear-sonic-teleop/
├── setup/                    安装脚本（拉上游/建环境/编译）
│   ├── 00_all.sh             一键跑全部（首次）
│   ├── 01_clone_upstream.sh  克隆 GEAR-SONIC + GEM-X 到 third_party/
│   ├── 02_envs.sh            建 .venv_sim(py3.10) 与 GEM-X .venv(py3.11)
│   ├── 03_build_deploy.sh    TensorRT + onnxruntime + 编译 C++ 部署端
│   ├── 04_build_trt_vitpose.sh  编 ViTPose 的 TRT fp16 引擎(提速 3 倍)
│   └── 05_fetch_assets.sh    下载模型权重（走 hf-mirror）
├── scripts/
│   ├── run_teleop.sh         一键启动三件套（仿真+部署端+视觉），自动按键、自动循环视频
│   ├── webcam_stream_teleop.py 视觉入口（官方版补丁：性能开关/逐段计时/循环播放）
│   └── replay_smpl_pkl.py    离线回放 SMPL 动作流（不接摄像头时调试用）
├── tools/
│   └── lfs_pull_media.sh     绕过 git-lfs 拉取上游大文件（国内网络用）
├── demo/
│   ├── README.md             演示素材说明（含许可提醒）
│   └── videos/               4 段演示视频 + 一段跟踪录屏
├── docs/
│   ├── SETUP_NOTES.md        本机安装踩坑全集（8G 显存优化、CUDA 库错配等）
│   └── PROTOCOL_SMPL_V3.md   SMPL 动作流协议与坐标约定（接自己数据源时必读）
├── third_party/              上游仓库（clone 进来，不入 git）
└── LICENSE / THIRD_PARTY.md  许可（本项目 Apache-2.0；上游归属见 THIRD_PARTY.md）
```

## 本机 8G 显存做的优化（相对上游）

| 问题 | 修法 | 效果 |
|---|---|---|
| denoiser 静默跑在 CPU | onnxruntime-gpu 1.30 需要 CUDA 13；用对 venv 自带 cu13/cudnn 库 | 回 GPU |
| ViTPose-Huge fp32 ONNX 占 4.3G / 127ms | 编 TensorRT fp16 引擎（`outputs/trt/vitpose.engine`，上游原生优先加载） | **2.0G / 40ms** |
| YOLOX 默认最大号 | 换 `yolox_m`（`YOLOX_MODEL=m`） | 49ms → 22ms |
| 合计 | — | 1.2 fps → **7.6~7.9 fps** |

## 已知限制

- **动作速度 = 视觉帧率**：机器人做动作的快慢取决于重建速度（本机 ~8fps），比原始视频略慢
- **深弯腰类动作易趔趄**：策略能力边界（上游自己为此发过电机增益补丁），建议先用站立/行走类动作
- **要 30fps 流畅体验**：需要把 GEM-X 放到大显存机器（如 3090/4090/5090）上跑，笔记本只跑部署端+仿真
- 需要**全身入镜（含脚）**，2~3 米、光线均匀、画面里只有一个人

## 许可

本项目代码 Apache-2.0。上游组件与模型权重各有其许可（GEM-X、SOMA-X、SAM-3D-Body、NVIDIA 模型许可、
OMOMO 学术数据等），**使用与再分发前请读 [THIRD_PARTY.md](THIRD_PARTY.md)**。
