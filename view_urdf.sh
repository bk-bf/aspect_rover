#!/usr/bin/env bash
# view_urdf.sh — launch RViz2 URDF viewer on a local machine with a display
# Run from the repo root on your laptop (not inside the container).
# Usage: bash view_urdf.sh [--worktree <name>]
#   --worktree <name>  view URDF from features/<name> worktree instead of main

set -eo pipefail

# ── parse --worktree flag ─────────────────────────────────────────────────────
WORKTREE_NAME=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --worktree)
            [[ -z "${2:-}" ]] && { echo "ERROR: --worktree requires a name"; exit 1; }
            WORKTREE_NAME="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "$WORKTREE_NAME" ]]; then
    WORKSPACE="$SCRIPT_DIR/features/$WORKTREE_NAME"
    [[ -d "$WORKSPACE" ]] || { echo "ERROR: worktree not found: $WORKSPACE"; exit 1; }
else
    WORKSPACE="$SCRIPT_DIR"
fi

# ── guard: must have a display ────────────────────────────────────────────────
if [[ -z "${DISPLAY:-}" ]]; then
    echo "ERROR: \$DISPLAY is not set — this script requires a display (run on laptop, not VPS)."
    exit 1
fi

# ── guard: must NOT already be inside the container ──────────────────────────
if [[ -f /opt/ros/jazzy/setup.bash ]]; then
    echo "ERROR: run this script on the host, not inside the container."
    exit 1
fi

# ── docker daemon lifecycle ───────────────────────────────────────────────────
STARTED_DOCKER=false
if ! sudo docker info &>/dev/null 2>&1; then
    echo "Docker daemon not running — starting it..."
    sudo systemctl start docker
    # wait for socket to be ready (up to 10 s)
    for i in $(seq 1 10); do
        sudo docker info &>/dev/null 2>&1 && break
        sleep 1
    done
    STARTED_DOCKER=true
fi

cleanup() {
    if [[ "$STARTED_DOCKER" == true ]]; then
        echo "Stopping Docker daemon (we started it)..."
        sudo systemctl stop docker docker.socket
    fi
}
trap cleanup EXIT

echo "Workspace : $WORKSPACE"
echo "DISPLAY   : $DISPLAY"
echo "Launching RViz2 URDF viewer..."

sudo docker run --rm -it \
    -e DISPLAY="$DISPLAY" \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    --device /dev/dri \
    -v "$WORKSPACE":/workspace \
    -w /workspace \
    aspect:jazzy \
    bash -c "source install/setup.bash && ros2 launch aspect_description view_urdf.launch.py"
