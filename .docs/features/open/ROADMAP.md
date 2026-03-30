# ROADMAP

Current phase: **Phase 0** (2026 Q1). Completed items move to [`../archive/README.md`](../archive/README.md).

---

## Open

### Priority 1 — Phase 0: Make the Simulation Driveable

> Goal: wire up the full ROS 2 ↔ Gazebo loop so the rover can actually be driven
> in simulation. Currently the world launches but no model is spawned, no bridge
> connects `/cmd_vel` to the sim, and no drive plugin is in the SDF.
> Blocks everything in Phase 1.

- [x] T-007 [`aspect_bringup`]: Wire up `ros_gz_bridge` for `/cmd_vel` and `/odometry/filtered`
- [x] T-008 [`aspect_gazebo`]: Add differential drive plugin to `lunar_south_pole.world` *(note: NASA DEM heightmap is visual-only — dartsim skips heightmap collision; rover drives on a flat `ground_plane` at z=0)*
- [x] T-009 [`aspect_bringup`]: Spawn rover URDF model in simulation at launch
- [x] T-006 [`aspect_bringup`]: Add `robot_localization` EKF node to bringup launch

### Priority 2 — Phase 0: Complete Package Stubs

> Goal: finish the scaffolded nodes so the packages are functional, not just
> compilable. Copyright headers unblock the linter re-enable.
>
> Parallel tracks:
> - **Track A — linter hygiene** (T-003 → T-004): sequential pair, no external deps
> - **Track B — nav2 foundation** (T-010): independent of Track A; touches different packages
>
> T-003/T-004 and T-010 can run in separate worktrees simultaneously.

- [x] T-001 [`aspect_control`]: Implement keyboard input in `teleop_node.py` (termios raw mode)
- [x] T-002 [`aspect_navigation`]: Expose `/goto_waypoint` service in `simple_waypoint_nav.py`
- [x] T-003 [all]: Add Apache 2.0 copyright headers to all source files missing them
- [x] T-004 [all]: Re-enable `ament_copyright` linter check once T-003 is done
- [x] T-010 [`aspect_navigation`]: Add nav2 costmap + basic global planner

### Priority 3 — Phase 1: Simulation & AI (2026 Q2-Q3)

> Goal: rover autonomously excavates 50 g+ regolith in simulation at ≥ 80% success
> rate. TRL-3. Requires Priority 1 complete.
>
> Execution groups (by unlock order):
> - **Group A — start immediately** (T-101, T-102): nav2 stack and scoop URDF have no shared deps; run in parallel
> - **Group B — unblocked once T-101 done** (T-105, T-106): terrain tuning and EKF validation; run in parallel
> - **Group C — unblocked once T-101 + T-102 done** (T-103 → T-104): gym env then baseline PPO; sequential
>
> T-107 is the join point for Group B — requires T-105 + T-106 both complete.

[PARALLEL A — start immediately, no shared deps]
- [ ] T-101 [`aspect_navigation`]: Nav2 stack integration (costmap, global + local planner)
- [ ] T-102 [`aspect_description`]: Excavation scoop URDF + articulation joint

[PARALLEL B — unblocked once T-101 is done]
- [ ] T-105: Lunar terrain Nav2 parameter tuning *(needs T-101)*
- [ ] T-106 [`aspect_bringup`]: Sensor fusion — wheel odometry + IMU via EKF validated in sim *(needs T-101; parallel with T-105)*

[PARALLEL C — unblocked once T-101 + T-102 are done]
- [ ] T-103 [`aspect_gazebo`]: gymnasium environment wrapping Gazebo sim *(implements D-007 — gymnasium + SB3 framework choice; needs T-101 + T-102)*

[sequential after T-103]
- [ ] T-104: Baseline PPO training — SB3 Zoo defaults *(CPU-only proof-of-concept; goal is to validate gym env + reward function before GPU spend — see D-007, D-008; needs T-103)*

[sequential after T-105 + T-106]
- [ ] T-107: 30-minute stability test passing in CI *(needs T-101, T-105, T-106)*

### Priority 4 — Phase 2: Hardware V1 + RL Production Training (2026 Q3–2027 Q1)

> Goal: physical 1:10 prototype driving in lab; RL policy achieving 20 g+ excavation
> in simulation. TRL-4. Cloud GPU budget ~$80.
>
> Parallel tracks (per D-010):
> - **Track A — hardware chain** (T-201 → T-202 → T-203 → T-204 → T-205): each step
>   depends on the previous; builds up to full EKF fusion on real hardware
> - **Track B — RL production** (T-206 → T-207): cloud GPU migration, then hyperparam
>   search; sequential within the track, independent of Track A
>
> T-208 (field trial) needs both tracks complete — it is the join point for this phase.

[PARALLEL A — hardware chain, sequential internally; start with T-201]
- [ ] T-201: RPi 4B bring-up with ROS 2 Jazzy
- [ ] T-202: GY-521 IMU driver node *(needs T-201)*
- [ ] T-203: Faulhaber 1524 / SG90 motor driver node *(needs T-201)*
- [ ] T-204: ESP32-CAM ROS 2 video stream *(needs T-201)*
- [ ] T-205: EKF fusion — wheel odometry + IMU on hardware *(needs T-202, T-203)*

[PARALLEL B — RL production, independent of Track A]
- [ ] T-206: Cloud GPU migration (Vast.ai / RunPod); checkpoint auto-save to HF Hub *(executes D-008 gates 2–3; implements D-009 model storage)*
- [ ] T-207: Hyperparameter search (SB3 Zoo ablations, 10 runs) *(blocked by D-008 budget gate — do not start until T-206 complete and $80 budget confirmed; needs T-206)*

[sequential join — needs T-205 + T-207]
- [ ] T-208: Backyard excavation trial with regolith analog (≥ 5 g/min target) *(needs T-205 + T-207)*

### Priority 5 — Phase 3: Integrated ISRU Prototype (2027 Q2–2028 Q1)

> Goal: end-to-end water extraction demonstrated on bench. TRL-4 → TRL-5.
> 1:5 scale chassis. Cloud GPU budget ~$155. Requires T-208 field data.
>
> Parallelism at this horizon is not yet planned in detail — dependencies will be
> mapped when Phase 2 is within one quarter of completion.

[PARALLEL A — hardware subsystems, no stated inter-dependencies]
- [ ] T-301: 1:5 scale chassis with Faulhaber motors throughout
- [ ] T-302: Heated auger thermal extraction subsystem
- [ ] T-303: Cold trap water capture system
- [ ] T-304: Small-scale electrolysis module (target: 1-5 g/hr H₂)

[PARALLEL B — AI/perception, independent of hardware subsystems]
- [ ] T-305: Computer vision for ice-rich regolith detection
- [ ] T-306: Multi-scenario RL training (varied terrain, sensor noise, lighting)
- [ ] T-307: Domain randomisation for sim-to-real transfer

[sequential join — needs all above]
- [ ] T-308: > 50 g H₂O extraction per run validated

### Priority 6 — Phase 4: Extreme Environment Validation (2028)

> Goal: TRL-5. 72-hour autonomous operation demonstrated in Svalbard (-40 °C) and
> Atacama Desert. Requires funded partnerships for lab access.

[PARALLEL A — foundational systems + hardware, can start once partnerships secured]
- [ ] T-401: Sensor fusion for multi-modal data integration
- [ ] T-402: Fault-tolerant autonomous operation framework
- [ ] T-405: Thermal-vacuum chamber testing at partner facility
- [ ] T-406: Full-scale (1:1) excavation subsystem (5-10 kg/hr regolith)

[PARALLEL B — field trials, independent of each other; need T-401 + T-402]
- [ ] T-403: Arctic testing — Svalbard 168-hour continuous run
- [ ] T-404: Desert trials — Atacama thermal and solar validation

### Priority 7 — Phase 5: Scale-Up & Commercial Integration (2029)

> Goal: TRL-6. Mission-relevant performance metrics. H₂ production rate sufficient
> for propellant depot feasibility study. Requires $2-5M funding (SBIR/STTR).

[PARALLEL A — technical + funding tracks, independent of each other]
- [ ] T-501: Full-scale system < 500 W total power consumption
- [ ] T-502: Partner with commercial electrolysis provider (OxEon or equiv. TRL-5+)
- [ ] T-504: SBIR/STTR Phase I proposal submission

[sequential join — needs T-501 + T-502]
- [ ] T-503: Integrated system test: 10-20 g/hr H₂ production rate

### Priority 8 — Phases 6-7: Mission Design & Lunar Demonstration (2030-2033)

> Goal: TRL-7-9. Secure CLPS contract; flight-qualify system; execute first robotic
> lunar H₂ production. Requires NASA/commercial contract. See
> [FEASIBILITY-2026.md](../../research/FEASIBILITY-2026.md) for funding pathway.

[PARALLEL A — pre-flight design + proposal, independent of each other]
- [ ] T-601: NASA CLPS proposal (lunar surface demonstration)
- [ ] T-602: Flight-qualified design, mass budget < 100 kg
- [ ] T-603: Preliminary Design Review (PDR) with industry partners

[PARALLEL B — qualification + manufacture; needs T-602 + T-603]
- [ ] T-701: Engineering qualification model (EQM) manufacture
- [ ] T-702: Flight model (FM) + vibration/thermal-vac qualification

[sequential join — needs T-601 + T-701 + T-702]
- [ ] T-703: Lunar surface ops: excavation → water extraction → electrolysis → H₂ storage
- [ ] T-704: Target: 1-5 kg total H₂ produced during 90-day surface mission

