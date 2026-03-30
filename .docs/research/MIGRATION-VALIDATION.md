# Migration Validation — TX2540m1 → aspect VPS (netcup G11)

**Purpose:** Confirm the aspect VPS (AMD EPYC-Genoa, 8 vCores) is a worthwhile CI target
compared to the TX2540m1 (Intel Xeon E5-2420 v2, 2.7 GHz turbo) by running identical
tests on both hosts and comparing real-time factor, wall-clock test duration, and
pass/fail outcomes.

**Decision context:** D-008 (GPU compute strategy), B-017 (RTF ~1/30× on TX2540m1).
Expected single-thread improvement: ~3.5–4× (Geekbench 6: ~500 → ~1900).

---

## Prerequisites (both hosts)

```bash
# Enter the container
docker compose -f .docker/docker-compose.yml run --rm -w /workspace aspect_dev bash

# Build
colcon build --symlink-install && source install/setup.bash
```

---

## M-1 — Gazebo Real-Time Factor

**Why:** RTF is the root cause of B-017 and drives all timing decisions in test.sh.
A 3–4× improvement brings RTF from ~1/30× to ~1/8–1/10×, which is the threshold where
T-D4/T-D5 (90 s wall time) become viable.

```bash
# Launch sim and unpause
ros2 launch aspect_bringup launch_lunar_south_pole.py > /tmp/sim.log 2>&1 &
sleep 15
gz service -s /world/lunar_south_pole/control \
  --reqtype gz.msgs.WorldControl --reptype gz.msgs.Boolean \
  --timeout 5000 --req 'pause: false'

# Sample RTF from /stats topic for 30 s
timeout 30 ros2 topic echo /stats --once 2>/dev/null || \
  python3 - <<'EOF'
import subprocess, time, sys
samples = []
for _ in range(6):
    out = subprocess.run(
        ["timeout", "4", "ros2", "topic", "echo",
         "/world/lunar_south_pole/stats", "--once"],
        capture_output=True, text=True
    ).stdout
    for line in out.splitlines():
        if "real_time_factor" in line:
            try:
                samples.append(float(line.split(":")[1].strip()))
            except ValueError:
                pass
    time.sleep(5)
if samples:
    print(f"RTF samples: {samples}")
    print(f"RTF mean: {sum(samples)/len(samples):.4f}")
else:
    print("RTF: could not sample /stats — check topic name with ros2 topic list")
EOF
```

| Host | RTF (mean) | Geekbench 6 single-core | Notes |
|---|---|---|---|
| TX2540m1 | ~0.033 (1/30×) | ~500 | Measured Feb 2026; B-017 |
| aspect VPS | 1.1 (>1×) | ~1900 | Measured 2026-03-30; idle VPS, flat ground plane |

**Pass criterion:** RTF ≥ 0.10 on aspect VPS.

---

## M-2 — Full test.sh Wall-Clock Duration

**Why:** Total CI time determines whether running tests on the VPS is practical.
On the TX2540m1, T-D4/T-D5 always timeout (90 s wall ≈ 3 s sim time → rover moves
~0.6 m, below the 1.5 m threshold). On the VPS they should pass.

```bash
time bash test.sh 2>&1 | tee /tmp/migration_test_run.log
```

Record:
- Total wall-clock time
- Pass/fail for each test
- Specific outcome of T-D4 and T-D5 (these are the migration-critical tests)

| Test | TX2540m1 result | aspect VPS result |
|---|---|---|
| Prerequisites (build) | PASS | PASS |
| T-L1 linter | PASS | PASS |
| T-S1 topic smoke | PASS | PASS |
| T-D1 manual drive | PASS | PASS (vx=0.307) |
| T-D2 waypoint service | PASS | PASS |
| T-D4 pose displacement | FAIL (timeout — B-017) | PASS (Δx=1.62 m in ~4 wall-sec) |
| T-D5 cmd_vel silence | FAIL (timeout — B-017) | PASS |
| **Total wall time** | _~N min_ | **59 s** |

**Pass criterion:** T-D4 and T-D5 both PASS on aspect VPS.

---

## M-3 — Clock Stabilisation Time (B-011)

**Why:** The EKF `/clock` bridge takes ~12 s post-unpause on the TX2540m1. On a faster
host this should be shorter, potentially allowing tighter startup waits in test.sh.

```bash
# After unpausing, time how long until /clock sec > 0
START=$(date +%s)
for i in $(seq 1 60); do
    CLK=$(timeout 2 ros2 topic echo /clock --once 2>/dev/null \
          | grep "^  sec:" | awk '{print $2}' || true)
    if [[ -n "$CLK" ]] && awk "BEGIN{exit !($CLK > 0)}"; then
        echo "Clock live after $(($(date +%s) - START)) s (sec=$CLK)"
        break
    fi
    sleep 1
done
```

| Host | Clock stabilisation | Notes |
|---|---|---|
| TX2540m1 | ~12 s | B-011 |
| aspect VPS | 2 s | Measured 2026-03-30 |

---

## M-4 — Docker Image Build Time

**Why:** Faster build = faster iteration cycle for dependency changes.

```bash
# On aspect, from /home/admin/aspect:
time docker build -f .docker/Dockerfile -t aspect:jazzy . 2>&1 | tail -5
```

| Host | Build time | Notes |
|---|---|---|
| TX2540m1 | ~10 min (first build) | Documented in AGENTS.md |
| aspect VPS | ~1.5 min (first build) | Measured 2026-03-30; apt 43s + layer export 29s |

---

## M-5 — Resource Headroom

**Why:** The TX2540m1 runs the full mediaserver stack (20 containers, ~18 GB RAM used,
5.8 GB swap active). The VPS runs ASPECT only — available memory directly affects
whether Gazebo page-faults into swap during physics ticks.

```bash
# During a live sim run:
free -h
cat /proc/meminfo | grep -E "MemAvailable|SwapFree|SwapTotal"
top -bn1 | grep -E "Cpu|Mem|Swap" | head -4
```

| Host | RAM available during sim | Swap used | Notes |
|---|---|---|---|
| TX2540m1 | ~12 GB (contended) | ~5.8 GB | mediaserver stack running |
| aspect VPS | ~14 GB available | 0 MB (no swap configured) | ASPECT only; 15 GiB total RAM |

---

## Migration Verdict

Fill in after running M-1 through M-5 on the aspect VPS:

| Criterion | Target | Result | Pass? |
|---|---|---|---|
| RTF ≥ 0.10 | ≥ 0.10 | **1.1** | ✓ PASS |
| T-D4 passes | PASS | **PASS** | ✓ PASS |
| T-D5 passes | PASS | **PASS** | ✓ PASS |
| Build time ≤ 10 min | ≤ 10 min | **~1.5 min** | ✓ PASS |
| No swap during sim | 0 MB | **0 MB** | ✓ PASS |

**Verdict (2026-03-30): MIGRATE. All criteria pass.**

RTF of 1.1 (vs 0.033 on TX2540m1) is a 33× improvement — the minimum bar of 0.10 was
eclipsed by an order of magnitude. T-D4 and T-D5 both pass; total test run is 59 s
(vs effectively infinite on TX2540m1). Zero swap, ~14 GB available RAM. This is now
the primary CI host.

Note: three bugs were fixed in test.sh during this migration run:
- Waypoints for T-D2/T-D4/T-D5 raised from 2.0 m to 5.0/5.0/8.0 m (rover accumulates
  position across tests; old waypoint landed inside acceptance_radius by T-D4).
- awk `--` crash on negative scientific-notation BASE_Y wrapped in parentheses.
