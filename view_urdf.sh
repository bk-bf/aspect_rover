#!/usr/bin/env bash
# view_urdf.sh — ASPECT URDF visualiser service manager
#
# Manages two persistent Docker services via systemd:
#   aspect-foxglove-bridge  — foxglove_bridge  on port 8765 (ROS ↔ WebSocket)
#   aspect-foxglove-ui      — Foxglove Studio  on port 8080 (web UI)
#
# Commands:
#   bash view_urdf.sh install    install + enable services (run once from workspace root)
#   bash view_urdf.sh uninstall  disable + remove services and unit files
#   bash view_urdf.sh start      start both services
#   bash view_urdf.sh stop       stop both services
#   bash view_urdf.sh restart    restart both services (e.g. after workspace change)
#   bash view_urdf.sh status     show service status + access URLs
#   bash view_urdf.sh logs       follow bridge logs
#
# Access: http://<host>.ts.net:8080
#         Open Connection → Foxglove WebSocket → ws://<host>.ts.net:8765

set -eo pipefail

BRIDGE_PORT=8765
UI_PORT=8080
BRIDGE_SVC="aspect-foxglove-bridge"
UI_SVC="aspect-foxglove-ui"

# ── inside-container entrypoint (called by the bridge systemd service) ─────────
if [[ "${1:-}" == "--inside-container" ]]; then
    shift
    PORT="${1:-$BRIDGE_PORT}"

    if ! ros2 pkg list 2>/dev/null | grep -q foxglove_bridge; then
        echo "==> Installing foxglove_bridge (one-time, rebuild image to skip)..."
        apt-get update -qq && apt-get install -y -qq ros-jazzy-foxglove-bridge \
            && rm -rf /var/lib/apt/lists/*
    fi
    if [[ ! -f install/setup.bash ]]; then
        echo "==> Building workspace (first run)..."
        colcon build --symlink-install 2>&1 | grep -E "^\[|^(Summary|ERROR)" || true
    else
        colcon build --symlink-install --packages-select aspect_description \
            2>&1 | grep -E "^\[|^(Summary|ERROR)" || true
    fi
    # shellcheck source=/dev/null
    set +u; source install/setup.bash; set -u
    exec ros2 launch aspect_description foxglove_urdf.launch.py port:="$PORT"
fi

# ── host side ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="${1:-status}"

DOCKER="docker"
if ! docker info &>/dev/null 2>&1; then
    DOCKER="sudo docker"
fi

_install() {
    echo "Building aspect:jazzy image if needed..."
    if ! $DOCKER image inspect aspect:jazzy &>/dev/null 2>&1; then
        $DOCKER build -f "$SCRIPT_DIR/.docker/Dockerfile" -t aspect:jazzy "$SCRIPT_DIR"
    fi

    echo "Pulling Foxglove Studio UI image..."
    $DOCKER pull ghcr.io/foxglove/studio:latest

    echo "Writing systemd unit files..."
    cat > /etc/systemd/system/${BRIDGE_SVC}.service << EOF
[Unit]
Description=ASPECT Foxglove Bridge (ROS 2 WebSocket)
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStartPre=-/usr/bin/docker stop ${BRIDGE_SVC}
ExecStartPre=-/usr/bin/docker rm   ${BRIDGE_SVC}
ExecStart=/usr/bin/docker run --name ${BRIDGE_SVC} \\
    -p 0.0.0.0:${BRIDGE_PORT}:${BRIDGE_PORT} \\
    -v ${SCRIPT_DIR}:/workspace \\
    -w /workspace \\
    aspect:jazzy \\
    bash /workspace/view_urdf.sh --inside-container ${BRIDGE_PORT}
ExecStop=/usr/bin/docker stop ${BRIDGE_SVC}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/${UI_SVC}.service << EOF
[Unit]
Description=ASPECT Foxglove Studio Web UI
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStartPre=-/usr/bin/docker stop ${UI_SVC}
ExecStartPre=-/usr/bin/docker rm   ${UI_SVC}
ExecStart=/usr/bin/docker run --name ${UI_SVC} \\
    -p 0.0.0.0:${UI_PORT}:8080 \\
    ghcr.io/foxglove/studio:latest
ExecStop=/usr/bin/docker stop ${UI_SVC}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$BRIDGE_SVC" "$UI_SVC"
    echo ""
    echo "Services installed and started."
    _status
}

_uninstall() {
    systemctl disable --now "$BRIDGE_SVC" "$UI_SVC" 2>/dev/null || true
    rm -f /etc/systemd/system/${BRIDGE_SVC}.service \
          /etc/systemd/system/${UI_SVC}.service
    systemctl daemon-reload
    echo "Services removed."
}

_status() {
    HOST="$(hostname -s)"
    echo ""
    echo "  Foxglove Studio : http://${HOST}.ts.net:${UI_PORT}"
    echo "  Bridge URL      : ws://${HOST}.ts.net:${BRIDGE_PORT}"
    echo "  In the UI       : Open Connection → Foxglove WebSocket → ws://${HOST}.ts.net:${BRIDGE_PORT}"
    echo ""
    systemctl is-active --quiet "$BRIDGE_SVC" \
        && echo "  bridge : running" || echo "  bridge : stopped"
    systemctl is-active --quiet "$UI_SVC" \
        && echo "  ui     : running" || echo "  ui     : stopped"
    echo ""
}

case "$CMD" in
    install)
        [[ "$(id -u)" -eq 0 ]] || exec sudo bash "$0" install
        _install
        ;;
    uninstall)
        [[ "$(id -u)" -eq 0 ]] || exec sudo bash "$0" uninstall
        _uninstall
        ;;
    start)
        sudo systemctl start  "$BRIDGE_SVC" "$UI_SVC" && _status ;;
    stop)
        sudo systemctl stop   "$BRIDGE_SVC" "$UI_SVC" ;;
    restart)
        sudo systemctl restart "$BRIDGE_SVC" "$UI_SVC" && _status ;;
    status)
        _status ;;
    logs)
        sudo journalctl -u "$BRIDGE_SVC" -f ;;
    *)
        echo "Unknown command: $CMD"
        echo "Usage: bash view_urdf.sh {install|uninstall|start|stop|restart|status|logs}"
        exit 1
        ;;
esac
