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

> Goal: rover autonomously excavates 50 g+ regolith via auger in simulation at
> ≥ 80% success rate. TRL-3. PPO baseline validates gym env + reward function;
> VLA fine-tuning pipeline initiated by end of phase. Requires Priority 1 complete.
>
> Execution groups (by unlock order):
> - **Group A — start immediately** (T-101, T-102, T-108): nav2 stack, auger URDF, and test infra refactor have no shared deps; run in parallel
> - **Group B — unblocked once T-101 done** (T-105, T-106): terrain tuning and EKF validation; run in parallel
> - **Group C — unblocked once T-101 + T-102 done** (T-103 → T-104): gym env then baseline PPO; sequential
> - **Group D — unblocked once T-103 + T-104 done** (T-AI-01 → T-AI-02, T-AI-03): VLA fine-tuning, inference node, domain randomisation
>
> T-107 is the join point for Group B — requires T-105 + T-106 both complete.
>
> *Competition fork (D-015): if a Lunabotics-style opportunity is confirmed, fork
> only `aspect_description` + `aspect_gazebo`; nav/AI/bringup stack is shared
> unchanged. Est. ~1 weekend once T-103 is stable. No tasks created until confirmed.*

[PARALLEL A — start immediately, no shared deps]
- [x] T-101 [`aspect_navigation`]: Nav2 stack integration (costmap, global + local planner)
- [x] T-102 [`aspect_description`]: Excavation auger URDF + articulation joints
      — cylinder link (auger body) with continuous joint (rotation, ~120 RPM
        nominal) + prismatic joint (vertical feed, 0–10 mm/s range);
        box-geometry stub sufficient for Phase 1 — no mesh required to unblock T-103.
        Interface: publishes `/excavation/joint_state`, subscribes
        `/excavation/cmd` (`rpm: float`, `feed_rate: float`).
        Phase 3 thermal extension (T-302) adds resistive heating to this link —
        design auger body link to accept a `<thermal>` plugin slot. *(see D-013, D-014)*
        ⚠ *`feature/t-102-scoop-urdf` contains a superseded scoop stub — discard
        and replace with auger design before merging.*
- [x] T-108 [infra]: Refactor `test.sh` — extract ROS message parsing into `src/aspect_scripts/test_helpers.py`; bash retains process orchestration (`colcon`, `docker`, `gz service`), Python handles structured parsing (`odom_field`, `wait_for_topic`, clock sampling)

[PARALLEL B — unblocked once T-101 is done]
- [ ] T-105: Lunar terrain Nav2 parameter tuning *(needs T-101; validates D-014 wheelbase constraint — document final wheelbase spec before T-201)*
- [ ] T-106 [`aspect_bringup`]: Sensor fusion — wheel odometry + IMU via EKF validated in sim *(needs T-101; parallel with T-105)*

[PARALLEL C — unblocked once T-101 + T-102 are done]
- [ ] T-103 [`aspect_gazebo`]: gymnasium environment wrapping Gazebo sim *(implements D-007 — gymnasium + SB3 framework choice; needs T-101 + T-102)*

[sequential after T-103]
- [ ] T-104: Baseline PPO training — SB3 Zoo defaults *(CPU-only proof-of-concept; goal is to validate gym env + reward function before GPU spend — see D-007, D-008; needs T-103)*
      → On completion: export rollout dataset in LeRobot/HF Hub format
        (episodes: `camera_obs`, `[rpm, feed_rate, v_x, ω_z]` actions, reward).
        This dataset is the fine-tuning input for T-AI-01.

[sequential after T-105 + T-106]
- [ ] T-107: 30-minute stability test passing in CI *(needs T-101, T-105, T-106)*

[PARALLEL D — VLA foundation, unblocked once T-103 + T-104 done] *(implements D-016 Tier 2)*
- [ ] T-AI-01 [`aspect_navigation`]: OpenVLA-OFT fine-tuning on Gazebo rollouts *(D-016 Tier 2 policy)*
      — LoRA adapters on `openvla/openvla-7b-oft` (HuggingFace); input: camera
        frame (RGB, 224×224) + goal waypoint as text; output: action tokens
        decoded to `[v_x, ω_z, auger_rpm, feed_rate]`; train on rollout dataset
        exported by T-104; target: > 75% excavation success in held-out sim
        episodes. Hardware: same Vast.ai instance as T-206 (share budget).
        *(needs T-103, T-104 rollout dataset)*
- [ ] T-AI-02 [`aspect_navigation`]: VLA inference ROS 2 node *(D-016 Tier 2 — production policy replacing PPO)*
      — wraps OpenVLA-OFT at ~30ms/step via HuggingFace transformers + 4-bit
        quantisation; publishes `/cmd_vel` and `/excavation/cmd`; falls back to
        Nav2 reactive layer if inference latency > 50ms (watchdog timer).
        Replaces PPO as production Tier 2 policy. *(needs T-AI-01)*
- [ ] T-AI-03 [`aspect_gazebo`]: Domain randomisation dataset for VLA retraining
      — randomise: surface friction μ ∈ [0.4, 0.8], regolith density ∈
        [1.1, 1.5] g/cm³, lighting intensity ∈ [0.2, 1.0], IMU noise σ ∈
        [0.01, 0.05]; generate 500-episode dataset; retrain T-AI-01 adapters.
        Implements T-307 (domain randomisation) one phase early.
        *(needs T-105, T-106; parallel with T-107)*

### Priority 4 — Phase 2: Hardware V1 + RL Production Training (2026 Q3–2027 Q1)

> Goal: physical 1:10 prototype driving in lab; RL policy achieving 20 g+ auger
> excavation in simulation. TRL-4. Cloud GPU budget ~$80. Hierarchical AI tier
> integration validated on hardware (T-AI-05).
>
> Parallel tracks (per D-010, D-016):
> - **Track A — hardware chain** (T-201 → T-202 → T-203 → T-204 → T-205): each step
>   depends on the previous; builds up to full EKF fusion on real hardware
> - **Track B — RL production** (T-206 → T-207): cloud GPU migration, then hyperparam
>   search; sequential within the track, independent of Track A
> - **Track C — rover intelligence** (T-AI-04 → T-AI-05): LLM task planner then
>   hierarchical tier integration; needs T-201 for hardware grounding *(implements D-016)*
>
> T-208 (field trial) needs Tracks A, B, and C complete — it is the join point for this phase.

[PARALLEL A — hardware chain, sequential internally; start with T-201]
- [ ] T-201: RPi 4B bring-up with ROS 2 Jazzy
- [ ] T-202: GY-521 IMU driver node *(needs T-201)*
- [ ] T-203: Faulhaber 1524 / SG90 motor driver node *(needs T-201)*
- [ ] T-204: ESP32-CAM ROS 2 video stream *(needs T-201)*
- [ ] T-205: EKF fusion — wheel odometry + IMU on hardware *(needs T-202, T-203)*

[PARALLEL B — RL production, independent of Track A]
- [ ] T-206: Cloud GPU migration (Vast.ai / RunPod); checkpoint auto-save to HF Hub *(executes D-008 gates 2–3; implements D-009 model storage)*
      → Also migrate T-AI-01 VLA fine-tuning runs to cloud GPU instance;
        share budget envelope with PPO ablations. Checkpoint both PPO and
        VLA adapter weights to HF Hub under the same auto-save pipeline.
- [ ] T-207: Hyperparameter search (SB3 Zoo ablations, 10 runs) *(blocked by D-008 budget gate — do not start until T-206 complete and $80 budget confirmed; needs T-206)*

[PARALLEL C — rover intelligence architecture, independent of Tracks A and B]
- [ ] T-AI-04 [`aspect_bringup`]: LLM task planner node (Tier 3 coordinator)
      — Ollama-served Qwen2.5-7B (or Gemma-3-4B if RPi memory-constrained)
        running offboard initially; subscribes `/mission_state` (JSON: battery %,
        auger depth, regolith yield, position); publishes `/task_command`
        (enum: NAVIGATE | DRILL | RETRACT | RECHARGE | IDLE); prompt template
        includes rover telemetry + mission constraints.
        Text→action overhead isolated to this tier; Tier 2 VLA handles execution. *(see D-016)*
        *(needs T-201 RPi bring-up; parallel with T-202, T-203)*
- [ ] T-AI-05 [`aspect_bringup`]: Hierarchical control integration
      — wire Tier 3 LLM planner (T-AI-04) → Tier 2 VLA policy (T-AI-02) →
        Tier 1 Nav2/EKF stack; define ROS 2 action server interfaces between
        tiers; latency budget enforced by watchdog: planner < 2s, VLA < 50ms,
        Nav2 < 10ms; integration test: full navigate→drill→retract cycle
        completing autonomously without teleop. *(needs T-AI-04, T-AI-02, T-205)*

[sequential join — needs T-205 + T-207 + T-AI-05]
- [ ] T-208: Backyard excavation trial with regolith analog (≥ 5 g/min auger yield) *(needs T-205 + T-207 + T-AI-05)*

### Priority 5 — Phase 3: Integrated ISRU Prototype (2027 Q2–2028 Q1)

> Goal: end-to-end water extraction demonstrated on bench. TRL-4 → TRL-5.
> 1:5 scale chassis. Cloud GPU budget ~$155. Requires T-208 field data.
>
> Parallelism at this horizon is not yet planned in detail — dependencies will be
> mapped when Phase 2 is within one quarter of completion.

[PARALLEL A — hardware subsystems, no stated inter-dependencies]
- [ ] T-301: 1:5 scale chassis with Faulhaber motors throughout
- [ ] T-302 [`aspect_description`]: Heated auger thermal extraction subsystem
      — extends T-102 auger URDF: add resistive heating element to auger flight
        geometry; target drill-zone temperature 120–150°C for water ice
        sublimation in place; vapour vented up drill string to T-303 cold trap.
        Reference: NASA LADI architecture (AIAA 2023-4758).
        *(needs T-102 auger URDF thermal plugin slot)*
- [ ] T-303: Cold trap water capture system
- [ ] T-304: Small-scale electrolysis module (target: 1-5 g/hr H₂)

[PARALLEL B — AI/perception, independent of hardware subsystems]
- [ ] T-305: Computer vision for ice-rich regolith detection
- [ ] T-306: Multi-scenario RL training (varied terrain, sensor noise, lighting)
- [ ] T-307: Domain randomisation for sim-to-real transfer *(partially implemented early by T-AI-03)*
- [ ] T-AI-06 [`aspect_bringup`]: Rover mesh network prototype
      — ROS 2 DDS peer discovery over WiFi/LoRa between ≥ 2 rovers; shared
        `OccupancyGrid` relay via `/map` topic; decentralised excavation zone
        allocation using stigmergy pattern — each rover writes auger yield
        estimates to shared map, reads neighbour estimates, avoids recently
        drilled zones without central coordinator.
        Architecture reference: JPL CADRE UWB inter-ranging mesh.
        *(needs T-301 chassis; parallel with T-302, T-303)*
- [ ] T-AI-07 [`aspect_navigation`]: Multi-agent cooperative excavation policy
      — extend T-AI-01 gym env to 2-rover scenario with shared `OccupancyGrid`
        observation; train shared policy (parameter sharing) with independent
        per-rover observations; success metric: combined yield ≥ 1.8× single-rover
        baseline (super-linear from zone coordination).
        *(needs T-AI-01 single-rover policy, T-AI-06 mesh)*

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

