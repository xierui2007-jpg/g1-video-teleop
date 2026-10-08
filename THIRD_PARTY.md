# 第三方组件、数据与许可

本项目只包含**集成代码、补丁、文档与演示素材**；以下上游组件与数据由各自许可约束，未随本仓库分发。

## 上游代码

| 组件 | 仓库 | 许可 | 本项目如何使用 |
|---|---|---|---|
| GEAR-SONIC（机器人策略/部署/仿真） | https://github.com/NVlabs/GR00T-WholeBodyControl | Apache-2.0 | `setup/01` 克隆到 `third_party/GEAR-SONIC`，C++ 部署端按 `setup/03` 编译 |
| GEM-X（单目人体 3D 重建） | https://github.com/NVlabs/GEM-X | Apache-2.0 | `setup/01` 克隆到 `third_party/GEM-X`（含子模块 SOMA-X / sam-3d-body） |
| SOMA-X（人体模型层，GEM-X 子模块） | https://github.com/NVlabs/SOMA-X | 见其仓库 | 由 GEM-X 子模块引入 |
| SAM-3D-Body（网格模型，GEM-X 子模块） | https://github.com/facebookresearch/sam-3d-body | 见其仓库（Meta） | 由 GEM-X 子模块引入 |

## 模型权重（不在本仓库，脚本下载）

| 权重 | 来源 | 许可 |
|---|---|---|
| SONIC 策略（含 low_latency checkpoint） | https://huggingface.co/nvidia/GEAR-SONIC | NVIDIA Open Model License |
| GEM-X 权重（denoiser / ViTPose / SOMA） | https://huggingface.co/nvidia/GEM-X | NVIDIA Open Model License |
| YOLOX / ViTPose 检测与姿态（rtmlib 缓存） | 上游自动下载（OpenMMLab 等） | 各自许可 |

## 演示数据

`demo/videos/` 中的 `sub*.mp4` 来自 **OMOMO 数据集**（Object Motion Guided Human Motion，MPI/ETH 等联合发布）：

- 数据集主页：https://omomo.is.tue.mpg.de/ （学术许可，需同意条款后下载）
- **若要公开分发本项目，请先确认是否可以再分发这些渲染视频；不确定就删除它们，仅保留脚本与说明**
- `g1_smpl_tracking.mp4` 是本项目自己录制的 MuJoCo 效果演示，可自由使用

LAFAN1（Ubisoft La Forge）动捕数据同样有独立许可（CC BY-NC-ND 4.0），本项目未包含其数据。
