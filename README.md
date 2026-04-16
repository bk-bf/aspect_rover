# ASPECT — Autonomous Surface Precision Excavation for Celestial Terrain
<!-- LOC cap: 156 (source: 780, ratio: 0.20, updated: 2026-03-26) -->

A ROS 2 Jazzy + Gazebo Harmonic simulation and 1:10 scale physical prototype of a
lunar mining rover for in-situ resource utilization (ISRU). Target: autonomous
regolith excavation ≥5 g/min at <50 W.

**Stack:** ROS 2 Jazzy Jalisco (LTS May 2029) · Gazebo Harmonic · Docker · uv  
**Phase:** 0 — Infrastructure & simulation foundation (2026)  
**Roadmap:** [`.docs/features/open/ROADMAP.md`](.docs/features/open/ROADMAP.md)  
**Architecture:** [`.docs/ARCHITECTURE.md`](.docs/ARCHITECTURE.md)

---

## Quick Start (10 minutes)

### Prerequisites

- Docker Engine ([install](https://docs.docker.com/engine/install/))
- `rocker` — official OSRF GUI wrapper: `uv tool install rocker` (or `pip install rocker`)
- Linux with X11 or Wayland (tested: Ubuntu 24.04, CachyOS/Arch)

> All Python tooling in this project uses [uv](https://docs.astral.sh/uv/)
> instead of `pip` / `python` directly. Install it once:
> ```bash
> curl -LsSf https://astral.sh/uv/install.sh | sh
> ```

### Build the Docker image

```bash
git clone https://github.com/bk-bf/aspect
cd aspect

# Build image (first time: ~10 minutes)
docker build -f .docker/Dockerfile -t aspect:jazzy .
```

### Launch the simulation (with GUI)

```bash
# rocker handles X11/Wayland forwarding and NVIDIA GPU passthrough automatically
rocker --x11 --nvidia --user --volume $(pwd):/workspace aspect:jazzy

# Inside the container — build and launch
colcon build && source install/setup.bash
ros2 launch aspect_bringup launch_lunar_south_pole.py
```

Gazebo Harmonic opens with the lunar south pole heightmap terrain.

### Alternative: docker compose (headless / no GUI)

```bash
docker compose -f .docker/docker-compose.yml up -d
docker compose -f .docker/docker-compose.yml exec aspect_dev bash
```

---

## Project Structure

```
aspect/
├── .docker/
│   ├── Dockerfile            # ROS 2 Jazzy + Gazebo Harmonic + uv
│   ├── docker-compose.yml    # Container orchestration
│   └── entrypoint.sh         # Sources ROS 2 overlay on container start
├── .docs/                    # Planning & architecture documents (Obsidian vault)
│   ├── ASPECT.md
│   ├── Development-Architecture-Proposal.md
│   ├── Execution-Roadmap-2026-2033.md
│   ├── Feasibility-Analysis-2026.md
│   └── Tasks/
│       ├── Yearly/
│       ├── Monthly/
│       └── Weekly/
├── AGENTS.md                 # Guide for AI coding agents
└── src/
    ├── aspect_bringup/       # Launch files
    ├── aspect_description/   # URDF/xacro rover model
    ├── aspect_control/       # Teleoperation node
    ├── aspect_navigation/    # Waypoint navigation node
    └── aspect_gazebo/        # Gazebo worlds & DEM heightmap media
```

---

## Build & Test

All commands run inside the Docker container (after `rocker` / `docker compose exec`).

```bash
# Build entire workspace
colcon build

# Build a single package
colcon build --packages-select aspect_bringup

# Source the install overlay
source install/setup.bash

# Run all tests
colcon test && colcon test-result --verbose

# Run tests for one package
colcon test --packages-select aspect_navigation

# Run a single test file directly (uv manages the pytest invocation)
uv run pytest src/aspect_navigation/test/test_flake8.py -v

# Run linters directly via uv
uv tool run flake8 src/aspect_control/aspect_control/
```

---

## Packages

| Package | Type | Status | Description |
|---|---|---|---|
| `aspect_bringup` | `ament_python` | Active | Launch files |
| `aspect_description` | `ament_cmake` | Active | URDF/xacro rover model (box geometry stub) |
| `aspect_control` | `ament_python` | Active | Teleoperation (`/cmd_vel`); keyboard input pending |
| `aspect_navigation` | `ament_python` | Active | Waypoint nav (`/odometry/filtered` → `/cmd_vel`); `/goto_waypoint` service pending |
| `aspect_gazebo` | `ament_cmake` | Active | Simulation worlds & DEM media |

---

## Hardware Platform (1:10 scale prototype)

| Component | Part |
|---|---|
| Chassis | 3D printed PETG/PLA+, ~15 × 10 × 8 cm |
| Computing | Raspberry Pi 4B+ |
| IMU | GY-521 (MPU-6050) |
| Vision | ESP32-CAM with OpenCV |
| Motors | SG90 servos / Faulhaber 1524 |
| Design base | NASA Open Source Rover (scaled 1:10) |

---

## Development Workflow

### Daily development (laptop)

```bash
# Enter container with GUI
rocker --x11 --user --volume $(pwd):/workspace aspect:jazzy

# Build, test, iterate
colcon build --symlink-install
source install/setup.bash
ros2 launch aspect_bringup launch_lunar_south_pole.py
```

### Cloud GPU (Phase 2+)

```bash
# Same image, no GUI needed — for RL training when implemented
docker run --gpus all aspect:jazzy bash
```

---

## World File Resource Path

The lunar heightmap SDF uses `model://` URIs resolved via `GZ_SIM_RESOURCE_PATH`.
The Dockerfile sets this automatically:

```
GZ_SIM_RESOURCE_PATH=/workspace/install/aspect_gazebo/share/aspect_gazebo
```

If launching outside Docker, export it manually:

```bash
export GZ_SIM_RESOURCE_PATH=$(ros2 pkg prefix aspect_gazebo)/share/aspect_gazebo
```

---

## Dependencies

```bash
# Inside the container
rosdep install --from-paths src --ignore-src -r -y
```

Key runtime: `rclpy`, `launch`, `launch_ros`, `ros_gz`, `robot_localization`  
Key dev: `ament_flake8`, `ament_pep257`, `ament_lint_auto`, `uv`

---

## Partners & Acknowledgments

- ROS 2 and Gazebo communities
- Contributors to the ros_gz packages
- ESA/NASA ISRU Strategic Plans

---

## License

Apache 2.0 — see [LICENSE](LICENSE).
