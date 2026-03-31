#!/usr/bin/env bash
# view_urdf.sh — ASPECT URDF visualiser service manager
#
# Manages per-worktree Foxglove bridge services via systemd.
# Each worktree runs in its own Docker container on a dedicated port.
#
# Commands (start/stop/restart default to --all):
#   bash view_urdf.sh install   [--worktree <name>] [--port <N>]
#   bash view_urdf.sh uninstall [--worktree <name>]
#   bash view_urdf.sh start     [--worktree <name>|--all]
#   bash view_urdf.sh stop      [--worktree <name>|--all]
#   bash view_urdf.sh restart   [--worktree <name>|--all]
#   bash view_urdf.sh status
#   bash view_urdf.sh logs      [--worktree <name>]
#
# Connect from Foxglove Desktop: Open Connection → Foxglove WebSocket → ws://<host>:<port>

set -eo pipefail

DEFAULT_PORT=8765
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── inside-container entrypoint ────────────────────────────────────────────────
if [[ "${1:-}" == "--inside-container" ]]; then
    PORT="${2:-$DEFAULT_PORT}"

    if ! ros2 pkg list 2>/dev/null | grep -q foxglove_bridge; then
        echo "==> Installing foxglove_bridge (one-time — rebuild image to skip)..."
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

# ── host helpers ───────────────────────────────────────────────────────────────
DOCKER="docker"
docker info &>/dev/null 2>&1 || DOCKER="sudo docker"

_svc_name() { echo "aspect-foxglove-${1}"; }

_all_svcs() {
    systemctl list-units --type=service --all --no-legend 2>/dev/null \
        | awk '{print $1}' | grep '^aspect-foxglove-' | sed 's/\.service$//' || true
}

_svc_port() {
    local out
    out="$(systemctl cat "${1}.service" 2>/dev/null \
        | grep -o -- '-p 0\.0\.0\.0:[0-9]*' | head -1 \
        | grep -o '[0-9]*$')" || true
    echo "${out:-?}"
}

_next_port() {
    local used p
    used="$({ _all_svcs | while IFS= read -r svc; do _svc_port "$svc"; done; } \
        | grep -E '^[0-9]+$' | sort -n | tr '\n' ' ')"
    p=$DEFAULT_PORT
    while [[ " $used " == *" $p "* ]]; do p=$((p + 1)); done
    echo "$p"
}

_tailscale_host() {
    local host=""
    if command -v tailscale &>/dev/null; then
        host="$(tailscale status --peers=false --json 2>/dev/null \
            | grep -o '"DNSName": *"[^"]*"' | head -1 \
            | grep -o '"[^"]*"$' | tr -d '"' | sed 's/\.$//' || true)"
    fi
    echo "${host:-$(hostname -s)}"
}

_status() {
    local host; host="$(_tailscale_host)"
    local svcs; svcs="$(_all_svcs)"
    echo ""
    if [[ -z "$svcs" ]]; then
        echo "  No aspect-foxglove services installed."
        echo "  Run: bash view_urdf.sh install"
        echo "       bash view_urdf.sh install --worktree <name>"
        echo ""
        return
    fi
    while IFS= read -r svc; do
        local wt="${svc#aspect-foxglove-}"
        local state; state="$(systemctl is-active "$svc" 2>/dev/null || echo stopped)"
        local port; port="$(_svc_port "$svc")"
        printf "  %-38s  %-8s  ws://%s:%s\n" "$wt" "$state" "$host" "$port"
    done <<< "$svcs"
    echo ""
}

_install() {
    local worktree="$1" port="$2"
    local svc; svc="$(_svc_name "$worktree")"
    local workspace
    if [[ "$worktree" == "main" ]]; then
        workspace="$SCRIPT_DIR"
    else
        workspace="$SCRIPT_DIR/features/$worktree"
        [[ -d "$workspace" ]] || { echo "ERROR: worktree not found: $workspace"; exit 1; }
    fi

    echo "Building aspect:jazzy image if needed..."
    if ! $DOCKER image inspect aspect:jazzy &>/dev/null 2>&1; then
        $DOCKER build -f "$SCRIPT_DIR/.docker/Dockerfile" -t aspect:jazzy "$SCRIPT_DIR"
    fi

    local docker_bin; docker_bin="$(command -v docker)"
    echo "Writing unit: $svc on port $port ..."
    cat > "/etc/systemd/system/${svc}.service" << EOF
[Unit]
Description=ASPECT Foxglove Bridge — ${worktree} (port ${port})
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStartPre=-${docker_bin} stop ${svc}
ExecStartPre=-${docker_bin} rm   ${svc}
ExecStartPre=-/bin/sh -c '${docker_bin} ps -q --filter publish=${port} | xargs -r ${docker_bin} stop'
ExecStart=${docker_bin} run --name ${svc} \
    -p 0.0.0.0:${port}:${port} \
    -v ${workspace}:/workspace \
    -w /workspace \
    aspect:jazzy \
    bash /workspace/view_urdf.sh --inside-container ${port}
ExecStop=${docker_bin} stop ${svc}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$svc"
    echo "Installed: $svc"
}

_uninstall() {
    local svc; svc="$(_svc_name "$1")"
    systemctl disable --now "$svc" 2>/dev/null || true
    rm -f "/etc/systemd/system/${svc}.service"
    systemctl daemon-reload
    echo "Removed: $svc"
}

# ── argument parsing ───────────────────────────────────────────────────────────
CMD="${1:-status}"; shift || true
WORKTREE=""
PORT=""
TARGET_ALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --worktree) WORKTREE="$2"; shift 2 ;;
        --port)     PORT="$2";     shift 2 ;;
        --all)      TARGET_ALL=true; shift ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# ── dispatch ───────────────────────────────────────────────────────────────────
case "$CMD" in
    install)
        [[ "$(id -u)" -eq 0 ]] || {
            args=(install)
            [[ -n "$WORKTREE" ]] && args+=(--worktree "$WORKTREE")
            [[ -n "$PORT" ]]     && args+=(--port "$PORT")
            exec sudo bash "$0" "${args[@]}"
        }
        wt="${WORKTREE:-main}"
        if [[ -z "$PORT" ]]; then
            existing="$(_svc_port "$(_svc_name "$wt")")"
            if [[ "$existing" =~ ^[0-9]+$ ]]; then
                PORT="$existing"   # reinstall keeps same port
            else
                PORT="$(_next_port)"
            fi
        fi
        _install "$wt" "$PORT"
        _status
        ;;
    uninstall)
        [[ "$(id -u)" -eq 0 ]] || {
            args=(uninstall)
            [[ -n "$WORKTREE" ]] && args+=(--worktree "$WORKTREE")
            exec sudo bash "$0" "${args[@]}"
        }
        _uninstall "${WORKTREE:-main}"
        ;;
    start|stop|restart)
        if [[ -n "$WORKTREE" ]] && ! $TARGET_ALL; then
            sudo systemctl "$CMD" "$(_svc_name "$WORKTREE")"
        else
            svcs="$(_all_svcs)"
            # shellcheck disable=SC2086
            [[ -n "$svcs" ]] && sudo systemctl "$CMD" $svcs
        fi
        [[ "$CMD" != "stop" ]] && _status || true
        ;;
    status)
        _status
        ;;
    logs)
        sudo journalctl -u "$(_svc_name "${WORKTREE:-main}")" -f
        ;;
    *)
        echo "Unknown command: $CMD"
        echo "Usage: bash view_urdf.sh {install|uninstall|start|stop|restart|status|logs}"
        echo "       [--worktree <name>] [--port <N>] [--all]"
        exit 1
        ;;
esac
