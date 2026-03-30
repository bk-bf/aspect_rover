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
"""Keyboard teleoperation node for the ASPECT rover (termios raw-mode)."""

import sys
import termios
import tty

from geometry_msgs.msg import Twist
import rclpy
from rclpy.node import Node

BANNER = """
ASPECT Rover Teleoperation
--------------------------
  w / s  :  forward / backward
  a / d  :  turn left / right
  space  :  stop (zero velocity)
  q      :  quit
--------------------------
"""

KEY_BINDINGS: dict[str, tuple[float, float]] = {
    'w': (1.0, 0.0),
    's': (-1.0, 0.0),
    'a': (0.0, 1.0),
    'd': (0.0, -1.0),
    ' ': (0.0, 0.0),
}


def _get_key(fd: int) -> str:
    """Read a single raw character from the terminal."""
    return sys.stdin.read(1)


class TeleopNode(Node):
    """
    Publish velocity commands to /cmd_vel from keyboard input.

    Topics
    ------
    Publishers:
        /cmd_vel (geometry_msgs/Twist) — velocity commands for the rover
    """

    LINEAR_SPEED: float = 0.2   # m/s
    ANGULAR_SPEED: float = 0.5  # rad/s

    def __init__(self) -> None:
        """Initialise the teleop node and create publisher."""
        super().__init__('teleop_node')
        self._cmd_pub = self.create_publisher(Twist, '/cmd_vel', 10)
        self.get_logger().info('TeleopNode started — keyboard teleoperation active')

    def send_velocity(self, linear: float, angular: float) -> None:
        """
        Publish a single Twist message.

        Parameters
        ----------
        linear:
            Forward/backward velocity in m/s.
        angular:
            Rotational velocity in rad/s.

        """
        msg = Twist()
        msg.linear.x = linear * self.LINEAR_SPEED
        msg.angular.z = angular * self.ANGULAR_SPEED
        self._cmd_pub.publish(msg)

    def stop(self) -> None:
        """Publish a zero-velocity command to halt the rover."""
        self.send_velocity(0.0, 0.0)
        self.get_logger().info('Stopping rover')


def main(args: list | None = None) -> None:
    """Entry point for the teleop_node console script."""
    rclpy.init(args=args)
    node = TeleopNode()

    print(BANNER)

    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        while rclpy.ok():
            key = _get_key(fd)
            if key == 'q':
                break
            if key in KEY_BINDINGS:
                linear, angular = KEY_BINDINGS[key]
                node.send_velocity(linear, angular)
            # Spin once to process any pending callbacks (non-blocking)
            rclpy.spin_once(node, timeout_sec=0.0)
    except KeyboardInterrupt:
        pass
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
        node.stop()
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
