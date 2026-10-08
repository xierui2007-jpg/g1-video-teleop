# SMPL 动作流协议（Protocol v3）与坐标约定

接自己的数据源（别的姿态估计器、录制的动捕、自己的视频管线）时必读。上游文档：
`third_party/GEAR-SONIC/docs/source/tutorials/zmq.md`。

## 消息字段（Protocol v3，`--input-type zmq` 用）

| 字段 | 形状 | 说明 |
|---|---|---|
| `smpl_joints` | `[N,24,3]` | SMPL 24 关节位置，**根局部（root-local）、Z-up** |
| `smpl_pose` | `[N,21,3]` | 身体关节轴角；**官方 GEM-X 路径直接发全零**（主信号是 joints + 根朝向） |
| `joint_pos` | `[N,29]` | G1 关节角，v3 里**只有腕部索引 23~28 有意义**，其余可全零 |
| `joint_vel` | `[N,29]` | 同上，可全零 |
| `body_quat` | `[N,4]` | 根朝向四元数 **wxyz** |
| `frame_index` | `[N]` | 单调递增帧号（用于对齐） |

打包必须用 SONIC 自带的 `pack_pose_message`（1280B header + 二进制 payload），
否则字节级不一致会被拒。本项目脚本已自动使用它。

## 坐标约定（**最容易踩的坑**）

必须严格复刻**训练侧公式**（源码：
`gear_sonic/envs/manager_env/mdp/commands.py` 的 `smpl_root_quat_w_multi_future` +
`.../mdp/observations.py` 的 `smpl_joints_multi_future_local`；三个 checkpoint 的训练配置
均为 `smpl_y_up: true`）：

```
Q = remove_smpl_base_rot(smpl_root_ytoz_up(aa2quat(pose_aa[:, :3])), w_last=False)
smpl_joints 流 = quat_apply(quat_inv(Q), pkl原始joints)    # 只旋转，不减去根位置
body_quat   流 = Q                                          # wxyz
smpl_pose   流 = 全零
```

实测教训（两种错法都会"链路通但姿势全错"）：

- **漏掉 `ytoz`** → G1 拧麻花、姿态诡异
- **整个不做旋转**（直接发原始四元数）→ G1 站立时姿势不对劲、动作不跟随
- 结论：**"消息被解析" ≠ "跟踪正确"**，验收必须看机器人姿势

参考实现见 `scripts/replay_smpl_pkl.py`（离线回放 SONIC 训练管线格式的 pkl）。

## 速率与实时性

- 部署端控制回路固定 **50Hz**，参考动作按 1 帧/节拍消费；视觉若只有 8fps，缓冲会被抽干，
  日志出现 `waiting following motion`——**机器人做动作的速度≈视觉帧率**
- `low_latency` checkpoint 的"4 帧前瞻"是按 **20ms 帧距**训练的；输入帧距越大，时间语义越失真，
  所以要尽量提高视觉帧率（本项目的 TRT 优化就是为了这个）
- 可选字段 `catch_up`（默认 true）：帧间隔过大时重置播放，避免累积延迟
