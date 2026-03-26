<!-- LOC cap: 160 (source: 800, ratio: 0.20, updated: 2026-03-26) -->
# AGENTS.md — ASPECT Rover Codebase Guide

**Stack:** ROS 2 Jazzy · Gazebo Harmonic · Python · C++ · Docker · uv  
**Overview / architecture:** `.docs/ASPECT.md` · `.docs/ARCHITECTURE.md`  
**Parent deployment docs:** `../.docs/` (ARCHITECTURE, PHILOSOPHY, DECISIONS, ROADMAP)

## Self-Maintenance Rules

Keep this file ≤ LOC cap. After any meaningful session:
- Commands changed? Update them here.
- New quirk discovered? Add a one-liner; prose rationale → `.docs/`.
- Quirk resolved or already in BUGS.md? Remove it from here.
- Section grown verbose? Extract to `.docs/` and replace with a backlink.
- Update the `<!-- LOC cap -->` date after each edit.

## Git Workflow

```bash
git add . && git commit -m "feat: <description>" && git push origin main
ssh -T git@github.com   # verify SSH: "Hi bk-bf!..."
```

Prefixes: `feat:` `fix:` `docs:` `refactor:` `test:` `chore:` `wip:`  
Commit and push via SSH after every meaningful change.

For any significant change (new feature, refactor, multi-file edit), create a worktree
and work there instead of directly on `main`:

```bash
git worktree add ../aspect-<feature> -b feature/<feature>
# work in ../aspect-<feature>, then PR back to main
```

Significant = new package, behaviour change, anything that could break a passing build.

---

## Repository Layout

```
aspect/
├── .docker/          # Dockerfile, docker-compose.yml, entrypoint.sh
├── .docs/            # Planning docs (Obsidian vault — not code)
├── AGENTS.md         # This file
└── src/
    ├── aspect_bringup/     # ament_python — launch files
    ├── aspect_description/ # ament_cmake  — URDF/xacro rover models
    ├── aspect_control/     # ament_python — teleoperation node
    ├── aspect_navigation/  # ament_python — waypoint nav node
    └── aspect_gazebo/      # ament_cmake  — SDF worlds, DEM media
```

---

## Docker Workflow

```bash
# Build image (~10 min first time)
docker build -f .docker/Dockerfile -t aspect:jazzy .

# GUI dev (Gazebo, RViz2) — recommended
rocker --x11 --nvidia --user --volume $(pwd):/workspace aspect:jazzy

# Headless
docker compose -f .docker/docker-compose.yml up -d
docker compose -f .docker/docker-compose.yml exec aspect_dev bash
```

---

## Build / Test / Lint

```bash
# Build
colcon build
colcon build --packages-select <pkg>
colcon build --symlink-install --packages-select <pkg>
source install/setup.bash

# Test
colcon test && colcon test-result --verbose
colcon test --packages-select <pkg>
uv run pytest src/<pkg>/test/test_flake8.py -v

# Lint (always uv tool run — never python -m or bare flake8)
uv tool run flake8 src/<pkg>/<pkg>/
colcon test --packages-select <pkg> --pytest-args -m flake8
colcon test --packages-select <pkg> --pytest-args -m pep257
```

**Always use `uv` instead of `python`, `python3`, or `pip`.**  
`colcon build` manages its own env — do not interfere via uv.

---

## Launch Commands

```bash
ros2 launch aspect_bringup launch_lunar_south_pole.py   # headless sim
ros2 launch aspect_description view_urdf.launch.py
ros2 launch aspect_control teleop.launch.py             # needs -it TTY
ros2 launch aspect_navigation waypoint_nav.launch.py
```

### Gazebo Quirks

**1. Server-only (`-s`)** — launch file already uses `gz sim -s -v 4`. Never remove `-s`
inside headless container (GUI crash kills physics server). For GUI use rocker on host.

**2. Sim starts paused** — unpause after every launch:

```bash
gz service -s /world/lunar_south_pole/control \
  --reqtype gz.msgs.WorldControl --reptype gz.msgs.Boolean \
  --timeout 5000 --req 'pause: false'
# Expected reply: data: true
# Without this: /clock silent, EKF logs "Waiting for clock..."
```

**3. `/clock` bridge lazy** — see B-011 in `.docs/bugs/BUGS.md`; allow ~30 s warmup.

---

## Code Style — Python

- PEP 8 (flake8, max 99 chars), PEP 257 (pep257). 4-space indent, no tabs.
- Imports: stdlib → third-party → ROS 2/local. One per line, no wildcards.
- Names: `snake_case` files/funcs, `PascalCase` classes, `UPPER_SNAKE_CASE` constants.
- Topics/services: `/snake_case`. Node names: `snake_case`.
- Type annotations on all new nodes. Use `list | None` (3.10+), not `Optional`.
- Logging: `self.get_logger().error/warn/info(...)` — never `print()`.
- Node template: `aspect_control/aspect_control/teleop_node.py`.

## Code Style — C++ / URDF / SDF

- **C++17**: `-Wall -Wextra -Wpedantic`, `#pragma once`, no raw owning pointers.
- **URDF/xacro**: macros for repeated elements, `<inertial>` on every link.
- **SDF 1.9**: never hardcode paths — use `model://` URIs via `GZ_SIM_RESOURCE_PATH`.

---

## Package Configuration

**ament_python:** `package.xml` build_type, test deps (`ament_flake8`, `ament_pep257`, `python3-pytest`), copy tests from `aspect_control`, `resource/<pkg>` marker, `setup.py` data_files.

**ament_cmake:** CMake ≥ 3.8, `-Wall -Wextra -Wpedantic`, `ament_lint_auto` in `BUILD_TESTING`.

---

---

## Dependencies

```bash
rosdep install --from-paths src --ignore-src -r -y   # inside container
```

Runtime: `rclpy`, `launch`, `launch_ros`, `ros_gz`, `robot_localization`  
Dev: `ament_flake8`, `ament_pep257`, `ament_lint_auto`, `uv`
