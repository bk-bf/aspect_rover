#!/usr/bin/env python3
"""test_helpers.py — ROS message parsing utilities for test.sh.

Invoked by test.sh as a subprocess; requires no ROS Python packages.
All ROS interaction is done via ``ros2`` CLI calls (subprocess).

CLI usage::

    python3 test_helpers.py odom_field <x|y|z>
    python3 test_helpers.py wait_for_clock [max_wait_seconds]
    python3 test_helpers.py wait_for_topic <topic> [max_wait_seconds]
    python3 test_helpers.py wait_for_service <service> [max_wait_seconds]
    echo "$MSG" | python3 test_helpers.py parse_twist_linear_x
"""

import re
import subprocess
import sys
import time


def _ros2_echo_once(topic, timeout=6, field=None):
    """Return raw text from ``ros2 topic echo --once``, or '' on failure."""
    cmd = ["ros2", "topic", "echo", topic, "--once"]
    if field:
        cmd += ["--field", field]
    try:
        return subprocess.check_output(
            cmd, timeout=timeout, stderr=subprocess.DEVNULL, text=True
        )
    except Exception:
        return ""


def odom_field(field, topic="/odometry/filtered"):
    """Extract a named position field from a single odometry message.

    Calls ``ros2 topic echo <topic> --once --field pose.pose.position``
    and parses the ``<field>:`` line.  Returns the value as a string,
    or '' on failure.
    """
    out = _ros2_echo_once(topic, timeout=6, field="pose.pose.position")
    for line in out.splitlines():
        line = line.strip()
        if line.startswith(f"{field}:"):
            return line.split(":", 1)[1].strip()
    return ""


def wait_for_clock(max_wait=45, topic="/clock"):
    """Poll ``ros2 topic echo`` until the clock ``sec`` field is > 0.

    Returns a human-readable summary string on success, e.g.
    ``"after 12s (sec=4)"``, or '' if the timeout is reached.
    """
    for i in range(1, max_wait + 1):
        out = _ros2_echo_once(topic, timeout=2)
        for line in out.splitlines():
            stripped = line.strip()
            if stripped.startswith("sec:"):
                try:
                    sec = int(stripped.split(":", 1)[1].strip())
                    if sec > 0:
                        return f"after {i}s (sec={sec})"
                except ValueError:
                    pass
        time.sleep(1)
    return ""


def wait_for_topic(topic, max_wait=15):
    """Poll ``ros2 topic list`` until *topic* appears.

    Returns True when found, False on timeout.
    """
    for _ in range(max_wait):
        try:
            out = subprocess.check_output(
                ["ros2", "topic", "list"],
                timeout=5, stderr=subprocess.DEVNULL, text=True
            )
            if topic in out.splitlines():
                return True
        except Exception:
            pass
        time.sleep(1)
    return False


def wait_for_service(service, max_wait=15):
    """Poll ``ros2 service list`` until *service* appears.

    Returns True when found, False on timeout.
    """
    for _ in range(max_wait):
        try:
            out = subprocess.check_output(
                ["ros2", "service", "list"],
                timeout=5, stderr=subprocess.DEVNULL, text=True
            )
            if service in out.splitlines():
                return True
        except Exception:
            pass
        time.sleep(1)
    return False


def parse_twist_linear_x(text):
    """Extract ``linear.x`` from a ROS Twist YAML string.

    Matches the first ``x:`` value following a ``linear:`` block.
    Returns the value as a string, or '' on failure.
    """
    m = re.search(r"linear:.*?x:\s*([-\d.eE+]+)", text, re.DOTALL)
    return m.group(1) if m else ""


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "odom_field":
        if len(sys.argv) < 3:
            print("Usage: odom_field <x|y|z>", file=sys.stderr)
            sys.exit(1)
        print(odom_field(sys.argv[2]))

    elif cmd == "wait_for_clock":
        max_wait = int(sys.argv[2]) if len(sys.argv) > 2 else 45
        result = wait_for_clock(max_wait)
        if result:
            print(result)
            sys.exit(0)
        else:
            sys.exit(1)

    elif cmd == "wait_for_topic":
        if len(sys.argv) < 3:
            print("Usage: wait_for_topic <topic> [max_wait]", file=sys.stderr)
            sys.exit(1)
        _topic = sys.argv[2]
        max_wait = int(sys.argv[3]) if len(sys.argv) > 3 else 15
        sys.exit(0 if wait_for_topic(_topic, max_wait) else 1)

    elif cmd == "wait_for_service":
        if len(sys.argv) < 3:
            print("Usage: wait_for_service <service> [max_wait]", file=sys.stderr)
            sys.exit(1)
        _service = sys.argv[2]
        max_wait = int(sys.argv[3]) if len(sys.argv) > 3 else 15
        sys.exit(0 if wait_for_service(_service, max_wait) else 1)

    elif cmd == "parse_twist_linear_x":
        text = sys.stdin.read()
        print(parse_twist_linear_x(text))

    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)
