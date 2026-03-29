# Copyright 2026 Kirill Boychenkov
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
"""Launch the nav2 costmap and global planner stack for the ASPECT rover (T-010)."""

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    """Generate launch description for the nav2 costmap and global planner stack."""
    nav_pkg = get_package_share_directory('aspect_navigation')
    nav2_params = os.path.join(nav_pkg, 'config', 'nav2_params.yaml')

    # ── Nav2 global planner (NavFn / Dijkstra) ────────────────────────────
    planner_server = Node(
        package='nav2_planner',
        executable='planner_server',
        name='planner_server',
        output='screen',
        parameters=[nav2_params],
    )

    # ── Nav2 BT navigator (NavigateToPose / NavigateThroughPoses actions) ─
    bt_navigator = Node(
        package='nav2_bt_navigator',
        executable='bt_navigator',
        name='bt_navigator',
        output='screen',
        parameters=[nav2_params],
    )

    # ── Lifecycle manager ─────────────────────────────────────────────────
    # Autostart brings planner_server and bt_navigator through
    # configure → activate in sequence.
    lifecycle_manager = Node(
        package='nav2_lifecycle_manager',
        executable='lifecycle_manager',
        name='lifecycle_manager_navigation',
        output='screen',
        parameters=[nav2_params],
    )

    return LaunchDescription(
        [
            planner_server,
            bt_navigator,
            lifecycle_manager,
        ]
    )
