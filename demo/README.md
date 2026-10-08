# 演示素材说明

## 视频列表（按动作难度）

| 文件 | 动作 | 难度 | 说明 |
|---|---|---|---|
| `sub11_trashcan_027.mp4` | 站立持小物 | ★ 低 | 推荐首次跑通时用 |
| `sub16_whitechair_033.mp4` | 椅子旁站立/微动 | ★ 低 | 推荐首次跑通时用 |
| `sub12_woodchair_008.mp4` | 站立提椅子 | ★★ 中 | |
| `sub10_largebox_093.mp4` | 深弯腰搬大箱 | ★★★ 高 | 深弯腰接近策略能力边界，容易趔趄，用来观察极限 |

> ⚠️ **上面 4 段 `sub*.mp4` 来自 OMOMO 数据集（学术许可），不随本仓库分发**（已在 .gitignore 中排除）。
> 想复现同样的测试：从 <https://omomo.is.tue.mpg.de/> 按学术许可获取，或直接用你自己的全身视频。
| `g1_smpl_tracking.mp4` | —— | —— | 本项目录制的效果演示（MuJoCo 里 G1 跟踪 SMPL 动作流） |

## 怎么用

```bash
# 视频在 scripts/run_teleop.sh 里会自动循环播放（短视频可反复看）
bash scripts/run_teleop.sh demo/videos/sub16_whitechair_033.mp4
```

## 来源与许可（重要）

- `sub*.mp4` 来自 **OMOMO 数据集**（https://omomo.is.tue.mpg.de/ ，学术许可）。
  本项目只把它们当"测试输入"用；**如果要公开分发本仓库，请先确认能否再分发这些渲染视频，
  不确定就删掉这个目录里的 sub*.mp4**（脚本和文档不依赖它们）。
- `g1_smpl_tracking.mp4` 是本项目自录，可自由使用。

## 想用自己的视频？

任何"一个人、全身入镜（含脚）、2~3 米、光线均匀"的视频都可以直接喂：

```bash
bash scripts/run_teleop.sh /path/to/你的视频.mp4
```

拍摄要领：镜头保持水平、别裁掉腿脚（下半身是机器人保持平衡的依据）、画面里只留一个人。
