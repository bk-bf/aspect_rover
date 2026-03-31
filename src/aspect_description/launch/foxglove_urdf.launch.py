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
"""Launch robot_state_publisher + foxglove_bridge for headless URDF viewing."""

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration, PythonExpression
from launch_ros.actions import Node
import xacro


def generate_launch_description():
    """Generate headless URDF viewer via Foxglove WebSocket bridge."""
    description_pkg = get_package_share_directory('aspect_description')
    urdf_file = os.path.join(
        description_pkg, 'urdf', 'aspect_rover.urdf.xacro')
    robot_description_content = xacro.process_file(urdf_file).toxml()

    return LaunchDescription([
        DeclareLaunchArgument(
            'port',
            default_value='8765',
            description='WebSocket port exposed by foxglove_bridge'
        ),

        Node(
            package='robot_state_publisher',
            executable='robot_state_publisher',
            name='robot_state_publisher',
            parameters=[{'robot_description': robot_description_content}],
            output='screen'
        ),

        Node(
            package='foxglove_bridge',
            executable='foxglove_bridge',
            name='foxglove_bridge',
            parameters=[{
                'port': PythonExpression(
                    ['int(', LaunchConfiguration('port'), ')']),
            }],
            output='screen'
        ),
    ])
