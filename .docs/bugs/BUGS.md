<!-- LOC cap: 186 (source: 930, ratio: 0.20, updated: 2026-03-30) -->
# BUGS

Known defects and technical debt. Use `B-NNN` IDs. Mark resolved items with date.

---

## Open

- [ ] B-003 — Low — `aspect_description/resource/` directory is empty — harmless for `ament_cmake`
  but leftover from scaffold (`aspect_description/resource/`)
- [ ] B-009 — Low — LSP false positives on host: `rclpy`, `geometry_msgs`, `launch`, `xacro` etc.
  unresolvable without ROS overlay. Do **not** suppress with `# noqa` — will break linter inside
  container. Safe to ignore on host. (All Python source files)
- [ ] B-010 — Medium — Heightmap collision not supported by dartsim — world uses flat `ground_plane`
  for physics; heightmap is visual-only. Rover drives on z=0 plane regardless of terrain.
  (`aspect_gazebo/worlds/lunar_south_pole.world`)
- [ ] B-011 — Low — EKF `/clock` bridge connects lazily: `/clock` stays at `sec: 0` for ~12 s after
  unpause, then catches up. `robot_localization` waits for clock before publishing. Do not sample
  odometry until `/clock sec > 0`. Workaround in `test.sh`: poll `/clock` before drive tests.
  (`aspect_bringup/launch/`)
- [ ] B-016 — Low — `ros2 topic echo --timeout N` (Jazzy) does not function as a receive timeout —
  the flag controls daemon spin time, not how long to wait for a message. Using it with `--once`
  silently returns nothing. Use `timeout N ros2 topic echo ... --once` (shell wrapper) instead.
  (`test.sh`, any script using `ros2 topic echo`)
- [ ] B-017 — Medium — Gazebo Harmonic runs at ~1/30× real-time in headless Docker on this host
  (TX2540m1). Physics ticks are throttled by CPU. Consequence: position-based drive checks
  (`x > 0.05 m`) fail in CI even after 8 s of wall time. Use velocity-based checks
  (`twist.linear.x > threshold`) in tests instead. (`test.sh` T-D1)

---

## Resolved

- [x] B-018 — 2026-03-30 — `aspect_bringup/test/test_copyright.py` stale skip decorator removed;
  flake8-quotes violation fixed; `colcon test` confirmed 9/9 passing, 0 skipped
- [x] B-001 — 2026-03-30 — Apache 2.0 copyright headers added to all source files (T-003 complete)
- [x] B-002 — 2026-03-30 — `ament_copyright` linter re-enabled in all packages (T-004 complete);
  `aspect_bringup` skip decorator also removed (see B-018)
- [x] B-000 — 2026-03-26 — Hardcoded absolute paths in launch file and world SDF — replaced with
  `get_package_share_directory` and `model://` URIs
- [x] B-004 — 2026-03-26 — `teleop_node.py`: keyboard capture not implemented — termios raw-mode
  loop implemented; `w/a/s/d/space/q` keys wired to `/cmd_vel`
- [x] B-005 — 2026-03-26 — `simple_waypoint_nav.py`: `/goto_waypoint` service not exposed —
  `GotoWaypoint.srv` created in `aspect_msgs`; service server implemented and tested
- [x] B-006 — 2026-03-26 — `ros_gz_bridge` added in `launch_lunar_south_pole.py`; bridges
  `/cmd_vel`, `/odometry/raw`, `/joint_states`, `/imu`, `/clock`
- [x] B-007 — 2026-03-26 — Rover URDF spawned at launch via `ros_gz_sim create` node (delayed 3 s);
  `robot_state_publisher` added
- [x] B-008 — 2026-03-26 — Diff-drive + joint-state-publisher + IMU sensor plugins added to
  `aspect_rover.urdf.xacro` as Gazebo extensions
- [x] B-012 — 2026-03-26 — `gz sim` GUI thread crashed in headless container (Qt/OGRE no display)
  and killed the physics server — fixed by adding `-s` (server-only) flag to launch file
- [x] B-013 — 2026-03-26 — `cmd_vel` bridge used wrong Gazebo topic: bridged `/cmd_vel` → Gz
  `/cmd_vel`, but diff-drive listens on `/model/aspect_rover/cmd_vel` — fixed by changing bridge
  argument to `/model/aspect_rover/cmd_vel` with ROS-side remapping
- [x] B-014 — 2026-03-26 — dartsim ODE LCP crash (`assertion d[i]!=0.0` in `_dLDLTRemove`) on
  rover–ground contact — fixed: added flat `ground_plane`, corrected inertia tensors
  (box/cylinder formulas), lowered spawn z from 0.5 m to 0.05 m
- [x] B-015 — 2026-03-26 — `aspect_bringup/setup.py` import order wrong (flake8 I100/I201):
  `from setuptools import setup` before stdlib — fixed to stdlib-first order
