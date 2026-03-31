#!/usr/bin/env bash
# view_urdf.sh — ASPECT URDF visualiser service manager
#
# Manages one persistent Docker service via systemd:
#   aspect-foxglove-bridge  — foxglove_bridge on port 8765 (ROS ↔ WebSocket)
#
# Connect from Foxglove Desktop (laptop): Open Connection → Foxglove WebSocket
#   → ws://<host>.ts.net:8765
#
# Commands:
#   bash view_urdf.sh install    install + enable service (run once from workspace root)
#   bash view_urdf.sh uninstall  disable + remove service and unit file
#   bash view_urdf.sh start      start the bridge
#   bash view_urdf.sh stop       stop the bridge
#   bash view_urdf.sh restart    restart the bridge (e.g. after workspace change)
#   bash view_urdf.sh status     show service status + connection URL
#   bash view_urdf.sh logs       follow bridge logs

set -eo pipefail

BRIDGE_PORT=8765
BRIDGE_SVC="aspect-foxglove-bridge"

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

    echo "Writing systemd unit file..."
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

    systemctl daemon-reload
    systemctl enable --now "$BRIDGE_SVC"
    echo ""
    echo "Service installed and started."
    _status
}

_uninstall() {
    systemctl disable --now "$BRIDGE_SVC" 2>/dev/null || true
    rm -f "/etc/systemd/system/${BRIDGE_SVC}.service"
    systemctl daemon-reload
    echo "Service removed."
}

_status() {
    # Prefer the real Tailscale MagicDNS FQDN (e.g. aspect.tail6d9fdf.ts.net)
    HOST=""
    if command -v tailscale &>/dev/null; then
        HOST="$(tailscale status --peers=false --json 2>/dev/null \
            | grep -o '"DNSName": *"[^"]*"' | head -1 \
            | grep -o '"[^"]*"$' | tr -d '"' | sed 's/\.$//' || true)"
    fi
    [[ -z "$HOST" ]] && HOST="$(hostname -s)"
    echo ""
    echo "  Bridge URL : ws://${HOST}:${BRIDGE_PORT}"
    echo "  Connect    : Foxglove Desktop → Open Connection → Foxglove WebSocket → ws://${HOST}:${BRIDGE_PORT}"
    echo ""
    systemctl is-active --quiet "$BRIDGE_SVC" \
        && echo "  bridge : running" || echo "  bridge : stopped"
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
        sudo systemctl start   "$BRIDGE_SVC" && _status ;;
    stop)
        sudo systemctl stop    "$BRIDGE_SVC" ;;
    restart)
        sudo systemctl restart "$BRIDGE_SVC" && _status ;;
    status)
        _status ;;
    logs)
        sudo journalctl -u "$BRIDGE_SVC" -f ;;
    *)
        echo "Unknown command: $CMD"
        echo "usage: bash view_urdf.sh {install|uninstall|start|stop|restart|status|logs}"
        exit 1
        ;;
esac
