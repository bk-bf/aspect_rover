<!-- LOC cap: 282 (source: 1410, ratio: 0.20, updated: 2026-03-30) -->
# TESTING

All testing runs **inside the Docker container**. See `AGENTS.md` for container entry commands.

> **Headless note:** `gz sim -s` (server-only) is used inside the container.
> The Gazebo server starts **paused** — unpause with:
> ```bash
> gz service -s /world/lunar_south_pole/control \
>   --reqtype gz.msgs.WorldControl --reptype gz.msgs.Boolean \
>   --timeout 5000 --req 'pause: false'
> ```

---

## Prerequisites

> Enter the container, build, and source before any test step below.

```bash
colcon build --symlink-install && source install/setup.bash
```

Pass: all 6 packages (`aspect_msgs`, `aspect_bringup`, `aspect_control`,
`aspect_description`, `aspect_gazebo`, `aspect_navigation`) finish with no `ERROR`.

---

## T-L1 — Linter

```bash
colcon test --packages-select aspect_bringup aspect_control aspect_navigation
colcon test-result --verbose
```

Pass: flake8, pep257, copyright all green.

---

## T-S1 — Topic smoke test

```bash
ros2 launch aspect_bringup launch_lunar_south_pole.py
# in a second shell:
ros2 topic list
```

Pass: all topics present.

| Topic | Type |
|---|---|
| `/cmd_vel` | `geometry_msgs/Twist` |
| `/odometry/raw` | `nav_msgs/Odometry` |
| `/model/aspect_rover/imu` | `sensor_msgs/Imu` |
| `/clock` | `rosgraph_msgs/Clock` |
| `/tf` | `tf2_msgs/TFMessage` |

---

## T-N1 — Nav2 stack smoke test

```bash
ros2 launch aspect_navigation nav2.launch.py &
sleep 10
ros2 action list
```

Pass: `/navigate_to_pose` and `/navigate_through_poses` action servers present.

---

## T-A1 — Auger joint state topic

Verifies that Gazebo publishes both auger joints after T-102 URDF is loaded.

```bash
ros2 launch aspect_bringup launch_lunar_south_pole.py
# second shell:
ros2 topic echo /joint_states --once | grep -E 'auger'
```

Pass: `auger_feed_joint` and `auger_rotation_joint` both appear in the `name:` array.

*Automated by `test.sh` T-A1 block.*

---

## T-A2 — Auger joints at initial retracted position

Confirms the prismatic feed joint starts at 0.0 (fully retracted) and the
rotation joint starts at 0.0 (stationary at sim start).

```bash
# Using test_helpers.py directly:
python3 src/aspect_scripts/test_helpers.py \
    joint_state_field auger_feed_joint position /joint_states
# Expected: 0.0

python3 src/aspect_scripts/test_helpers.py \
    joint_state_field auger_rotation_joint position /joint_states
# Expected: 0.0
```

Pass: both positions are `≈ 0.0` (absolute value < 0.001).

*Automated by `test.sh` T-A2 block.*

---

## T-D1 — Manual drive

```bash
# Unpause first (see above), then:
ros2 topic pub --rate 10 /cmd_vel geometry_msgs/msg/Twist \
  "{linear: {x: 0.2}, angular: {z: 0.0}}"
ros2 topic echo /odometry/raw --once
```

Pass: `pose.pose.position.x` non-zero after publish.

---

## T-D2 — Waypoint service

```bash
ros2 launch aspect_navigation waypoint_nav.launch.py &
ros2 service call /goto_waypoint aspect_msgs/srv/GotoWaypoint "{x: 2.0, y: 0.0}"
ros2 topic echo /cmd_vel --once
```

Pass: service returns `success: true`; `/cmd_vel` publishes non-zero until goal reached.

---

## T-D3 — Keyboard teleop

```bash
ros2 run aspect_control teleop_node   # requires -it TTY
```

Pass: `w` → forward velocity on `/cmd_vel`; `space` → zeros; `q` → clean exit + zero stop.

---

## Results

| Test | Date | Result | Notes |
|---|---|---|---|
| Prerequisites (build) | 2026-03-26 | PASS | 6 packages, 0 errors |
| T-L1 linter | 2026-03-30 | PASS | 9 tests, 0 failures, 0 skipped — copyright enabled and passing in all packages (B-018 resolved) |
| T-S1 topic smoke | 2026-03-26 | PASS | 5 topics confirmed |
| T-D1 manual drive | 2026-03-26 | PASS | x=0.659m after 5s at 0.2m/s |
| T-D2 waypoint service | 2026-03-26 | PASS | `success=True`; cmd_vel linear.x=0.2 |
| T-D3 keyboard teleop | — | SKIP | Requires interactive TTY; not automatable |

| T-A1 auger joint topics | — | — | Requires container + T-102 URDF |
| T-A2 auger initial position | — | — | Requires container + T-102 URDF |

### Known issues / fixes made during testing

| Issue | Fix |
|---|---|
| `cmd_vel` bridge mapped wrong Gz topic | Changed bridge arg to `/model/aspect_rover/cmd_vel` |
| `gz sim` GUI crash killed server | Added `-s` (server-only) flag to launch file |
| Physics crash (dartsim ODE assert) | Added flat ground plane; corrected box/cylinder inertia |
| Sim starts paused in server-only mode | Document `gz service` unpause step above |
| `aspect_bringup/setup.py` import order | Fixed: `from glob import glob` before `import os` |
| T-L1 grep pattern wrong | `colcon test-result` emits `"Summary: …0 errors, 0 failures…"`; fixed pattern |
| T-D2 service grep wrong | `ros2 service call` prints `success=True` (repr); fixed to `success[=:] ?True` |
| T-D2 service call hung | No timeout on `ros2 service call`; added `timeout 10` + service-ready poll |
| T-D2 cmd_vel race | Topic echo ran before nav node reacted; added `sleep 2` after service call |

---

## Not yet testable

| Item | Blocker |
|---|---|
| Gazebo GUI / meshes | T-005 (no real URDF meshes yet) |
| EKF `/odometry/filtered` | Requires clock to stabilise (~12 s); bridge lazy-connects |
| nav2 costmap | T-010 complete; T-N1 smoke test result pending (run in container) |
| 30-min stability | T-107, Phase 1 |
| Auger `/excavation/cmd` response | T-103 (gym env wires up AugerCmd subscriber) — T-A3 planned |
