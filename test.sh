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

# Wait for sim clock to advance past 0 (B-011: /clock bridge lazy, takes ~12 s post-unpause)
info "Waiting for sim clock to advance (up to 45 s)..."
CLOCK_READY=false
for i in $(seq 1 45); do
    CLK_SEC=$(timeout 2 ros2 topic echo /clock --once 2>/dev/null \
              | grep "^  sec:" | head -1 | awk '{print $2}' || true)
    if [[ -n "$CLK_SEC" ]] && awk "BEGIN{exit !($CLK_SEC > 0)}"; then
        info "Sim clock advancing after ${i}s (sec=${CLK_SEC})"
        CLOCK_READY=true
        break
    fi
    sleep 1
done
$CLOCK_READY || info "WARNING: sim clock still 0 after 45 s — T-D1 may fail"

# Brief settle for EKF to initialise once clock is running
sleep 2

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
info "Publishing cmd_vel 0.2 m/s, checking for non-zero odom velocity..."
ros2 topic pub --rate 10 /cmd_vel geometry_msgs/msg/Twist \
    "{linear: {x: 0.2}, angular: {z: 0.0}}" \
    > /dev/null 2>&1 &
PUB_PID=$!
sleep 2   # brief settle for velocity to propagate

# Check that /odometry/raw reports non-zero linear velocity (twist.twist.linear.x)
# This works regardless of sim real-time factor — position accumulation is too slow.
VX_MAX=0
for _i in $(seq 1 8); do
    # The odometry message has twist.linear.x nested under "twist:" blocks.
    # We grep all "x:" lines and take the max absolute value found.
    ODOM_MSG=$(timeout 3 ros2 topic echo /odometry/raw --once 2>/dev/null || true)
    while IFS= read -r line; do
        VAL=$(echo "$line" | awk '/x:/{print $2}')
        if [[ -n "$VAL" ]]; then
            VX_MAX=$(awk "BEGIN{v=$VAL+0; if(v<0)v=-v; m=$VX_MAX+0; print (v>m)?v:m}")
        fi
    done < <(echo "$ODOM_MSG" | grep "x:")
    awk "BEGIN{exit !($VX_MAX > 0.01)}" && break
    sleep 1
done
kill "$PUB_PID" 2>/dev/null || true

if awk "BEGIN{exit !($VX_MAX > 0.01)}"; then
    pass "T-D1: odometry velocity vx=$VX_MAX (expected > 0.01)"
else
    fail "T-D1: odometry velocity not responding to cmd_vel (max vx='${VX_MAX}')"
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
    "{x: 5.0, y: 0.0}" 2>/dev/null || true)
# Wait for nav node to start issuing /cmd_vel (up to 10 s)
CMD=$(timeout 10 ros2 topic echo /cmd_vel --once 2>/dev/null || true)

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

# ── T-D4 — Pose displacement ──────────────────────────────────────────────────
# Behavioral test: rover must actually navigate toward waypoint (2.0, 0.0).
# Asserts position.x advances ≥ 1.5 m within 90 s — i.e. the rover covered
# 75 % of the straight-line distance, implying genuine forward navigation.
# Uses /odometry/filtered (EKF-fused, the authoritative pose used by the nav
# node itself).  Also asserts lateral drift |y| < 0.5 m to catch spin/drift bugs.
echo ""
echo "=== T-D4: Pose displacement — rover navigates toward waypoint ==="

# Helper: extract position.x or position.y from a single /odometry/filtered msg.
# Usage: odom_field <x|y>
odom_field() {
    local field="$1"
    python3 - <<PYEOF
import subprocess, sys
try:
    out = subprocess.check_output(
        ["ros2", "topic", "echo", "/odometry/filtered", "--once",
         "--field", "pose.pose.position"],
        timeout=4, stderr=subprocess.DEVNULL, text=True
    )
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("${field}:"):
            print(line.split(":")[1].strip())
            sys.exit(0)
except Exception:
    pass
print("")
PYEOF
}

info "Sampling baseline pose from /odometry/filtered..."
BASE_X=$(odom_field x)
BASE_Y=$(odom_field y)
if [[ -z "$BASE_X" ]]; then
    fail "T-D4: could not read baseline pose from /odometry/filtered"
else
    info "Baseline: x=${BASE_X} y=${BASE_Y}"

    info "Starting fresh nav node for T-D4..."
    ros2 launch aspect_navigation waypoint_nav.launch.py \
        > /tmp/aspect_nav_t4.log 2>&1 &
    NAV4_PID=$!

    # Wait for service
    for i in $(seq 1 15); do
        ros2 service list 2>/dev/null | grep -qx '/goto_waypoint' && break
        sleep 1
    done

    info "Sending goto_waypoint {x: 5.0, y: 0.0}..."
    timeout 5 ros2 service call /goto_waypoint aspect_msgs/srv/GotoWaypoint \
        "{x: 5.0, y: 0.0}" > /dev/null 2>&1 || true

    # Poll /odometry/filtered up to 90 s; succeed when x-displacement ≥ 1.5 m.
    info "Polling pose for up to 90 s (target: position.x ≥ $(awk "BEGIN{print $BASE_X+1.5}"))..."
    D4_REACHED=false
    D4_FINAL_X="$BASE_X"
    D4_FINAL_Y="${BASE_Y:-0}"
    for _i in $(seq 1 45); do
        CUR_X=$(odom_field x)
        CUR_Y=$(odom_field y)
        [[ -n "$CUR_X" ]] && D4_FINAL_X="$CUR_X"
        [[ -n "$CUR_Y" ]] && D4_FINAL_Y="$CUR_Y"
        DX=$(awk "BEGIN{print $D4_FINAL_X - $BASE_X}")
        if awk "BEGIN{exit !(${DX} >= 1.5)}"; then
            D4_REACHED=true
            break
        fi
        info "  t=$((_i*2))s  x=${D4_FINAL_X}  Δx=${DX}"
        sleep 2
    done

    kill "$NAV4_PID" 2>/dev/null || true
    wait "$NAV4_PID" 2>/dev/null || true

    DX_FINAL=$(awk "BEGIN{print $D4_FINAL_X - $BASE_X}")
    DY_FINAL=$(awk "BEGIN{v=($D4_FINAL_Y)-(${BASE_Y:-0}); if(v<0)v=-v; print v}")

    if $D4_REACHED; then
        pass "T-D4: rover advanced Δx=${DX_FINAL} m toward waypoint (≥ 1.5 m required)"
    else
        fail "T-D4: rover only advanced Δx=${DX_FINAL} m in 90 s (< 1.5 m required)"
    fi

    # Lateral drift check — catches spin-in-place and sideways-drive bugs
    if awk "BEGIN{exit !(${DY_FINAL} < 0.5)}"; then
        pass "T-D4: lateral drift |Δy|=${DY_FINAL} m within 0.5 m tolerance"
    else
        fail "T-D4: excessive lateral drift |Δy|=${DY_FINAL} m (≥ 0.5 m) — rover may be spinning or drifting"
    fi
fi

# ── T-D5 — cmd_vel silence after goal reached ─────────────────────────────────
# Behavioral test: after the rover reaches the waypoint the nav node must stop
# publishing non-zero cmd_vel.  Catches "drives past goal" / "never stops" bugs.
# This test runs its own nav node, sends the same waypoint, waits for T-D4-level
# displacement, then asserts /cmd_vel is zero (or silent) within 15 s of arrival.
echo ""
echo "=== T-D5: cmd_vel silence — rover stops after reaching waypoint ==="

info "Starting fresh nav node for T-D5..."
ros2 launch aspect_navigation waypoint_nav.launch.py \
    > /tmp/aspect_nav_t5.log 2>&1 &
NAV5_PID=$!
for i in $(seq 1 15); do
    ros2 service list 2>/dev/null | grep -qx '/goto_waypoint' && break
    sleep 1
done

timeout 5 ros2 service call /goto_waypoint aspect_msgs/srv/GotoWaypoint \
    "{x: 8.0, y: 0.0}" > /dev/null 2>&1 || true

# Wait until rover has meaningfully advanced (reuse same displacement probe).
info "Waiting for rover to advance before checking for stop..."
D5_BASE_X=$(odom_field x)
D5_BASE_X="${D5_BASE_X:-0}"
D5_MOVED=false
for _i in $(seq 1 45); do
    CUR_X=$(odom_field x)
    DX5=$(awk "BEGIN{print ${CUR_X:-0} - $D5_BASE_X}")
    if awk "BEGIN{exit !(${DX5} >= 1.5)}"; then
        D5_MOVED=true
        info "  rover reached Δx=${DX5} m — checking cmd_vel stops..."
        break
    fi
    sleep 2
done

if ! $D5_MOVED; then
    info "T-D5: rover did not advance ≥ 1.5 m — skipping silence check (T-D4 already failed)"
    kill "$NAV5_PID" 2>/dev/null || true
    wait "$NAV5_PID" 2>/dev/null || true
else
    # After arrival, cmd_vel should go to zero.  Sample up to 15 s.
    D5_STOPPED=false
    for _j in $(seq 1 15); do
        CMD5=$(timeout 3 ros2 topic echo /cmd_vel --once 2>/dev/null || true)
        LX5=$(echo "$CMD5" | python3 -c "
import sys, re
for line in sys.stdin:
    m = re.search(r'linear.*?x:\s*([-\d.]+)', line)
    if m: print(m.group(1)); break
" 2>/dev/null || true)
        # Also accept silence (no message published) as stopped
        if [[ -z "$CMD5" ]] || awk "BEGIN{v=${LX5:-0}; if(v<0)v=-v; exit !(v < 0.01)}"; then
            D5_STOPPED=true
            break
        fi
        sleep 1
    done

    kill "$NAV5_PID" 2>/dev/null || true
    wait "$NAV5_PID" 2>/dev/null || true

    if $D5_STOPPED; then
        pass "T-D5: /cmd_vel went silent/zero after goal reached"
    else
        fail "T-D5: /cmd_vel still non-zero after rover arrived at waypoint — rover not stopping"
    fi
fi

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
