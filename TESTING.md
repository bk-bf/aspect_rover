# ASPECT Manual Testing Guide

All testing runs **inside the Docker container**. No ROS 2 is installed on the host.

---

## 0. Enter the container

```bash
# From the repo root on the host:
docker run -it --rm \
  --volume $(pwd):/workspace \
  aspect:jazzy
```

> For GUI (Gazebo, RViz2) use rocker instead:
> `rocker --x11 --nvidia --user --volume $(pwd):/workspace aspect:jazzy`

---

## 1. Build the workspace

```bash
# Inside the container:
colcon build --symlink-install
source install/setup.bash
```

**Pass criteria:**
- No `ERROR` lines in colcon output
- `colcon build` exits 0
- `aspect_msgs`, `aspect_bringup`, `aspect_control`, `aspect_description`,
  `aspect_gazebo`, `aspect_navigation` all listed as `Finished`

---

## 2. Run automated linter tests

```bash
colcon test --packages-select aspect_control aspect_navigation
colcon test-result --verbose
```

**Pass criteria:** all tests pass (flake8, pep257, copyright)

---

## 3. Headless smoke test — verify topics are advertised

In one terminal (inside the container), launch the simulation headless:

```bash
gz sim --headless-rendering -v 4 \
  install/aspect_gazebo/share/aspect_gazebo/worlds/lunar_south_pole.world &
ros2 launch aspect_bringup launch_lunar_south_pole.py
```

In a second container shell (`docker exec -it <container> bash`, then `source /workspace/install/setup.bash`), check topics:

```bash
ros2 topic list
```

**Expected topics (minimum set):**

| Topic | Direction | Notes |
|---|---|---|
| `/cmd_vel` | sub | bridge receives drive commands |
| `/model/aspect_rover/odometry` | pub | raw odometry from diff-drive |
| `/odometry/raw` | pub | relayed from above |
| `/odometry/filtered` | pub | EKF output |
| `/model/aspect_rover/imu` | pub | IMU data |
| `/clock` | pub | sim time |
| `/robot_description` | pub | URDF string |
| `/tf` | pub | TF tree |

---

## 4. Drive the rover manually

With the simulation running, publish a forward velocity command:

```bash
ros2 topic pub --once /cmd_vel geometry_msgs/msg/Twist \
  "{linear: {x: 0.2, y: 0.0, z: 0.0}, angular: {x: 0.0, y: 0.0, z: 0.0}}"
```

Then echo odometry to confirm the rover is moving:

```bash
ros2 topic echo /odometry/filtered --once
```

**Pass criteria:** `pose.pose.position.x` changes from 0.0 after repeated publishes.

Stop the rover:

```bash
ros2 topic pub --once /cmd_vel geometry_msgs/msg/Twist "{}"
```

---

## 5. Test the /goto_waypoint service

```bash
ros2 service call /goto_waypoint aspect_msgs/srv/GotoWaypoint \
  "{x: 2.0, y: 0.0}"
```

**Pass criteria:**
- Response: `success: True`, `message: 'Goal set to (2.00, 0.00)'`
- `/cmd_vel` starts publishing non-zero commands (verify with `ros2 topic echo /cmd_vel`)
- Once the rover reaches the waypoint, `/cmd_vel` returns to zero

---

## 6. Test keyboard teleoperation

In a terminal with a TTY (requires `-it` Docker flag or rocker):

```bash
ros2 run aspect_control teleop_node
```

**Pass criteria:**
- Banner printed with key bindings
- Pressing `w` publishes `{linear: {x: 0.2}}` on `/cmd_vel`
- Pressing `space` publishes zeros
- Pressing `q` exits cleanly, publishes a final zero-velocity stop

---

## Known limitations / not yet testable

| Item | Reason |
|---|---|
| Gazebo GUI / visual rover model | Needs X11 / rocker; box geometry only until T-005 meshes done |
| nav2 costmap | T-010 not yet implemented |
| 30-min stability run | T-107, Phase 1 |
