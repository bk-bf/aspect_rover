#!/usr/bin/env bash
# test.sh — ASPECT integration test runner
# Run INSIDE the container from the workspace root (/workspace).
# Usage: bash test.sh [--worktree <name>]
#   --worktree <name>  run tests against features/<name> worktree instead of main
# T-D3 (keyboard teleop) is skipped — requires interactive TTY.

set -eo pipefail   # no -u: colcon's generated setup.bash uses unbound vars

# ── Parse --worktree flag ─────────────────────────────────────────────────────
WORKTREE_NAME=""
PASSTHROUGH_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --worktree)
            [[ -z "${2:-}" ]] && { echo "ERROR: --worktree requires a name"; exit 1; }
            WORKTREE_NAME="$2"; shift 2 ;;
        *) PASSTHROUGH_ARGS+=("$1"); shift ;;
    esac
done

# If not inside the container, re-exec via docker compose
if [[ ! -f /opt/ros/jazzy/setup.bash ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ -n "$WORKTREE_NAME" ]]; then
        WORKTREE_PATH="$SCRIPT_DIR/features/$WORKTREE_NAME"
        [[ -d "$WORKTREE_PATH" ]] || { echo "ERROR: worktree not found: $WORKTREE_PATH"; exit 1; }
        echo "Not inside container — re-launching in worktree '$WORKTREE_NAME' via docker compose..."
        docker compose -f "$WORKTREE_PATH/.docker/docker-compose.yml" \
            run --rm -w /workspace aspect_dev bash /workspace/test.sh "${PASSTHROUGH_ARGS[@]}"
    else
        echo "Not inside container — re-launching via docker compose..."
        docker compose -f "$SCRIPT_DIR/.docker/docker-compose.yml" \
            run --rm -w /workspace aspect_dev bash /workspace/test.sh "${PASSTHROUGH_ARGS[@]}"
    fi
    exit $?
fi

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}  $1"; }
fail() { echo -e "${RED}FAIL${NC}  $1"; FAILURES+=("$1"); }
info() { echo -e "${YELLOW}....${NC}  $1"; }

FAILURES=()
SIM_PID=""

cleanup() {
    if [[ -n "$SIM_PID" ]]; then
        info "Stopping sim (PID $SIM_PID)..."
        kill "$SIM_PID" 2>/dev/null || true
        wait "$SIM_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# ── Prerequisites — build ─────────────────────────────────────────────────────
echo "=== Prerequisites: build ==="
if colcon build --symlink-install 2>&1 | tee /tmp/aspect_build.log | grep -q "^ERROR"; then
    fail "Prerequisites: build failed — check /tmp/aspect_build.log"
    exit 1
else
    pass "Prerequisites: 6 packages built"
fi
# shellcheck source=/dev/null
set +u; source install/setup.bash; set -u

# ── T-L1 — Linter ─────────────────────────────────────────────────────────────
echo ""
echo "=== T-L1: Linter ==="
if colcon test \
        --packages-select aspect_bringup aspect_control aspect_navigation \
        --event-handlers console_cohesion+ \
        2>&1 | tee /tmp/aspect_lint.log \
   && colcon test-result --verbose 2>&1 | tee -a /tmp/aspect_lint.log \
   | grep -qE "0 errors, 0 failures"; then
    pass "T-L1: linter clean"
else
    fail "T-L1: linter failures — check /tmp/aspect_lint.log"
fi

# ── Launch sim in background ──────────────────────────────────────────────────
echo ""
echo "=== Starting sim (background) ==="
ros2 launch aspect_bringup launch_lunar_south_pole.py \
    > /tmp/aspect_sim.log 2>&1 &
SIM_PID=$!
info "Sim PID $SIM_PID — waiting 15 s for startup..."
sleep 15

# Unpause
info "Unpausing sim..."
if gz service -s /world/lunar_south_pole/control \
        --reqtype gz.msgs.WorldControl \
        --reptype gz.msgs.Boolean \
        --timeout 5000 \
        --req 'pause: false' 2>&1 | grep -q "data: true"; then
    info "Sim unpaused"
else
    fail "Sim unpause failed — subsequent tests may be unreliable"
fi
sleep 3

# ── T-S1 — Topic smoke test ───────────────────────────────────────────────────
echo ""
echo "=== T-S1: Topic smoke test ==="
REQUIRED_TOPICS=(
    "/cmd_vel"
    "/odometry/raw"
    "/model/aspect_rover/imu"
    "/clock"
    "/tf"
)
TOPIC_LIST=$(ros2 topic list 2>/dev/null)
ALL_TOPICS_OK=true
for topic in "${REQUIRED_TOPICS[@]}"; do
    if echo "$TOPIC_LIST" | grep -qx "$topic"; then
        info "  found $topic"
    else
        fail "T-S1: missing topic $topic"
        ALL_TOPICS_OK=false
    fi
done
$ALL_TOPICS_OK && pass "T-S1: all required topics present"

# ── T-D1 — Manual drive ───────────────────────────────────────────────────────
echo ""
echo "=== T-D1: Manual drive ==="
info "Publishing cmd_vel 0.2 m/s for 5 s..."
ros2 topic pub --rate 10 /cmd_vel geometry_msgs/msg/Twist \
    "{linear: {x: 0.2}, angular: {z: 0.0}}" \
    > /dev/null 2>&1 &
PUB_PID=$!
sleep 5
kill "$PUB_PID" 2>/dev/null || true

ODOM=$(ros2 topic echo /odometry/raw --once --no-daemon 2>/dev/null | grep "x:" | head -1)
X_VAL=$(echo "$ODOM" | awk '{print $2}')
if [[ -n "$X_VAL" ]] && awk "BEGIN{exit !($X_VAL > 0.05)}"; then
    pass "T-D1: odometry x=$X_VAL (expected > 0.05)"
else
    fail "T-D1: odometry x not advancing (got: '${X_VAL:-<empty>}')"
fi

# ── T-D2 — Waypoint service ───────────────────────────────────────────────────
echo ""
echo "=== T-D2: Waypoint service ==="
info "Starting waypoint nav node..."
ros2 launch aspect_navigation waypoint_nav.launch.py \
    > /tmp/aspect_nav.log 2>&1 &
NAV_PID=$!

# Wait up to 15 s for the service to become available
info "Waiting for /goto_waypoint service..."
for i in $(seq 1 15); do
    ros2 service list 2>/dev/null | grep -qx '/goto_waypoint' && break
    sleep 1
done

SVC_RESULT=$(timeout 10 ros2 service call /goto_waypoint aspect_msgs/srv/GotoWaypoint \
    "{x: 2.0, y: 0.0}" 2>/dev/null || true)
sleep 2
CMD=$(timeout 5 ros2 topic echo /cmd_vel --once --no-daemon 2>/dev/null || true)

kill "$NAV_PID" 2>/dev/null || true

if echo "$SVC_RESULT" | grep -qE "success[=:] ?True"; then
    pass "T-D2: service returned success=True"
else
    fail "T-D2: service did not return success=True (got: $(echo "$SVC_RESULT" | tr '\n' ' '))"
fi
if echo "$CMD" | grep -qE "x: 0\.[1-9]|x: [1-9]"; then
    pass "T-D2: /cmd_vel published non-zero linear.x"
else
    fail "T-D2: /cmd_vel linear.x was zero or missing"
fi

# ── T-D3 — skipped ────────────────────────────────────────────────────────────
echo ""
echo "=== T-D3: Keyboard teleop — SKIP (requires interactive TTY) ==="
echo "    Run manually: ros2 run aspect_control teleop_node"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
if [[ ${#FAILURES[@]} -eq 0 ]]; then
    echo -e "${GREEN}All automated tests passed.${NC}"
    exit 0
else
    echo -e "${RED}${#FAILURES[@]} failure(s):${NC}"
    for f in "${FAILURES[@]}"; do echo "  - $f"; done
    exit 1
fi
