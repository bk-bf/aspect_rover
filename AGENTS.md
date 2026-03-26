<!-- LOC cap: 220 (source: 1100, ratio: 0.20, updated: 2026-03-26) -->
# AGENTS.md — ASPECT Rover Codebase Guide

**Stack:** ROS 2 Jazzy · Gazebo Harmonic · Python · C++ · Docker · uv  
**Overview / architecture:** `.docs/ASPECT.md` · `.docs/ARCHITECTURE.md`  
**Parent deployment docs:** `../.docs/` (ARCHITECTURE, PHILOSOPHY, DECISIONS, ROADMAP)

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

**3. `/clock` bridge lazy** — give it 2–3 s after launch before `ros2 topic echo /clock`.

**4. `cmd_vel` routing** — bridge maps `/model/aspect_rover/cmd_vel` → ROS `/cmd_vel`.
If bridge logs the pass but rover doesn't move: check sim is unpaused (Quirk 2).

**5. dartsim crash** — fixed: spawn z=0.05 m, corrected inertias, flat ground_plane added.
See `.docs/bugs/BUGS.md` (B-009–B-013) and `.docs/DECISIONS.md` (D-011) for details.

**6. LSP false positives** — host has no ROS 2 overlay; `rclpy`, `geometry_msgs`, `launch`,
`ament_*`, `xacro` imports show as unresolved. **Safe to ignore — do not add `# noqa`.**

---

## Code Style — Python

- PEP 8 (flake8, max 99 chars), PEP 257 (pep257). 4-space indent, no tabs.
- Imports: stdlib → third-party → ROS 2/local. One per line, no wildcards.
- Names: `snake_case` files/funcs, `PascalCase` classes, `UPPER_SNAKE_CASE` constants.
- Topics/services: `/snake_case`. Node names: `snake_case`.
- Type annotations on all new nodes. Use `list | None` (3.10+), not `Optional`.
- Logging: `self.get_logger().error/warn/info(...)` — never `print()`.

```python
"""One-line module docstring."""
import rclpy
from rclpy.node import Node


class MyNode(Node):
    """Node docstring."""

    def __init__(self) -> None:
        """Initialise node."""
        super().__init__('my_node')


def main(args: list | None = None) -> None:
    """Entry point."""
    rclpy.init(args=args)
    node = MyNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
```

Full node template: `aspect_control/aspect_control/teleop_node.py`.

## Code Style — C++ / URDF / SDF

- **C++17**: `-Wall -Wextra -Wpedantic`, `#pragma once`, no raw owning pointers.
- **URDF/xacro**: macros for repeated elements, `<inertial>` on every link.
- **SDF 1.9**: never hardcode paths — use `model://` URIs via `GZ_SIM_RESOURCE_PATH`.

---

## Package Configuration

**ament_python:** `package.xml` build_type, test deps (`ament_flake8`, `ament_pep257`, `python3-pytest`), copy tests from `aspect_control`, `resource/<pkg>` marker, `setup.py` data_files.

**ament_cmake:** CMake ≥ 3.8, `-Wall -Wextra -Wpedantic`, `ament_lint_auto` in `BUILD_TESTING`.

---

## Git Workflow

**Commit and push via SSH after every meaningful change.**

```bash
git add .
git commit -m "feat: <description>"
git push origin main          # remote: git@github.com:bk-bf/aspect_rover.git
ssh -T git@github.com         # verify: "Hi bk-bf!..."
```

Prefixes: `feat:` `fix:` `docs:` `refactor:` `test:` `chore:` `wip:`  
Branches: `feature/<name>` or `fix/<name>`. License: Apache 2.0.

---

## AGENTS.md Self-Maintenance

**Agents must keep this file ≤ 200 lines.** After any meaningful session:

- Update commands if they change (launch args, bridge topics, unpause syntax).
- Add new Gazebo quirks as one-liner notes; move prose rationale to `.docs/`.
- Move resolved tech debt out; add new debt to `.docs/bugs/BUGS.md` with a backlink here.
- Trim any section that has grown verbose — extract to `.docs/` and replace with a backlink.
- Update the `<!-- LOC cap -->` date at the top after each edit.

**Do not** let prose rationale accumulate here. This file is for commands and rules agents
need inline. Everything else belongs in `.docs/`.

## Known Technical Debt

See `.docs/bugs/BUGS.md` for full list. Open items:

| Item | Location |
|---|---|
| Copyright headers absent | All source files (linter check skipped) |
| cpplint disabled | `aspect_gazebo/CMakeLists.txt` |
| URDF box geometry only | `aspect_description/urdf/aspect_rover.urdf.xacro` |
| Joy input not yet added | `aspect_control/teleop_node.py` |

## Dependencies

```bash
rosdep install --from-paths src --ignore-src -r -y   # inside container
```

Runtime: `rclpy`, `launch`, `launch_ros`, `ros_gz`, `robot_localization`  
Dev: `ament_flake8`, `ament_pep257`, `ament_lint_auto`, `uv`
