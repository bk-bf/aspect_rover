# Copyright 2026 Kirill Boychenko
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Launch the ASPECT lunar south pole simulation in Gazebo Harmonic."""

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, ExecuteProcess, TimerAction
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node
import xacro  # noqa: E402 — available only inside ROS 2 install overlay


def generate_launch_description():
    """Generate launch description for the lunar south pole world."""
    gazebo_pkg = get_package_share_directory('aspect_gazebo')
    description_pkg = get_package_share_directory('aspect_description')

    default_world = os.path.join(
        gazebo_pkg, 'worlds', 'lunar_south_pole.world'
    )
    urdf_file = os.path.join(
        description_pkg, 'urdf', 'aspect_rover.urdf.xacro'
    )
    ekf_config = os.path.join(
        get_package_share_directory('aspect_bringup'), 'config', 'ekf.yaml'
    )

    # Process xacro → URDF string at launch time
    robot_description_content = xacro.process_file(urdf_file).toxml()

    world_arg = DeclareLaunchArgument(
        'world',
        default_value=default_world,
        description='Path to the Gazebo world SDF file'
    )

    x_arg = DeclareLaunchArgument(
        'x', default_value='0.0', description='Spawn X position (metres)'
    )
    y_arg = DeclareLaunchArgument(
        'y', default_value='0.0', description='Spawn Y position (metres)'
    )
    z_arg = DeclareLaunchArgument(
        'z', default_value='0.05', description='Spawn Z position (metres)'
    )

    # ── 1. Gazebo Harmonic simulator ──────────────────────────────────────
    # -s = server-only (no GUI); safe for headless/CI environments.
    # Remove -s to launch the full GUI when running interactively with rocker.
    gz_sim = ExecuteProcess(
        cmd=['gz', 'sim', '-s', '-v', '4', LaunchConfiguration('world')],
        output='screen'
    )

    # ── 2. robot_state_publisher ──────────────────────────────────────────
    # Publishes TF from joint states and the URDF.
    robot_state_publisher = Node(
        package='robot_state_publisher',
        executable='robot_state_publisher',
        name='robot_state_publisher',
        output='screen',
        parameters=[{'robot_description': robot_description_content,
                     'use_sim_time': True}]
    )

    # ── 3. Spawn rover into Gazebo ────────────────────────────────────────
    # ros_gz_sim's create node reads robot_description from the parameter
    # server and calls the /world/<world>/create Gazebo service.
    # Delayed 3 s to give gz sim time to initialise the world.
    spawn_rover = TimerAction(
        period=3.0,
        actions=[
            Node(
                package='ros_gz_sim',
                executable='create',
                name='spawn_aspect_rover',
                output='screen',
                arguments=[
                    '-name', 'aspect_rover',
                    '-topic', 'robot_description',
                    '-x', LaunchConfiguration('x'),
                    '-y', LaunchConfiguration('y'),
                    '-z', LaunchConfiguration('z'),
                ]
            )
        ]
    )

    # ── 4. ros_gz_bridge ─────────────────────────────────────────────────
    # Bridges Gazebo ↔ ROS 2 topics.
    # Format: <gz_topic>@<ros_type>[gz_type]
    # Remappings rename the bridged topics to standard ROS 2 names,
    # removing the need for a separate topic_tools relay node.
    ros_gz_bridge = Node(
        package='ros_gz_bridge',
        executable='parameter_bridge',
        name='ros_gz_bridge',
        output='screen',
        parameters=[{'use_sim_time': True}],
        arguments=[
            # cmd_vel: ROS 2 → Gazebo
            # The diff-drive plugin listens on /model/aspect_rover/cmd_vel
            # inside Gazebo; the ROS-side remapping below exposes /cmd_vel.
            '/model/aspect_rover/cmd_vel@geometry_msgs/msg/Twist]gz.msgs.Twist',
            # odometry: Gazebo → ROS 2
            '/model/aspect_rover/odometry'
            '@nav_msgs/msg/Odometry'
            '[gz.msgs.Odometry',
            # joint states: Gazebo → ROS 2 (for TF)
            '/model/aspect_rover/joint_states'
            '@sensor_msgs/msg/JointState'
            '[gz.msgs.Model',
            # IMU: Gazebo → ROS 2
            '/model/aspect_rover/imu'
            '@sensor_msgs/msg/Imu'
            '[gz.msgs.IMU',
            # clock: Gazebo → ROS 2
            '/clock@rosgraph_msgs/msg/Clock[gz.msgs.Clock',
        ],
        remappings=[
            ('/model/aspect_rover/cmd_vel', '/cmd_vel'),
            ('/model/aspect_rover/odometry', '/odometry/raw'),
            ('/model/aspect_rover/joint_states', '/joint_states'),
        ]
    )

    # ── 5. robot_localization EKF ─────────────────────────────────────────
    # Fuses wheel odometry + IMU → /odometry/filtered used by navigation.
    ekf_node = Node(
        package='robot_localization',
        executable='ekf_node',
        name='ekf_node',
        output='screen',
        parameters=[ekf_config, {'use_sim_time': True}],
        remappings=[('odometry/filtered', '/odometry/filtered')]
    )

    return LaunchDescription([
        world_arg,
        x_arg,
        y_arg,
        z_arg,
        gz_sim,
        robot_state_publisher,
        spawn_rover,
        ros_gz_bridge,
        ekf_node,
    ])
