#!/usr/bin/env python3
"""离线 SMPL 序列 → SONIC ZMQ Protocol v3 流发布器（摄像头接入前的接口预演）。

严格复刻官方 soma_to_smpl.py (GEM-X→SONIC) 的逐帧约定（不加 ytoz，因为
sample_data 的 pkl 已是 SONIC 训练管线的 Z-up 根局部格式）：
  body_quat    = remove_smpl_base_rot(aa2quat(pose_aa[:, :3]))     (wxyz)
  smpl_joints  = R_inv(body_quat) · (joints[t] - joints[t, 0])     (根局部, Z-up)
  smpl_pose    = 全零 (1,21,3)   —— 官方 GEM-X 路径即如此，主信号是 joints+quat
  wrists       = 全零 (1,6)      —— 协议仅要求腕部索引 23-28 有意义时才填
打包用 gear_sonic 自带的 pack_pose_message（线格式 100% 官方）。

用法:
  ~/workspace/env/envs/isaaclab/bin/python local_scripts/smpl_pkl_to_sonic_v3.py \
      --pkl sample_data/smpl_filtered/walk_forward_amateur_001__A001.pkl [--loop]
部署端（另两个终端）:
  T1: source .venv_sim/bin/activate && python gear_sonic/scripts/run_sim_loop.py
  T2: cd gear_sonic_deploy && bash deploy.sh --cp policy/low_latency/model \
        --obs-config policy/low_latency/observation_config.yaml \
        --input-type zmq --zmq-host localhost --zmq-port 5556 --zmq-topic pose sim
  T2 里按 `]` 启动 → MuJoCo 窗口按 9 落地 → 按 ENTER 进入 ZMQ streaming。
"""
import argparse
import os
import sys
import time
from pathlib import Path

import numpy as np

REPO_ROOT = Path(
    os.environ.get("SONIC_ROOT")
    or str(Path(__file__).resolve().parent.parent / "third_party" / "GEAR-SONIC")
)
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(REPO_ROOT / "gear_sonic" / "examples" / "live_camera_teleop"))

from soma_to_smpl import SonicV3Publisher  # noqa: E402  官方 v3 发布器

import torch  # noqa: E402

from gear_sonic.isaac_utils.rotations import (  # noqa: E402  SONIC 自家旋转工具(wxyz)
    remove_smpl_base_rot,
    smpl_root_ytoz_up,
)
from gear_sonic.trl.utils.torch_transform import (  # noqa: E402  同官方 soma_to_smpl 的 import
    angle_axis_to_quaternion,
    quat_apply,
    quat_inv,
)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pkl", required=True)
    ap.add_argument("--port", type=int, default=5556)
    ap.add_argument("--topic", default="pose")
    ap.add_argument("--fps", type=float, default=0.0, help="0 = 用 pkl 内的 fps")
    ap.add_argument("--loop", action="store_true")
    ap.add_argument("--start", type=int, default=0)
    ap.add_argument("--max-frames", type=int, default=0)
    ap.add_argument("--smooth", type=float, default=0.0, help="EMA 平滑权重 0.6-0.85, 0=关")
    args = ap.parse_args()

    import joblib

    d = joblib.load(args.pkl)
    joints = torch.as_tensor(np.asarray(d["smpl_joints"], dtype=np.float32))    # (T,24,3) Z-up
    pose_aa = torch.as_tensor(np.asarray(d["pose_aa"], dtype=np.float32))       # (T,72)
    fps = float(args.fps or d.get("fps", 50.0))
    T = len(joints)
    print(f"[pkl->v3] {args.pkl}: {T} 帧 @ {fps}fps")

    root_aa = pose_aa.reshape(T, 24, 3)[:, 0, :]                                # 根轴角
    # 严格复刻训练侧 (commands.py:smpl_root_quat_w_*): aa2quat → ytoz(训练配置
    # smpl_y_up=true) → 去 SMPL 基准旋转。三个 checkpoint 的训练配置均为 true。
    root_quat = angle_axis_to_quaternion(root_aa)                               # (T,4) wxyz
    root_quat = smpl_root_ytoz_up(root_quat)                                    # Y-up → Z-up
    body_quat = remove_smpl_base_rot(root_quat, w_last=False)                   # 去 120° 基准
    quat_inv_t = quat_inv(body_quat)                                            # (T,4)

    ema_j = None
    ema_q = None

    def frame(t):
        nonlocal ema_j, ema_q
        # 训练侧 smpl_joints_multi_future_local: quat_apply(quat_inv(root_quat), raw_joints)
        # —— 只旋转、不减去根位置，保持一致。
        j = joints[t]
        j_local = quat_apply(quat_inv_t[t].repeat(j.shape[0], 1), j)            # 根朝向归零
        q = body_quat[t]
        if args.smooth > 0:
            w = args.smooth
            if ema_j is None:
                ema_j, ema_q = j_local.clone(), q.clone()
            else:
                ema_j = w * ema_j + (1 - w) * j_local
                dot = float((ema_q * q).sum())
                q = q if dot >= 0 else -q
                ema_q = w * ema_q + (1 - w) * q
                ema_q = ema_q / (ema_q.norm() + 1e-8)
            j_local, q = ema_j, ema_q
        return j_local.numpy().astype(np.float32), q.numpy().astype(np.float32)

    pub = SonicV3Publisher(port=args.port, topic=args.topic, sonic_root=str(REPO_ROOT))
    print(f"[pkl->v3] 发布 'pose' v3 于 tcp://*:{args.port}；部署端按 ENTER 启用 streaming")
    time.sleep(1.0)
    dt = 1.0 / fps
    sent = 0
    t0 = args.start
    try:
        while True:
            for t in range(t0, T):
                j, q = frame(t)
                pub.publish(
                    {
                        "smpl_joints": j,                                        # (24,3)
                        "body_quat": q,                                          # (4) wxyz
                        "smpl_pose": np.zeros((1, 21, 3), dtype=np.float32),     # 官方即全零
                        "wrists": np.zeros((1, 6), dtype=np.float32),
                    }
                )
                sent += 1
                if t % int(max(1, fps)) == 0:
                    print(f"\r[pkl->v3] 帧 {t + 1}/{T}（已发 {sent}）", end="", flush=True)
                time.sleep(dt)
                if args.max_frames and sent >= args.max_frames:
                    return
            if not args.loop:
                break
            print("\n[pkl->v3] 循环重播")
            t0 = 0
            ema_j = ema_q = None
    except KeyboardInterrupt:
        pass
    finally:
        pub.close()
        print("\n[pkl->v3] 结束")


if __name__ == "__main__":
    main()
