# ROADMAP

Current phase: **Phase 0** (2026 Q1). Completed items move to [`../archive/README.md`](../archive/README.md).

---

## Open

### Priority 1 — Phase 0: Make the Simulation Driveable

> Goal: wire up the full ROS 2 ↔ Gazebo loop so the rover can actually be driven
> in simulation. Currently the world launches but no model is spawned, no bridge
> connects `/cmd_vel` to the sim, and no drive plugin is in the SDF.
> Blocks everything in Phase 1.

- [x] T-007 [`aspect_bringup`]: Wire up `ros_gz_bridge` for `/cmd_vel` and `/odometry/filtered`
- [x] T-008 [`aspect_gazebo`]: Add differential drive plugin to `lunar_south_pole.world` *(note: NASA DEM heightmap is visual-only — dartsim skips heightmap collision; rover drives on a flat `ground_plane` at z=0)*
- [x] T-009 [`aspect_bringup`]: Spawn rover URDF model in simulation at launch
- [x] T-006 [`aspect_bringup`]: Add `robot_localization` EKF node to bringup launch

### Priority 2 — Phase 0: Complete Package Stubs

> Goal: finish the scaffolded nodes so the packages are functional, not just
> compilable. Copyright headers unblock the linter re-enable.
>
> Parallel tracks:
> - **Track A — linter hygiene** (T-003 → T-004): sequential pair, no external deps
> - **Track B — nav2 foundation** (T-010): independent of Track A; touches different packages
>
> T-003/T-004 and T-010 can run in separate worktrees simultaneously.

- [x] T-001 [`aspect_control`]: Implement keyboard input in `teleop_node.py` (termios raw mode)
- [x] T-002 [`aspect_navigation`]: Expose `/goto_waypoint` service in `simple_waypoint_nav.py`
- [ ] T-003 [all]: Add Apache 2.0 copyright headers to all source files missing them
- [ ] T-004 [all]: Re-enable `ament_copyright` linter check once T-003 is done
- [x] T-010 [`aspect_navigation`]: Add nav2 costmap + basic global planner

### Priority 3 — Phase 1: Simulation & AI (2026 Q2-Q3)

> Goal: rover autonomously excavates 50 g+ regolith in simulation at ≥ 80% success
> rate. TRL-3. Requires Priority 1 complete.
>
> Parallel tracks:
> - **Track A — sim/nav** (T-101 → T-105 → T-107): nav2 integration, then terrain tuning,
>   then stability CI; each step gates the next
> - **Track B — hardware-model + RL** (T-102 → T-103 → T-104): scoop URDF, then gym env,
>   then baseline PPO; sequential within the track, independent of Track A
> - **Track C — EKF validation** (T-106): needs sim running (T-101 unblocks it) but does not
>   depend on nav2 planner output; can run alongside T-105
>
> T-103 and T-104 depend on both T-101 (sim must be navigable) and T-102 (scoop must exist),
> so Track B cannot fully start until T-101 is done. T-102 alone can start immediately.

- [ ] T-101 [`aspect_navigation`]: Nav2 stack integration (costmap, global + local planner)
- [ ] T-102 [`aspect_description`]: Excavation scoop URDF + articulation joint
- [ ] T-103 [`aspect_gazebo`]: gymnasium environment wrapping Gazebo sim *(implements D-007 — gymnasium + SB3 framework choice; needs T-101 + T-102)*
- [ ] T-104: Baseline PPO training — SB3 Zoo defaults *(CPU-only proof-of-concept; goal is to validate gym env + reward function before GPU spend — see D-007, D-008; needs T-103)*
- [ ] T-105: Lunar terrain Nav2 parameter tuning *(needs T-101)*
- [ ] T-106 [`aspect_bringup`]: Sensor fusion — wheel odometry + IMU via EKF validated in sim *(needs T-101; parallel with T-105)*
- [ ] T-107: 30-minute stability test passing in CI *(needs T-101, T-105, T-106)*

### Priority 4 — Phase 2: Hardware V1 + RL Production Training (2026 Q3–2027 Q1)

> Goal: physical 1:10 prototype driving in lab; RL policy achieving 20 g+ excavation
> in simulation. TRL-4. Cloud GPU budget ~$80.
>
> Parallel tracks (per D-010):
> - **Track A — hardware chain** (T-201 → T-202 → T-203 → T-204 → T-205): each step
>   depends on the previous; builds up to full EKF fusion on real hardware
> - **Track B — RL production** (T-206 → T-207): cloud GPU migration, then hyperparam
>   search; sequential within the track, independent of Track A
>
> T-208 (field trial) needs both tracks complete — it is the join point for this phase.

- [ ] T-201: RPi 4B bring-up with ROS 2 Jazzy
- [ ] T-202: GY-521 IMU driver node *(needs T-201)*
- [ ] T-203: Faulhaber 1524 / SG90 motor driver node *(needs T-201)*
- [ ] T-204: ESP32-CAM ROS 2 video stream *(needs T-201)*
- [ ] T-205: EKF fusion — wheel odometry + IMU on hardware *(needs T-202, T-203)*
- [ ] T-206: Cloud GPU migration (Vast.ai / RunPod); checkpoint auto-save to HF Hub *(executes D-008 gates 2–3; implements D-009 model storage)*
- [ ] T-207: Hyperparameter search (SB3 Zoo ablations, 10 runs) *(blocked by D-008 budget gate — do not start until T-206 complete and $80 budget confirmed; needs T-206)*
- [ ] T-208: Backyard excavation trial with regolith analog (≥ 5 g/min target) *(needs T-205 + T-207)*

### Priority 5 — Phase 3: Integrated ISRU Prototype (2027 Q2–2028 Q1)

> Goal: end-to-end water extraction demonstrated on bench. TRL-4 → TRL-5.
> 1:5 scale chassis. Cloud GPU budget ~$155. Requires T-208 field data.
>
> Parallelism at this horizon is not yet planned in detail — dependencies will be
> mapped when Phase 2 is within one quarter of completion.

- [ ] T-301: 1:5 scale chassis with Faulhaber motors throughout
- [ ] T-302: Heated auger thermal extraction subsystem
- [ ] T-303: Cold trap water capture system
- [ ] T-304: Small-scale electrolysis module (target: 1-5 g/hr H₂)
- [ ] T-305: Computer vision for ice-rich regolith detection
- [ ] T-306: Multi-scenario RL training (varied terrain, sensor noise, lighting)
- [ ] T-307: Domain randomisation for sim-to-real transfer
- [ ] T-308: > 50 g H₂O extraction per run validated

### Priority 6 — Phase 4: Extreme Environment Validation (2028)

> Goal: TRL-5. 72-hour autonomous operation demonstrated in Svalbard (-40 °C) and
> Atacama Desert. Requires funded partnerships for lab access.

- [ ] T-401: Sensor fusion for multi-modal data integration
- [ ] T-402: Fault-tolerant autonomous operation framework
- [ ] T-403: Arctic testing — Svalbard 168-hour continuous run
- [ ] T-404: Desert trials — Atacama thermal and solar validation
- [ ] T-405: Thermal-vacuum chamber testing at partner facility
- [ ] T-406: Full-scale (1:1) excavation subsystem (5-10 kg/hr regolith)

### Priority 7 — Phase 5: Scale-Up & Commercial Integration (2029)

> Goal: TRL-6. Mission-relevant performance metrics. H₂ production rate sufficient
> for propellant depot feasibility study. Requires $2-5M funding (SBIR/STTR).

- [ ] T-501: Full-scale system < 500 W total power consumption
- [ ] T-502: Partner with commercial electrolysis provider (OxEon or equiv. TRL-5+)
- [ ] T-503: Integrated system test: 10-20 g/hr H₂ production rate
- [ ] T-504: SBIR/STTR Phase I proposal submission

### Priority 8 — Phases 6-7: Mission Design & Lunar Demonstration (2030-2033)

> Goal: TRL-7-9. Secure CLPS contract; flight-qualify system; execute first robotic
> lunar H₂ production. Requires NASA/commercial contract. See
> [FEASIBILITY-2026.md](../../research/FEASIBILITY-2026.md) for funding pathway.

- [ ] T-601: NASA CLPS proposal (lunar surface demonstration)
- [ ] T-602: Flight-qualified design, mass budget < 100 kg
- [ ] T-603: Preliminary Design Review (PDR) with industry partners
- [ ] T-701: Engineering qualification model (EQM) manufacture
- [ ] T-702: Flight model (FM) + vibration/thermal-vac qualification
- [ ] T-703: Lunar surface ops: excavation → water extraction → electrolysis → H₂ storage
- [ ] T-704: Target: 1-5 kg total H₂ produced during 90-day surface mission

---

## Sprints

### Week 1 — February 15-21, 2026

**WEEK OVERVIEW:**
Phase 0 infrastructure setup (Week 1-2). Establish Docker-based ROS 2 Jazzy + Gazebo Harmonic development environment using rocker for GUI. Create basic rover URDF model and GitHub repository. Follows [Architecture v2.0](../../Development-Architecture-Proposal.md) Docker-first strategy.

**STATUS:** Week 1 of 4 (February) | Phase 0 Infrastructure (Week 1/2)

---

#### 1.1 Docker Development Environment Setup

**Priority:** CRITICAL | **Phase:** 0.1 | **Dependencies:** None (fresh start)

##### Overview:
Establish Docker-based ROS 2 Jazzy + Gazebo Harmonic development environment using rocker (official OSRF tool) for seamless GUI integration on CachyOS + Wayland. This enables 10-minute collaborator onboarding and ensures laptop→cloud portability.

##### Tasks:
- [ ] **TASK-1.1.1:** Install Docker and rocker on CachyOS
  - **Method:** Install Docker Engine + rocker for ROS container management
  - **Install Docker:**
    ```bash
    # Install Docker on CachyOS (Arch-based)
    sudo pacman -S docker docker-compose

    # Start and enable Docker service
    sudo systemctl enable --now docker

    # Add user to docker group (logout/login required)
    sudo usermod -aG docker $USER

    # Verify installation
    docker --version
    docker run hello-world
    ```
  - **Install rocker:**
    ```bash
    # rocker is a Python package
    pip install rocker

    # Verify installation
    rocker --version
    ```
  - **Document:** Note Docker version + confirm no errors
  - **Deliverable:** Docker functional, user in docker group, rocker installed

- [ ] **TASK-1.1.2:** Test ROS 2 Jazzy base container
  - **Method:** Run official ROS 2 Jazzy container from OSRF registry
  - **Pull and test base image:**
    ```bash
    # Pull official ROS 2 Jazzy Desktop image
    docker pull osrf/ros:jazzy-desktop

    # Test basic ROS 2 functionality (no GUI)
    docker run --rm osrf/ros:jazzy-desktop ros2 --version

    # Expected output: ros2 doctor jazzy
    ```
  - **Verify:** Command runs without errors, shows "jazzy" version
  - **Deliverable:** Confirmed ROS 2 Jazzy container works

- [ ] **TASK-1.1.3:** Test rocker GUI forwarding with Gazebo
  - **Method:** Use rocker to run Gazebo Harmonic with X11/Wayland forwarding
  - **Test Gazebo GUI on host:**
    ```bash
    # Run Gazebo Harmonic with GUI (rocker handles X11/Wayland)
    rocker --x11 --user osrf/ros:jazzy-desktop gz sim shapes.sdf

    # Gazebo window should open on your CachyOS desktop
    # Test: Rotate view, insert models, verify 30+ FPS
    ```
  - **Troubleshoot if needed:**
    - Wayland users: `rocker --x11 --env WAYLAND_DISPLAY=$WAYLAND_DISPLAY ...`
    - Check `echo $DISPLAY` is set (usually `:0` or `:1`)
    - Verify no permission errors in terminal output
  - **Verify:** Gazebo GUI opens natively on CachyOS, no SSH/VNC needed
  - **Benchmark:** Note FPS with your laptop GPU (AMD/Intel integrated)
  - **Deliverable:** Working rocker X11 forwarding, Gazebo GUI functional

- [ ] **TASK-1.1.4:** Create custom ASPECT Docker image
  - **Method:** Build Dockerfile with ROS 2 + Gazebo + project dependencies
  - **Create workspace directory:**
    ```bash
    mkdir -p ~/aspect_ws
    cd ~/aspect_ws
    ```
  - **Create Dockerfile:**
    ```dockerfile
    # ~/aspect_ws/Dockerfile
    FROM osrf/ros:jazzy-desktop

    # Install Gazebo Harmonic and ROS-Gazebo bridge
    RUN apt-get update && apt-get install -y \
        gz-harmonic \
        ros-jazzy-ros-gz \
        ros-jazzy-joint-state-publisher-gui \
        python3-pip \
        git \
        wget \
        && rm -rf /var/lib/apt/lists/*

    # Install Python dependencies (for RL training later)
    RUN pip3 install --no-cache-dir \
        numpy \
        matplotlib

    # Set up workspace
    RUN mkdir -p /workspace/src
    WORKDIR /workspace

    # Source ROS 2 in bashrc
    RUN echo "source /opt/ros/jazzy/setup.bash" >> /root/.bashrc

    # Entry point
    CMD ["/bin/bash"]
    ```
  - **Build custom image:**
    ```bash
    cd ~/aspect_ws
    docker build -t aspect:jazzy .

    # Build time: 5-10 minutes (downloads packages)
    ```
  - **Test custom image:**
    ```bash
    rocker --x11 --user aspect:jazzy ros2 --version
    ```
  - **Verify:** Build completes without errors, image is ~3-4 GB
  - **Deliverable:** aspect:jazzy Docker image ready for development

- [ ] **TASK-1.1.5:** Create docker-compose.yml for workflow
  - **Method:** Define docker-compose for easy container management
  - **Create docker-compose.yml:**
    ```yaml
    # ~/aspect_ws/docker-compose.yml
    version: '3.8'

    services:
      aspect_dev:
        image: aspect:jazzy
        container_name: aspect_dev
        volumes:
          - ./:/workspace
          - /tmp/.X11-unix:/tmp/.X11-unix:rw
        environment:
          - DISPLAY=${DISPLAY}
          - QT_X11_NO_MITSHM=1
        network_mode: host
        stdin_open: true
        tty: true
        command: /bin/bash
    ```
  - **Test workflow:**
    ```bash
    # Start container in background
    docker-compose up -d

    # Enter container with rocker
    rocker --x11 --user --volume ~/aspect_ws:/workspace aspect:jazzy

    # Inside container: Test ROS 2
    ros2 run demo_nodes_cpp talker

    # Open new terminal, enter same container:
    rocker --x11 --user --volume ~/aspect_ws:/workspace aspect:jazzy
    ros2 run demo_nodes_cpp listener

    # Should see messages flowing
    ```
  - **Verify:** Two containers can communicate, ROS 2 DDS discovery works
  - **Deliverable:** Docker Compose workflow documented

- [ ] **TASK-1.1.6:** Create ROS 2 workspace inside container
  - **Method:** Initialize colcon workspace in Docker volume
  - **Workspace setup (inside container):**
    ```bash
    # Enter container
    rocker --x11 --user --volume ~/aspect_ws:/workspace aspect:jazzy

    # Inside container:
    cd /workspace
    mkdir -p src

    # Create packages
    cd src
    ros2 pkg create --build-type ament_cmake aspect_description
    ros2 pkg create --build-type ament_cmake aspect_gazebo
    ros2 pkg create --build-type ament_cmake aspect_control
    ros2 pkg create --build-type ament_python aspect_navigation

    # Build workspace
    cd /workspace
    colcon build
    source install/setup.bash

    # Verify
    ros2 pkg list | grep aspect
    ```
  - **Create .gitignore:**
    ```bash
    # On host (~/aspect_ws/.gitignore)
    cat > ~/aspect_ws/.gitignore << EOF
    build/
    install/
    log/
    *.pyc
    __pycache__/
    .docker/
    EOF
    ```
  - **Verify:** Packages build successfully, workspace structure clean
  - **Deliverable:** Colcon workspace ready for rover model development

---

#### 1.2 Basic Rover URDF Model

**Priority:** HIGH | **Phase:** 1.2 | **Dependencies:** 1.1 complete (workspace setup)

##### Overview:
Create basic 4-wheel differential drive rover URDF with collision/visual meshes. Foundation for all subsequent simulation work.

##### Tasks:
- [ ] **TASK-1.2.1:** Design rover chassis specifications
  - **Method:** Define physical parameters for 1:10 scale rover
  - **Specifications:**
    - **Dimensions:** 15cm (L) × 10cm (W) × 8cm (H) - fits on desk for testing
    - **Wheelbase:** 10cm (front-rear), 8cm (left-right)
    - **Wheel diameter:** 4cm (realistic for 1:10 scale)
    - **Mass budget:** 500g total (chassis: 200g, wheels: 4×25g, electronics: 200g)
    - **Ground clearance:** 2cm (sufficient for lunar rocks simulation)
  - **Document:** Create `docs/design/ROVER_SPECIFICATIONS.md` with detailed specs
  - **Reference:** NASA Open Source Rover scaled down to 1:10
  - **Deliverable:** Complete specification sheet ready for URDF implementation

- [ ] **TASK-1.2.2:** Create basic chassis URDF
  - **Method:** Write URDF XML defining rover rigid body structure
  - **File location:** `aspect_description/urdf/aspect_rover.urdf.xacro`
  - **URDF structure:**
    ```xml
    <?xml version="1.0"?>
    <robot name="aspect_rover" xmlns:xacro="http://www.ros.org/wiki/xacro">
      <!-- Base link (chassis center) -->
      <link name="base_link">
        <visual>
          <geometry>
            <box size="0.15 0.10 0.08"/>
          </geometry>
          <material name="blue">
            <color rgba="0.2 0.2 0.8 1.0"/>
          </material>
        </visual>
        <collision>
          <geometry>
            <box size="0.15 0.10 0.08"/>
          </geometry>
        </collision>
        <inertial>
          <mass value="0.2"/>
          <inertia ixx="0.0001" ixy="0.0" ixz="0.0" iyy="0.0001" iyz="0.0" izz="0.0001"/>
        </inertial>
      </link>

      <!-- Add footprint link for navigation -->
      <link name="base_footprint"/>
      <joint name="base_joint" type="fixed">
        <parent link="base_footprint"/>
        <child link="base_link"/>
        <origin xyz="0 0 0.04" rpy="0 0 0"/>
      </joint>

      <!-- Wheels will be added in TASK-1.2.3 -->
    </robot>
    ```
  - **Test:** Load in RViz2: `ros2 launch aspect_description view_urdf.launch.py`
  - **Verify:** Robot displays correctly, no TF errors
  - **Deliverable:** Basic chassis URDF loading in RViz2

- [ ] **TASK-1.2.3:** Add 4-wheel differential drive joints
  - **Method:** Add wheel links and continuous joints to URDF
  - **Implementation:** Use xacro macros for wheel duplication
  - **Wheel macro example:**
    ```xml
    <xacro:macro name="wheel" params="prefix parent reflect_lr reflect_fb">
      <link name="${prefix}_wheel_link">
        <visual>
          <geometry>
            <cylinder radius="0.02" length="0.015"/>
          </geometry>
          <material name="black">
            <color rgba="0.1 0.1 0.1 1.0"/>
          </material>
        </visual>
        <collision>
          <geometry>
            <cylinder radius="0.02" length="0.015"/>
          </geometry>
        </collision>
        <inertial>
          <mass value="0.025"/>
          <inertia ixx="0.00001" ixy="0.0" ixz="0.0" iyy="0.00001" iyz="0.0" izz="0.00001"/>
        </inertial>
      </link>

      <joint name="${prefix}_wheel_joint" type="continuous">
        <parent link="${parent}"/>
        <child link="${prefix}_wheel_link"/>
        <origin xyz="${reflect_fb*0.05} ${reflect_lr*0.055} 0" rpy="1.5708 0 0"/>
        <axis xyz="0 0 1"/>
      </joint>
    </xacro:macro>

    <!-- Instantiate 4 wheels -->
    <xacro:wheel prefix="front_left" parent="base_link" reflect_lr="1" reflect_fb="1"/>
    <xacro:wheel prefix="front_right" parent="base_link" reflect_lr="-1" reflect_fb="1"/>
    <xacro:wheel prefix="rear_left" parent="base_link" reflect_lr="1" reflect_fb="-1"/>
    <xacro:wheel prefix="rear_right" parent="base_link" reflect_lr="-1" reflect_fb="-1"/>
    ```
  - **Verify:** All 4 wheels appear in RViz2, joints movable with joint_state_publisher_gui
  - **Deliverable:** Complete 4-wheel rover model with movable joints

- [ ] **TASK-1.2.4:** Add IMU and camera sensors to URDF
  - **Method:** Add sensor links and Gazebo sensor plugins
  - **IMU sensor:**
    ```xml
    <!-- IMU link (mounted on chassis top) -->
    <link name="imu_link">
      <visual>
        <geometry>
          <box size="0.01 0.01 0.005"/>
        </geometry>
      </visual>
    </link>
    <joint name="imu_joint" type="fixed">
      <parent link="base_link"/>
      <child link="imu_link"/>
      <origin xyz="0 0 0.045" rpy="0 0 0"/>
    </joint>

    <!-- Gazebo IMU plugin -->
    <gazebo reference="imu_link">
      <sensor name="imu_sensor" type="imu">
        <always_on>true</always_on>
        <update_rate>100</update_rate>
        <imu>
          <angular_velocity>
            <x><noise type="gaussian"><stddev>0.01</stddev></noise></x>
            <y><noise type="gaussian"><stddev>0.01</stddev></noise></y>
            <z><noise type="gaussian"><stddev>0.01</stddev></noise></z>
          </angular_velocity>
          <linear_acceleration>
            <x><noise type="gaussian"><stddev>0.1</stddev></noise></x>
            <y><noise type="gaussian"><stddev>0.1</stddev></noise></y>
            <z><noise type="gaussian"><stddev>0.1</stddev></noise></z>
          </linear_acceleration>
        </imu>
      </sensor>
    </gazebo>
    ```
  - **Camera sensor:**
    ```xml
    <!-- Camera link (front-mounted) -->
    <link name="camera_link">
      <visual>
        <geometry>
          <box size="0.015 0.03 0.01"/>
        </geometry>
      </visual>
    </link>
    <joint name="camera_joint" type="fixed">
      <parent link="base_link"/>
      <child link="camera_link"/>
      <origin xyz="0.08 0 0.04" rpy="0 0.1 0"/>
    </joint>

    <!-- Gazebo camera plugin -->
    <gazebo reference="camera_link">
      <sensor name="camera" type="camera">
        <always_on>true</always_on>
        <update_rate>30</update_rate>
        <camera>
          <horizontal_fov>1.047</horizontal_fov>
          <image>
            <width>640</width>
            <height>480</height>
            <format>R8G8B8</format>
          </image>
          <clip>
            <near>0.05</near>
            <far>100</far>
          </clip>
        </camera>
      </sensor>
    </gazebo>
    ```
  - **Verify:** Sensors appear in URDF, links present in RViz2
  - **Note:** Plugin functionality tested in Gazebo (Week 2)
  - **Deliverable:** Rover URDF with IMU and camera sensor definitions

- [ ] **TASK-1.2.5:** Create Gazebo spawn launch file
  - **Method:** Write ROS 2 launch file to spawn rover in Gazebo
  - **File location:** `aspect_gazebo/launch/spawn_rover.launch.py`
  - **Launch file content:**
    ```python
    from launch import LaunchDescription
    from launch.actions import IncludeLaunchDescription
    from launch.launch_description_sources import PythonLaunchDescriptionSource
    from launch_ros.actions import Node
    from ament_index_python.packages import get_package_share_directory
    import os

    def generate_launch_description():
        gazebo_pkg = get_package_share_directory('ros_gz_sim')
        description_pkg = get_package_share_directory('aspect_description')
        urdf_file = os.path.join(description_pkg, 'urdf', 'aspect_rover.urdf.xacro')

        gazebo = IncludeLaunchDescription(
            PythonLaunchDescriptionSource([
                os.path.join(gazebo_pkg, 'launch', 'gz_sim.launch.py')
            ]),
            launch_arguments={'gz_args': '-r empty.sdf'}.items()
        )

        spawn_rover = Node(
            package='ros_gz_sim',
            executable='create',
            arguments=['-name', 'aspect_rover', '-file', urdf_file,
                       '-x', '0.0', '-y', '0.0', '-z', '0.1'],
            output='screen'
        )

        robot_state_publisher = Node(
            package='robot_state_publisher',
            executable='robot_state_publisher',
            parameters=[{'robot_description': urdf_file}],
            output='screen'
        )

        return LaunchDescription([gazebo, spawn_rover, robot_state_publisher])
    ```
  - **Create simple test world:** `aspect_gazebo/worlds/empty.sdf` (flat ground plane)
  - **Test:** `ros2 launch aspect_gazebo spawn_rover.launch.py`
  - **Verify:** Rover spawns in Gazebo, sits on ground without falling through
  - **Deliverable:** Working launch file spawning rover in empty Gazebo world

- [ ] **TASK-1.2.6:** Validate rover model physics
  - **Test scenarios:**
    - Rover spawns at z=0.1m, falls to ground and stabilizes (no bouncing/jitter)
    - Wheels make contact with ground plane
    - No collision geometry errors in Gazebo console
    - Robot doesn't tip over when spawned
  - **Tune physics parameters if needed:** friction coefficients, contact damping
  - **Document:** Take screenshots of rover in Gazebo from multiple angles
  - **Deliverable:** Stable rover model with validated physics in Gazebo

---

#### 1.3 Project Infrastructure & GitHub

**Priority:** MEDIUM | **Phase:** 0.2 | **Dependencies:** 1.1 complete (Docker setup)

##### Tasks:
- [ ] **TASK-1.3.1:** Initialize Git repository and GitHub remote
- [ ] **TASK-1.3.2:** Create README with Docker onboarding (10-minute setup)
- [ ] **TASK-1.3.3:** Create GitHub Actions CI/CD pipeline (Docker build + colcon test)
- [ ] **TASK-1.3.4:** Set up rosdep and dependency management
- [ ] **TASK-1.3.5:** Create development workflow documentation

#### Week 1 Completion Checklist

- [ ] Docker + rocker installed and functional on CachyOS (1.1)
- [ ] aspect:jazzy Docker image builds successfully (1.1)
- [ ] rocker X11 forwarding works — Gazebo GUI opens on host (1.1)
- [ ] ROS 2 workspace built inside Docker container (1.1)
- [ ] Basic rover URDF model spawns in Gazebo (1.2)
- [ ] All 4 wheels present with correct joints (1.2)
- [ ] IMU and camera sensor definitions added to URDF (1.2)
- [ ] GitHub repository created with Docker files (1.3)
- [ ] README includes 10-minute Docker onboarding instructions (1.3)
- [ ] GitHub Actions CI pipeline passes (1.3)

#### Week 1 Notes & Progress Tracking

- **Mon 2/17:** _1.1.1, 1.1.2 (Docker + rocker installation, image pull)_
- **Tue 2/18:** _1.1.3, 1.1.4 (rocker GUI test, custom Dockerfile build)_
- **Wed 2/19:** _1.1.5, 1.1.6, 1.2.1 (docker-compose, workspace setup, chassis URDF)_
- **Thu 2/20:** _1.2.3, 1.2.4 (wheels + sensors)_
- **Fri 2/21:** _1.2.5, 1.2.6 (launch file + physics validation)_
- **Weekend:** _1.3.x (project infrastructure) — can slip to Week 2 if needed_

**Blockers & Issues:** _Document any Docker/rocker issues, GPU passthrough problems, container networking errors_

**Week Review:**
- **Completed Tasks:** [ ] Dev environment fully functional  [ ] Basic rover model working  [ ] Git repository established
- **Challenges:** _What took longer than expected?_
- **Lessons Learned:** _Technical insights, workflow improvements_

---

### Week 2 — February 22-28, 2026

**WEEK OVERVIEW:**
Generate lunar terrain from NASA DEM data and implement teleoperation system for basic rover locomotion. By end of week, rover should be keyboard-controllable on realistic lunar surface.

**STATUS:** Week 2 of 4 (February) | Milestone 1 Week 2 of 16 (2026)

---

#### 2.1 Lunar Terrain Generation

**Priority:** HIGH | **Phase:** 1.2 | **Dependencies:** Week 1 complete (working Gazebo setup)

##### Tasks:
- [ ] **TASK-2.1.1:** Download NASA LRO DEM data for South Pole region
  - **Target region:** South Pole permanently shadowed crater (Shackleton or similar)
  - **Resolution:** Download highest available (5-10m/pixel ideal)
  - **Format:** GeoTIFF or IMG format compatible with GDAL
  - **Deliverable:** Raw DEM file saved to `aspect_gazebo/data/dems/south_pole_raw.tif`

- [ ] **TASK-2.1.2:** Process DEM to Gazebo-compatible heightmap
  - **Script location:** `aspect_gazebo/scripts/process_dem.py`
  - **Processing steps:** crop to 1km × 1km, resample to 1m/pixel, normalize to 0-255 grayscale PNG
  - **Deliverable:** `lunar_terrain_heightmap.png` ready for Gazebo

- [ ] **TASK-2.1.3:** Create Gazebo world file with lunar terrain
  - **File location:** `aspect_gazebo/worlds/lunar_terrain.sdf`
  - **World structure:** heightmap + lunar texture, realistic lighting, lunar regolith physics
  - **Test:** `gz sim lunar_terrain.sdf`
  - **Deliverable:** Functional lunar terrain world file

- [ ] **TASK-2.1.4:** Test rover physics on lunar terrain
  - **Test scenarios:** spawns without falling through, handles 15° slopes, no tunneling
  - **Deliverable:** Validated rover+terrain integration

---

#### 2.2 Basic Locomotion & Teleoperation

**Priority:** HIGH | **Phase:** 1.2 | **Dependencies:** 2.1 complete, Week 1 (rover URDF)

##### Tasks:
- [ ] **TASK-2.2.1:** Configure Gazebo differential drive plugin
  - **Plugin configuration:**
    ```xml
    <!-- Add to aspect_rover.urdf.xacro -->
    <gazebo>
      <plugin filename="gz-sim-diff-drive-system" name="gz::sim::systems::DiffDrive">
        <left_joint>front_left_wheel_joint</left_joint>
        <left_joint>rear_left_wheel_joint</left_joint>
        <right_joint>front_right_wheel_joint</right_joint>
        <right_joint>rear_right_wheel_joint</right_joint>
        <wheel_separation>0.08</wheel_separation>
        <wheel_diameter>0.04</wheel_diameter>
        <max_linear_velocity>0.5</max_linear_velocity>
        <max_angular_velocity>1.0</max_angular_velocity>
        <topic>/cmd_vel</topic>
        <odom_topic>/odom</odom_topic>
        <frame_id>odom</frame_id>
        <child_frame_id>base_footprint</child_frame_id>
      </plugin>
    </gazebo>
    ```
  - **Test:** `ros2 topic pub /cmd_vel geometry_msgs/Twist "{linear: {x: 0.2}, angular: {z: 0.0}}"`
  - **Deliverable:** Functional diff drive control via /cmd_vel topic

- [ ] **TASK-2.2.2:** Implement keyboard teleoperation node
  - **File location:** `aspect_control/scripts/teleop_keyboard.py`
  - **Controls:** W/S forward/backward, A/D turn, Space stop
  - **Deliverable:** Teleoperation working smoothly

- [ ] **TASK-2.2.3:** Configure odometry and TF transforms
  - **Expected TF tree:** `odom → base_footprint → base_link → wheels/sensors`
  - **Test accuracy:** Drive rover in square pattern, check position drift
  - **Deliverable:** Accurate odometry providing position feedback

- [ ] **TASK-2.2.4:** Create integrated launch file for teleoperation
  - **File location:** `aspect_gazebo/launch/teleop_lunar.launch.py`
  - **Components:** Gazebo + lunar terrain, rover spawn, robot state publisher, teleop node
  - **Deliverable:** `ros2 launch aspect_gazebo teleop_lunar.launch.py` fully functional

- [ ] **TASK-2.2.5:** Validate locomotion performance on lunar terrain
  - **Performance metrics:** odometry drift <5% over 50m, max stable slope >15°, latency <100ms, FPS >30
  - **Deliverable:** Performance validation report

#### Week 2 Completion Checklist

- [ ] Lunar terrain heightmap generated from NASA DEM data (2.1)
- [ ] Gazebo world file with lunar terrain functional (2.1)
- [ ] Rover physics validated on terrain (2.1)
- [ ] Differential drive controller working (2.2)
- [ ] Keyboard teleoperation responsive (2.2)
- [ ] Odometry publishing accurate position data (2.2)
- [ ] Integrated launch file tested (2.2)

**Critical Deliverables:** `lunar_terrain.sdf`, `teleop_lunar.launch.py`, teleoperation demo video (30s)

#### Week 2 Progress Notes

- **Mon 2/22:** — **Tue 2/23:** — **Wed 2/24:** — **Thu 2/25:** — **Fri 2/26:** — **Weekend:**

**Blockers & Issues:** _Document problems here_

---

### Week 3 — March 1-7, 2026

**WEEK OVERVIEW:**
Integrate sensor suite (IMU data fusion, camera visualization) and implement basic waypoint navigation system. Foundation for autonomous navigation AI in March/April.

**STATUS:** Week 3 of 4 (February/March) | Milestone 1 Week 3 of 16 (2026)

---

#### 3.1 Sensor Integration & Fusion

**Priority:** HIGH | **Phase:** 1.3 | **Dependencies:** Week 2 complete (terrain + teleoperation working)

##### Tasks:
- [ ] **TASK-3.1.1:** Verify IMU sensor data publication
  - **Check:** `ros2 topic list | grep imu` and `ros2 topic echo /imu/data --once`
  - **Expected:** orientation (quaternion), angular velocity, linear acceleration at ~100Hz
  - **Deliverable:** IMU publishing clean data at target rate

- [ ] **TASK-3.1.2:** Configure robot_localization for sensor fusion
  - **Create EKF config:** `aspect_control/config/ekf.yaml`
  - **Fuse:** odometry (x, y, velocity) + IMU (orientation, angular velocity)
  - **Test:** compare `/odometry/filtered` vs `/odom` during driving
  - **Deliverable:** Fused odometry with reduced drift

- [ ] **TASK-3.1.3:** Configure camera sensor and image visualization
  - **Check:** `ros2 run rqt_image_view rqt_image_view` → select `/camera/image_raw`
  - **Verify:** 640×480, 30fps, live feed of lunar terrain
  - **Deliverable:** Live camera feed visualized in RViz2

- [ ] **TASK-3.1.4:** Create comprehensive RViz2 configuration
  - **RViz elements:** TF tree, camera image panel, odometry path trail, IMU orientation arrow
  - **Save:** `aspect_description/rviz/rover_view.rviz`
  - **Deliverable:** Polished RViz2 configuration for telemetry monitoring

---

#### 3.2 Basic Waypoint Navigation

**Priority:** HIGH | **Phase:** 1.3 | **Dependencies:** 3.1 complete (sensor fusion working)

##### Tasks:
- [ ] **TASK-3.2.1:** Create simple waypoint navigation node (Python)
  - **File location:** `aspect_navigation/aspect_navigation/simple_waypoint_nav.py`
  - **Logic:** accept (x, y) waypoint → compute bearing → command `/cmd_vel` → stop within 0.5m
  - **Interfaces:** sub `/odometry/filtered`, pub `/cmd_vel`, service `/goto_waypoint`
  - **Deliverable:** Basic waypoint navigation working

- [ ] **TASK-3.2.2:** Implement obstacle detection and avoidance (basic)
  - **Approach:** stop if slope >20°; basic stop-and-replan, no complex avoidance yet
  - **Deliverable:** Basic safety check preventing dangerous navigation

- [ ] **TASK-3.2.3:** Create waypoint visualization and interface
  - **Implementation:** RViz2 interactive markers; accept 2D Pose Estimate clicks; draw path line
  - **Deliverable:** User-friendly waypoint setting interface

- [ ] **TASK-3.2.4:** Test multi-waypoint navigation sequence
  - **Test:** 5 waypoints forming 50m square; complete <5 min, final error <2m
  - **Deliverable:** Validated multi-waypoint navigation

- [ ] **TASK-3.2.5:** Implement emergency stop and safety systems
  - **Safety features:** Ctrl+C safe shutdown, waypoint timeout, tilt detection (roll/pitch >30°)
  - **Deliverable:** Robust safety systems preventing rover damage

#### Week 3 Completion Checklist

- [ ] IMU and camera sensors publishing data correctly (3.1)
- [ ] EKF sensor fusion improving odometry accuracy (3.1)
- [ ] RViz2 configuration displaying all telemetry (3.1)
- [ ] Waypoint navigation functional for single waypoints (3.2)
- [ ] Multi-waypoint sequence tested successfully (3.2)
- [ ] Safety systems (e-stop, timeout, tilt detection) implemented (3.2)

**Critical Deliverables:** `simple_waypoint_nav.py`, RViz2 config, demo video (rover navigating to 5 waypoints)

#### Week 3 Progress Notes

- **Sat 3/1:** — **Sun 3/2:** — **Mon 3/3:** — **Tue 3/4:** — **Wed 3/5:** — **Thu 3/6:** — **Fri 3/7:**

**Blockers & Issues:** _Document problems here_

---

### Week 4 — March 8-14, 2026

**WEEK OVERVIEW:**
Final week of February milestone. Focus on stability testing, performance benchmarking, comprehensive documentation, and demo preparation. Consolidate month's work and prepare for March milestone (Nav2 integration).

**STATUS:** Week 4 of 4 (February/March) | Milestone 1 Week 4 of 16 (2026)

---

#### 4.1 System Stability & Performance Testing

**Priority:** HIGH | **Phase:** 1.4 | **Dependencies:** Weeks 1-3 complete (all systems functional)

##### Tasks:
- [ ] **TASK-4.1.1:** Extended simulation runtime testing
  - **Procedure:** full system launch + 10+ waypoint navigation sequence for 30+ min; monitor CPU, memory, FPS, node health
  - **Success criteria:** 30+ min with no crashes, stable FPS >30
  - **Deliverable:** 30-minute stability test passed

- [ ] **TASK-4.1.2:** Stress testing with complex terrain
  - **Scenarios:** 20° slopes, rough terrain, crater rim, permanently shadowed region
  - **Failure modes to check:** tipping, collision detection failures, physics glitches
  - **Deliverable:** Terrain stress test with documented limitations

- [ ] **TASK-4.1.3:** Performance benchmarking and optimization
  - **Targets:** >30 FPS, <4GB memory, IMU 100Hz, Camera 30Hz, Odom 50Hz
  - **Document:** `docs/performance/BASELINE_METRICS.md`
  - **Deliverable:** Performance baseline documented

- [ ] **TASK-4.1.4:** Bug fixing and stability improvements
  - **Priority:** Fix all P0 (crashes) and P1 (navigation failures) bugs; document P2/P3 in GitHub Issues
  - **Deliverable:** System stable with no known critical bugs

---

#### 4.2 Comprehensive Documentation

**Priority:** HIGH | **Phase:** 1.4 | **Dependencies:** System tested and stable

##### Tasks:
- [ ] **TASK-4.2.1:** Write detailed setup guide — `docs/setup/INSTALLATION_GUIDE.md`
- [ ] **TASK-4.2.2:** Document system architecture — `docs/design/ARCHITECTURE.md` (block + data flow diagrams)
- [ ] **TASK-4.2.3:** Write 4 usage tutorials — teleop, waypoint nav, sensor monitoring, rosbag
- [ ] **TASK-4.2.4:** Create troubleshooting guide — `docs/TROUBLESHOOTING.md`
- [ ] **TASK-4.2.5:** Update main README with February achievements and demo video link

---

#### 4.3 Demo Preparation & Milestone Validation

**Priority:** HIGH | **Phase:** 1.4 | **Dependencies:** System stable, documentation complete

##### Tasks:
- [ ] **TASK-4.3.1:** Record demonstration video (3 min max: RViz, terrain, teleop, waypoint nav, sensor viz)
- [ ] **TASK-4.3.2:** Validate February milestone completion against all 7 deliverables
- [ ] **TASK-4.3.3:** Create March milestone preparation plan (Nav2 integration, weeks 5-8)

#### Week 4 Completion Checklist

- [ ] 30-minute stability test passed (4.1)
- [ ] Performance benchmarks documented (4.1)
- [ ] All critical bugs fixed (4.1)
- [ ] Installation guide tested by external person (4.2)
- [ ] Architecture documentation complete (4.2)
- [ ] 4 usage tutorials written (4.2)
- [ ] Troubleshooting guide created (4.2)
- [ ] Main README updated (4.2)
- [ ] Demo video recorded and uploaded (4.3)
- [ ] All 7 monthly deliverables validated (4.3)

**Critical Deliverables:** demo video URL, complete `docs/` set, README reflecting February achievements, March plan

#### Week 4 Progress Notes

- **Sat 3/8:** — **Sun 3/9:** — **Mon 3/10:** — **Tue 3/11:** — **Wed 3/12:** — **Thu 3/13:** — **Fri 3/14:**

**Blockers & Issues:** _Document problems here_

#### February Milestone Retrospective

- **Achievements:** _What went well?_
- **Challenges:** _What was harder than expected?_
- **Technical Learnings:** _Key technical insights_
- **March Preparation:**
  - [ ] February code committed and tagged (v0.1.0-february)
  - [ ] Documentation reviewed and polished
  - [ ] March roadmap refined based on lessons learned
  - [ ] Confidence level for March: Low / Medium / High
