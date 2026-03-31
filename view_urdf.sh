#!/usr/bin/env bash
# view_urdf.sh — URDF visual validation launcher
# Usage: bash view_urdf.sh [--worktree <name>]
# Run from the repo root on the host. Mirrors the test.sh self-re-exec pattern.
# OS support: Linux (X11 / XWayland), macOS (XQuartz), Windows WSL2.

set -eo pipefail

# ── args ──────────────────────────────────────────────────────────────────────
WORKTREE_NAME=""
INSIDE_CONTAINER=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --worktree)
            [[ -z "${2:-}" ]] && { echo "ERROR: --worktree requires a name"; exit 1; }
            WORKTREE_NAME="$2"; shift 2 ;;
        --inside-container) INSIDE_CONTAINER=true; shift ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# ── inside container: build if needed, then launch ───────────────────────────
if $INSIDE_CONTAINER; then
    if [[ ! -f install/setup.bash ]]; then
        echo "==> No install/ found — building workspace (first run, ~2 min)..."
        colcon build --symlink-install 2>&1 | grep -E "^\[|^(Summary|ERROR)" || true
    fi
    # shellcheck source=/dev/null
    set +u; source install/setup.bash; set -u
    exec ros2 launch aspect_description view_urdf.launch.py
fi

# ── host side ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "$WORKTREE_NAME" ]]; then
    WORKSPACE="$SCRIPT_DIR/features/$WORKTREE_NAME"
    [[ -d "$WORKSPACE" ]] || { echo "ERROR: worktree not found: $WORKSPACE"; exit 1; }
else
    WORKSPACE="$SCRIPT_DIR"
fi

# ── docker command (no sudo if user is in docker group) ──────────────────────
DOCKER="docker"
if ! docker info &>/dev/null 2>&1; then
    DOCKER="sudo docker"
fi

# ── OS-specific display + GPU args ────────────────────────────────────────────
DISPLAY_ARGS=()
GPU_ARGS=()
OS_TYPE="$(uname -s)"

case "$OS_TYPE" in
    Linux)
        if grep -qi microsoft /proc/version 2>/dev/null; then
            # WSL2 — WSLg provides X11 socket and DISPLAY automatically
            DISPLAY_ARGS+=(-e DISPLAY="${DISPLAY:-:0}")
            [[ -d /tmp/.X11-unix ]] && DISPLAY_ARGS+=(-v /tmp/.X11-unix:/tmp/.X11-unix)
        else
            # Native Linux: X11 or XWayland
            [[ -z "${DISPLAY:-}" ]] && {
                echo "ERROR: \$DISPLAY not set — connect a display or use SSH -X."
                exit 1
            }
            DISPLAY_ARGS+=(-e DISPLAY="$DISPLAY" -v /tmp/.X11-unix:/tmp/.X11-unix)
        fi
        [[ -d /dev/dri ]] && GPU_ARGS+=(--device /dev/dri)
        ;;
    Darwin)
        # macOS — requires XQuartz (https://xquartz.org)
        command -v xhost &>/dev/null || {
            echo "ERROR: XQuartz not installed. Install from https://xquartz.org"
            exit 1
        }
        xhost +localhost &>/dev/null || true
        DISPLAY_ARGS+=(-e DISPLAY=host.docker.internal:0)
        ;;
    *)
        echo "ERROR: unsupported OS: $OS_TYPE"
        exit 1
        ;;
esac

# ── docker daemon lifecycle (Linux systemd only) ──────────────────────────────
STARTED_DOCKER=false
if [[ "$OS_TYPE" == "Linux" ]] && ! $DOCKER info &>/dev/null 2>&1; then
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
echo "Launching RViz2 URDF viewer..."

$DOCKER run --rm -it \
    "${DISPLAY_ARGS[@]}" \
    "${GPU_ARGS[@]}" \
    -v "$WORKSPACE":/workspace \
    -w /workspace \
    aspect:jazzy \
    bash /workspace/view_urdf.sh --inside-container
