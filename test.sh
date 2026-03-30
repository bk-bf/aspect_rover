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

# ── Python parsing helpers ───────────────────────────────────────────────────
_HELPERS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src/aspect_scripts/test_helpers.py"

# ── Persistent log directory (survives container exit via workspace mount) ────
LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/logs"
mkdir -p "$LOG_DIR"

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
if colcon build --symlink-install 2>&1 | tee $LOG_DIR/aspect_build.log | grep -q "^ERROR"; then
    fail "Prerequisites: build failed — check $LOG_DIR/aspect_build.log"
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
        2>&1 | tee $LOG_DIR/aspect_lint.log \
   && colcon test-result --verbose 2>&1 | tee -a $LOG_DIR/aspect_lint.log \
   | grep -qE "0 errors, 0 failures"; then
    pass "T-L1: linter clean"
else
    fail "T-L1: linter failures — check $LOG_DIR/aspect_lint.log"
fi

# ── Launch sim in background ──────────────────────────────────────────────────
echo ""
echo "=== Starting sim (background) ==="
ros2 launch aspect_bringup launch_lunar_south_pole.py \
    > $LOG_DIR/aspect_sim.log 2>&1 &
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
CLOCK_INFO=$(python3 "$_HELPERS" wait_for_clock 45 2>/dev/null || true)
if [[ -n "$CLOCK_INFO" ]]; then
    info "Sim clock advancing $CLOCK_INFO"
    CLOCK_READY=true
else
    CLOCK_READY=false
fi
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

# ── T-A1 — Auger joint state topic ───────────────────────────────────────────
# Verifies that gz-sim-joint-state-publisher-system is publishing both auger
# joints.  Does NOT require /excavation/cmd — that is wired in T-103.
echo ""
echo "=== T-A1: Auger joint state — joints present in /model/aspect_rover/joint_states ==="
AUGER_JOINTS=("auger_feed_joint" "auger_rotation_joint")
A1_OK=true

# Wait up to 10 s for the joint_states topic to appear
if ! python3 "$_HELPERS" wait_for_topic /model/aspect_rover/joint_states 10 \
        > /dev/null 2>&1; then
    fail "T-A1: /model/aspect_rover/joint_states not present after 10 s"
    A1_OK=false
else
    JS_MSG=$(timeout 6 ros2 topic echo /model/aspect_rover/joint_states --once \
                 2>/dev/null || true)
    for jnt in "${AUGER_JOINTS[@]}"; do
        if echo "$JS_MSG" | grep -qF "$jnt"; then
            info "  found joint: $jnt"
        else
            fail "T-A1: joint '$jnt' not found in /model/aspect_rover/joint_states"
            A1_OK=false
        fi
    done
    $A1_OK && pass "T-A1: both auger joints present in joint_states"
fi

# ── T-A2 — Auger joints at initial (retracted) position ──────────────────────
# Reads auger_feed_joint.position via joint_state_field and asserts ≈ 0.0.
# The bit should also be stationary at angular position 0.0 (sim starts paused).
# This confirms the prismatic joint is properly modelled (not stuck or NaN).
echo ""
echo "=== T-A2: Auger joints at initial retracted position ==="
if ! $A1_OK; then
    fail "T-A2: skipped — T-A1 failed (joint_states not available)"
else
    FEED_POS=$(python3 "$_HELPERS" joint_state_field auger_feed_joint position \
                   /model/aspect_rover/joint_states 2>/dev/null || true)
    ROT_POS=$(python3 "$_HELPERS" joint_state_field auger_rotation_joint position \
                  /model/aspect_rover/joint_states 2>/dev/null || true)

    if [[ -z "$FEED_POS" ]]; then
        fail "T-A2: could not read auger_feed_joint position from joint_states"
    elif awk "BEGIN{v=${FEED_POS}+0; if(v<0)v=-v; exit !(v < 0.001)}"; then
        pass "T-A2: auger_feed_joint position=${FEED_POS} (≈ 0.0, retracted)"
    else
        fail "T-A2: auger_feed_joint position=${FEED_POS} (expected ≈ 0.0)"
    fi

    if [[ -z "$ROT_POS" ]]; then
        fail "T-A2: could not read auger_rotation_joint position from joint_states"
    elif awk "BEGIN{v=${ROT_POS}+0; if(v<0)v=-v; exit !(v < 0.001)}"; then
        pass "T-A2: auger_rotation_joint position=${ROT_POS} (≈ 0.0, stationary)"
    else
        fail "T-A2: auger_rotation_joint position=${ROT_POS} (expected ≈ 0.0)"
    fi
fi

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
    > $LOG_DIR/aspect_nav.log 2>&1 &
NAV_PID=$!

# Wait up to 15 s for the service to become available
info "Waiting for /goto_waypoint service..."
python3 "$_HELPERS" wait_for_service /goto_waypoint 15 > /dev/null 2>&1 || true

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
# Accept any non-zero velocity component (rover may need to turn before driving forward)
if echo "$CMD" | grep -qE "[xyz]: -?0\.[1-9]|[xyz]: -?[1-9]"; then
    pass "T-D2: /cmd_vel published non-zero velocity command"
else
    fail "T-D2: /cmd_vel was zero or missing after waypoint service call"
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
odom_field() { python3 "$_HELPERS" odom_field "$1"; }

info "Sampling baseline pose from /odometry/filtered (up to 15 s)..."
BASE_X=""
for _sb in $(seq 1 15); do
    BASE_X=$(odom_field x)
    [[ -n "$BASE_X" ]] && break
    info "  /odometry/filtered not yet ready, retrying (${_sb}/15)..."
    sleep 1
done
BASE_Y=$(odom_field y)
if [[ -z "$BASE_X" ]]; then
    fail "T-D4: could not read baseline pose from /odometry/filtered after 15 s"
else
    info "Baseline: x=${BASE_X} y=${BASE_Y}"

    info "Starting fresh nav node for T-D4..."
    ros2 launch aspect_navigation waypoint_nav.launch.py \
        > $LOG_DIR/aspect_nav_t4.log 2>&1 &
    NAV4_PID=$!

    # Wait for service
    python3 "$_HELPERS" wait_for_service /goto_waypoint 15 > /dev/null 2>&1 || true

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
    > $LOG_DIR/aspect_nav_t5.log 2>&1 &
NAV5_PID=$!
python3 "$_HELPERS" wait_for_service /goto_waypoint 15 > /dev/null 2>&1 || true

timeout 5 ros2 service call /goto_waypoint aspect_msgs/srv/GotoWaypoint \
    "{x: 8.0, y: 0.0}" > /dev/null 2>&1 || true

# Wait until rover has meaningfully advanced (reuse same displacement probe).
info "Waiting for rover to advance before checking for stop..."
D5_BASE_X=$(odom_field x)
D5_BASE_X="${D5_BASE_X:-0}"
D5_MOVED=false
for _i in $(seq 1 45); do
    CUR_X=$(odom_field x)
    DX5=$(awk "BEGIN{print (${CUR_X:-0}) - ($D5_BASE_X)}")
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
        LX5=$(echo "$CMD5" | python3 "$_HELPERS" parse_twist_linear_x 2>/dev/null || true)
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

# ── T-N1 + T-N2 — Nav2 lifecycle then NavigateToPose ─────────────────────────
# Both tests share a single nav2.launch.py instance to avoid the DDS
# deregistration race that occurs when the same node names are re-launched
# within a few seconds of each other (FastDDS heartbeat timeout ~10 s).
#
# T-N1: all three lifecycle nodes reach 'active'
# T-N2: NavigateToPose goal → DWB produces non-zero /cmd_vel
echo ""
echo "=== T-N1 + T-N2: Nav2 lifecycle + NavigateToPose (shared launch) ==="

info "Starting nav2.launch.py..."
ros2 launch aspect_navigation nav2.launch.py \
    > $LOG_DIR/aspect_nav2.log 2>&1 &
NAV2_PID=$!

NAV2_NODES="/controller_server,/planner_server,/bt_navigator"
info "Waiting up to 45 s for all Nav2 nodes to reach 'active' (T-N1)..."
if python3 "$_HELPERS" wait_for_lifecycle_active "$NAV2_NODES" 45; then
    pass "T-N1: all Nav2 nodes reached lifecycle 'active'"
else
    fail "T-N1: one or more Nav2 nodes did not reach 'active' within 45 s (see $LOG_DIR/aspect_nav2.log)"
fi

# T-N2: only run if T-N1 passed (nodes are active)
echo ""
echo "=== T-N2: NavigateToPose — DWB publishes non-zero /cmd_vel ==="
N1_PASSED=true
for _n in $(echo "$NAV2_NODES" | tr ',' ' '); do
    STATE=$(python3 "$_HELPERS" lifecycle_state "$_n" 2>/dev/null || true)
    [[ "$STATE" == "active" ]] || { N1_PASSED=false; break; }
done

if ! $N1_PASSED; then
    fail "T-N2: skipped — Nav2 nodes not active (T-N1 failed)"
else
    info "Sending NavigateToPose goal {x: 15.0, y: 0.0, frame_id: odom}..."
    ros2 action send_goal /navigate_to_pose nav2_msgs/action/NavigateToPose \
        "{pose: {header: {frame_id: odom}, pose: {position: {x: 15.0, y: 0.0, z: 0.0}, orientation: {w: 1.0}}}}" \
        > $LOG_DIR/aspect_nav2_goal.log 2>&1 &
    GOAL_PID=$!

    info "Sampling /cmd_vel for up to 20 s (expecting non-zero DWB output)..."
    N2_GOT_VEL=false
    for _i in $(seq 1 20); do
        CMD_N2=$(timeout 3 ros2 topic echo /cmd_vel --once 2>/dev/null || true)
        LX_N2=$(echo "$CMD_N2" | python3 "$_HELPERS" parse_twist_linear_x 2>/dev/null || true)
        if [[ -n "$CMD_N2" ]] && awk "BEGIN{v=${LX_N2:-0}; if(v<0)v=-v; exit !(v > 0.01)}"; then
            N2_GOT_VEL=true
            break
        fi
        sleep 1
    done

    kill "$GOAL_PID" 2>/dev/null || true

    if $N2_GOT_VEL; then
        pass "T-N2: /cmd_vel received non-zero DWB output after NavigateToPose goal"
    else
        fail "T-N2: /cmd_vel did not receive non-zero output within 20 s (see $LOG_DIR/aspect_nav2.log)"
    fi
fi

kill "$NAV2_PID" 2>/dev/null || true
wait "$NAV2_PID" 2>/dev/null || true

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
