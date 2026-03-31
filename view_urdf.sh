#!/usr/bin/env bash
# view_urdf.sh — headless URDF visualiser via Foxglove Studio
# Run from the repo root on the VPS (or any host with Docker).
# Usage: bash view_urdf.sh [--worktree <name>] [--port <port>]
#   View in browser: https://studio.foxglove.dev → Open Connection → ws://<host>:<port>
#   On Tailscale: ws://<machine>.tailnet-name.ts.net:8765

set -eo pipefail

FOXGLOVE_PORT=8765
WORKTREE_NAME=""
INSIDE_CONTAINER=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --worktree)
            [[ -z "${2:-}" ]] && { echo "ERROR: --worktree requires a name"; exit 1; }
            WORKTREE_NAME="$2"; shift 2 ;;
        --port)
            FOXGLOVE_PORT="$2"; shift 2 ;;
        --inside-container) INSIDE_CONTAINER=true; shift ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# ── inside container: build if needed, then launch ───────────────────────────
if $INSIDE_CONTAINER; then
    # Install foxglove_bridge if not yet in the image (pre-rebuild fallback)
    if ! ros2 pkg list 2>/dev/null | grep -q foxglove_bridge; then
        echo "==> Installing foxglove_bridge (one-time, rebuild image to skip)..."
        apt-get update -qq && apt-get install -y -qq ros-jazzy-foxglove-bridge \
            && rm -rf /var/lib/apt/lists/*
    fi

    if [[ ! -f install/setup.bash ]]; then
        echo "==> No install/ found — building workspace (first run, ~2 min)..."
        colcon build --symlink-install 2>&1 | grep -E "^\[|^(Summary|ERROR)" || true
    fi
    # shellcheck source=/dev/null
    set +u; source install/setup.bash; set -u

    exec ros2 launch aspect_description foxglove_urdf.launch.py \
        port:="${FOXGLOVE_PORT}"
fi

# ── host side ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "$WORKTREE_NAME" ]]; then
    WORKSPACE="$SCRIPT_DIR/features/$WORKTREE_NAME"
    [[ -d "$WORKSPACE" ]] || { echo "ERROR: worktree not found: $WORKSPACE"; exit 1; }
else
    WORKSPACE="$SCRIPT_DIR"
fi

# ── docker command ────────────────────────────────────────────────────────────
DOCKER="docker"
if ! docker info &>/dev/null 2>&1; then
    DOCKER="sudo docker"
fi

# ── docker daemon lifecycle (Linux systemd) ───────────────────────────────────
STARTED_DOCKER=false
if [[ "$(uname -s)" == "Linux" ]] && ! $DOCKER info &>/dev/null 2>&1; then
    echo "Docker daemon not running — starting it..."
    sudo systemctl start docker
    for _i in $(seq 1 10); do $DOCKER info &>/dev/null 2>&1 && break; sleep 1; done
    STARTED_DOCKER=true
fi

cleanup() {
    if [[ "$STARTED_DOCKER" == true ]]; then
        echo "Stopping Docker daemon (we started it)..."
        sudo systemctl stop docker docker.socket
    fi
}
trap cleanup EXIT

# ── ensure image exists ───────────────────────────────────────────────────────
if ! $DOCKER image inspect aspect:jazzy &>/dev/null 2>&1; then
    echo "Image 'aspect:jazzy' not found — building (~10 min first time)..."
    $DOCKER build -f "$SCRIPT_DIR/.docker/Dockerfile" -t aspect:jazzy "$SCRIPT_DIR"
fi

echo "Workspace : $WORKSPACE"
echo "Port      : $FOXGLOVE_PORT"
echo ""
echo "  Open in browser: https://studio.foxglove.dev"
echo "  Connection:      ws://$(hostname):${FOXGLOVE_PORT}"
echo "  On Tailscale:    ws://$(hostname -s).tailnet:${FOXGLOVE_PORT}  (use MagicDNS name)"
echo ""
echo "Press Ctrl+C to stop."
echo ""

$DOCKER run --rm -it \
    -p "${FOXGLOVE_PORT}:${FOXGLOVE_PORT}" \
    -v "$WORKSPACE":/workspace \
    -w /workspace \
    aspect:jazzy \
    bash /workspace/view_urdf.sh --inside-container --port "${FOXGLOVE_PORT}"
