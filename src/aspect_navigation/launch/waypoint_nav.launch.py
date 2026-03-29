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
"""Launch the ASPECT rover waypoint navigation node and nav2 costmap/planner stack."""

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    """Generate launch description for waypoint navigation with nav2 costmap and planner."""
    nav_pkg = get_package_share_directory("aspect_navigation")
    nav2_params = os.path.join(nav_pkg, "config", "nav2_params.yaml")

    # ── Simple proportional waypoint nav (existing) ───────────────────────
    waypoint_nav_node = Node(
        package="aspect_navigation",
        executable="simple_waypoint_nav",
        name="simple_waypoint_nav",
        output="screen",
        parameters=[
            {
                "acceptance_radius": 0.5,
                "linear_speed": 0.2,
                "angular_speed": 0.5,
                "use_sim_time": True,
            }
        ],
    )

    # ── Nav2 planner server (NavFn / Dijkstra global planner) ─────────────
    planner_server = Node(
        package="nav2_planner",
        executable="planner_server",
        name="planner_server",
        output="screen",
        parameters=[nav2_params],
    )

    # ── Nav2 BT navigator (action server wrapping planner + controller) ───
    bt_navigator = Node(
        package="nav2_bt_navigator",
        executable="bt_navigator",
        name="bt_navigator",
        output="screen",
        parameters=[nav2_params],
    )

    # ── Nav2 costmap lifecycle manager ────────────────────────────────────
    # Manages planner_server + bt_navigator lifecycle transitions.
    lifecycle_manager = Node(
        package="nav2_lifecycle_manager",
        executable="lifecycle_manager",
        name="lifecycle_manager_navigation",
        output="screen",
        parameters=[nav2_params],
    )

    return LaunchDescription(
        [
            waypoint_nav_node,
            planner_server,
            bt_navigator,
            lifecycle_manager,
        ]
    )
