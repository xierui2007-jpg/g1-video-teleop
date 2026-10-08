# GEAR-SONIC Teleop — Webcam/Video → Unitree G1 Real-Time Motion Imitation

[中文](README.zh-CN.md) | **English**

**In one sentence**: turn a human's motion from an ordinary webcam (or a video file) into real-time
whole-body motion of a Unitree G1 humanoid in MuJoCo — running on an 8 GB laptop GPU,
measured at **7.6–7.9 fps** with **5.4 GB peak VRAM**.

This project is an **integration + local-optimization layer** around two NVIDIA open-source
projects (upstream code is unmodified):

| Component | Upstream | Role |
|---|---|---|
| Robot policy + C++ deployment + MuJoCo sim | [NVlabs/GR00T-WholeBodyControl](https://github.com/NVlabs/GR00T-WholeBodyControl) (GEAR-SONIC) | Consumes the human-motion stream, outputs G1 joint targets at 50 Hz |
| Vision reconstruction (video → 3D human) | [NVlabs/GEM-X](https://github.com/NVlabs/GEM-X) | Detect → 2D keypoints → diffusion-lifted 3D → body parameters |
| The glue between them | Upstream's own `gear_sonic/examples/live_camera_teleop/` + this project's scripts | ZMQ Protocol v3 (SMPL motion stream) |

**Key design**: there is **no online IK / retargeting**. The mapping "how a human moves → how the
robot moves" is *learned inside the policy* (a SMPL encoder trained on 130k+ human motions at
training time). At runtime we only ship the human's motion representation over the wire.

```
[Webcam / video]
   │ frames
   ▼
① GEM-X (vision, ~8 fps on this laptop): YOLOX detect → ViTPose 77 keypoints → GEM diffusion denoiser (3D)
   → body params → SMPL 24 joints
   │ ZMQ PUB tcp://*:5556  topic "pose"   (Protocol v3, ~125 ms/frame)
   ▼
② C++ deployment (TensorRT, 50 Hz): merge frames into reference buffer → SMPL encoder (4-frame = 80 ms lookahead)
   → 64-D motion token → 29 joint targets
   │ DDS (loopback, unitree_sdk2 protocol)
   ▼
③ MuJoCo simulation: G1 physics, feeds joint states / IMU back (closed loop)
```

## Quick Start

```bash
# 0) Requirements: Ubuntu 24.04 + NVIDIA GPU (this project was validated on an RTX 5060 Laptop 8 GB)
# 1) Clone upstreams, build envs, compile the deploy binary, build the ViTPose TRT engine
#    (~1–2 h on first run; see docs/SETUP_NOTES.md)
bash setup/00_all.sh

# 2) Run the demo (a video stands in for the webcam; videos loop automatically)
bash scripts/run_teleop.sh demo/videos/sub16_whitechair_033.mp4

# 3) Or use the real webcam (stand 2–3 m back, full body including feet in frame)
bash scripts/run_teleop.sh
```

Windows and keys:
- **GEM webcam** — live reconstruction preview (a person + tracked keypoints).
  **The X button will not close it** — that is an OpenCV (`cv2.imshow`) quirk; press `q` in the window.
- **MuJoCo** — the G1 robot; closing it with X is fine (it also ends the sim process).
- Deployment pane (tmux window `sim:deploy`): `]` start control / `ENTER` toggle stream / `O` e-stop.

## Repository Layout

```
gear-sonic-teleop/
├── setup/                    Installation scripts (first run)
│   ├── 00_all.sh             Run everything
│   ├── 01_clone_upstream.sh  Clone GEAR-SONIC + GEM-X into third_party/
│   ├── 02_envs.sh            Create .venv_sim (py3.10) and the GEM-X venv (py3.11)
│   ├── 03_build_deploy.sh    TensorRT + onnxruntime + mini CUDA → build the C++ deploy binary
│   ├── 04_build_trt_vitpose.sh  Build the ViTPose TRT fp16 engine (3× faster)
│   └── 05_fetch_assets.sh    Download model weights (via hf-mirror)
├── scripts/
│   ├── run_teleop.sh         One-command launcher (sim + deploy + vision), auto-keys, auto-loops videos
│   ├── webcam_stream_teleop.py  Vision entry point (patched: perf switches / stage timing / video looping)
│   └── replay_smpl_pkl.py    Offline SMPL stream replay (for debugging without a camera)
├── tools/
│   └── lfs_pull_media.sh     Fetch git-lfs payloads without the LFS batch API
├── demo/
│   ├── README.md             Demo assets (with license notes)
│   └── videos/               4 demo clips + a screen recording of the robot tracking
├── docs/
│   ├── SETUP_NOTES.md        Every trap we hit (8 GB VRAM tuning, CUDA library mismatch, …)
│   └── PROTOCOL_SMPL_V3.md   SMPL stream protocol & coordinate conventions (read before plugging your own source)
├── third_party/              Upstream repos (cloned in; not committed)
└── LICENSE / THIRD_PARTY.md  Licensing (this project Apache-2.0; upstream attribution in THIRD_PARTY.md)
```

## 8 GB VRAM Optimizations (vs. upstream)

| Problem | Fix | Result |
|---|---|---|
| Denoiser silently fell back to CPU | `onnxruntime-gpu` 1.30 needs CUDA 13; point `LD_LIBRARY_PATH` at the venv's own cu13/cudnn libs | Back on GPU |
| ViTPose-Huge fp32 ONNX: 4.3 GB / 127 ms | Build a TensorRT fp16 engine (`outputs/trt/vitpose.engine`, upstream loads it preferentially) | **2.0 GB / 40 ms** |
| YOLOX defaults to the largest model | Switch to `yolox_m` (`YOLOX_MODEL=m`) | 49 ms → 22 ms |
| Total | — | 1.2 fps → **7.6–7.9 fps** |

## Known Limitations

- **Motion speed follows vision fps**: the robot replays the reference at roughly the rate frames
  arrive (~8 fps here), so it is slightly slower than the source video.
- **Deep-bending motions tend to stumble**: that is the policy's capability edge (upstream even
  shipped a motor-gain patch for it). Start with standing/walking motions.
- **30 fps experience requires a bigger GPU**: run GEM-X on a large-VRAM machine (3090/4090/5090)
  and keep only the deployment + sim on the laptop.
- **Full body required** (including feet), 2–3 m away, even lighting, one person in frame.

## License

This project's code is Apache-2.0. Upstream components, model weights and demo data carry their own
licenses (GEM-X, SOMA-X, SAM-3D-Body, NVIDIA model licenses, the OMOMO academic dataset, …).
**Read [THIRD_PARTY.md](THIRD_PARTY.md) before use or redistribution.**
