# Enable NVIDIA GPU Support on K3s (NixOS) — Reattempt (Prod-Safe)

This ExecPlan is a living document. The sections **Progress**, **Surprises & Discoveries**, **Decision Log**, and **Outcomes & Retrospective** must be kept up to date as work proceeds.

## Purpose / Big Picture
Enable reliable NVIDIA GPU workloads on the single-node `nandstorm` K3s cluster running NixOS.

The end state is that users can schedule Kubernetes Pods requesting `nvidia.com/gpu`, and those pods can reliably access the GPU for compute and video workloads (validated via `nvidia-smi`/CUDA tests inside the pod and Jellyfin NVENC/NVDEC transcoding).

## Definition of Done (Acceptance Criteria)
- `kubectl describe node` shows `capacity/allocatable` for `nvidia.com/gpu: 3` (TITAN V ×3).
- A minimal GPU smoke test pod succeeds repeatedly:
  - `nvidia-smi` works inside the container.
  - (Optional) a CUDA sample succeeds.
- Jellyfin hardware transcoding works reliably using `jellyfin-ffmpeg` with NVENC (no intermittent failures like FFmpeg exit `218`).
- Workload interface is explicit and repeatable:
  - Pods request GPUs via `resources.limits.nvidia.com/gpu` (no `RuntimeClass` required).
- Reboot survival:
  - After a host reboot, GPU scheduling and GPU workloads still work without manual patching of CDI spec files.

## Constraints / Principles
- **Production safety (no user interruption):** this is a prod cluster; avoid unplanned downtime or service interruption for users of services running on this cluster (including Jellyfin).
  - Note: on a single-node cluster, restarting K3s/containerd can interrupt running pods. If any required change implies a restart, it must be planned and minimized (and may require an explicit decision to accept a short maintenance window or to add redundancy).
- **Declarative-first:** no manual `sed` edits or persistent host-side “patch loops” that fight a controller over generated files.
- **Stability-first:** avoid changes that cause frequent K3s/containerd restarts, tight file rewrite races, or non-deterministic GPU injection.
- **NixOS reality:** driver libraries live in `/nix/store` and are exposed via `/run/opengl-driver`; do not assume FHS paths inside containers unless deliberately provided.
- **Impermanence:** anything needed across reboots must be declarative and/or persisted under `/persist` per `hosts/nandstorm/default.nix`.

## Progress
- [x] **Milestone 0: Prod-safe approach & baseline capture**
  - Baseline captured 2025-12-20 (via `ssh root@nandstorm`):
    - GPUs: TITAN V ×3
    - `nvidia-smi`: Driver `580.105.08` (CUDA `13.0`)
    - `k3s --version`: `v1.34.2+k3s1`
    - `containerd`: `2.1.5+unknown`
    - Kubernetes: node reports `nvidia.com/gpu` capacity/allocatable `0/0` while `kube-system/nvidia-device-plugin` is Running
    - Device plugin logs: `libnvidia-ml.so.1` missing in container → detects non-NVML platform and exports 0 GPUs
    - Host-side docker+CDI test: `docker run --rm --device nvidia.com/gpu=all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi -L` succeeds (3 GPUs)
    - CDI specs present: `/etc/cdi/nvidia.yaml`, `/var/run/cdi/nvidia-container-toolkit.json`
    - No CDI-related keys found in `/var/lib/rancher/k3s/agent/etc/containerd/config.toml` (no `enable_cdi` / `cdi_spec_dirs`)
- [x] **Milestone 1: Host-level GPU + CDI generation**
  - Host CDI generator: `nvidia-container-toolkit-cdi-generator.service` enabled/active; writes `/var/run/cdi/nvidia-container-toolkit.json`
  - Docker CDI smoke test with `nvidia/cuda` succeeds (3 GPUs)
- [x] **Milestone 2: K3s/containerd CDI integration (no device plugin yet)**
  - Enable CDI in K3s embedded containerd (see `hosts/nandstorm/nvidia-k3s.nix`).
- [x] **Milestone 3: Decide the architecture (CDI vs runtimeclass vs plugin-managed CDI)**
  - Chosen: NVIDIA device plugin `--device-list-strategy=cdi-cri` + containerd CDI injection (no RuntimeClass).
- [x] **Milestone 4: Deploy device plugin for scheduling**
  - Update device plugin DaemonSet to mount NixOS driver libs so NVML is available.
- [x] **Milestone 5: End-to-end GPU pod validation**
  - `kube-system/gpu-smoke-test` runs `nvidia-smi` successfully via `nvidia.com/gpu: 1`.
- [ ] **Milestone 6: Jellyfin validation**
  - Jellyfin now requests 1 GPU and `h264_nvenc` smoke test succeeds inside the pod (Jellyfin sees `/dev/nvidia2`, which is host GPU0 on `nandstorm`).
- [ ] **Milestone 7: Reboot/impermanence verification + hardening**

## Background: Known Failure Modes from Prior Attempt
- `nvidia-device-plugin` CDI generation required filesystem discovery of driver libs; on NixOS this pushed us toward FHS-ish hacks (mounting libs and running `ldconfig` inside the plugin container).
- `nvidia-device-plugin` generated a CDI spec containing `NVIDIA_VISIBLE_DEVICES=void` in global `containerEdits`, which appeared to disable GPU visibility for workloads.
- A host “patch-cdi” systemd service to remove the `void` entry caused a race with the device plugin repeatedly overwriting the spec, destabilizing K3s.

## Working Hypotheses (Prove/Disprove Early)
1. `NVIDIA_VISIBLE_DEVICES=void` may be intentional as a safe default, and our runtime never applied the per-container/per-device override (annotation mismatch, device name mismatch, or containerd not applying requested CDI devices).
2. We can avoid plugin-managed CDI specs entirely by using **host-generated CDI** (e.g. `/etc/cdi/nvidia.yaml`) and ensuring K3s/containerd consumes it.
3. Jellyfin failures may come from mixing legacy NVIDIA runtime-hook expectations with CDI injection; the stable solution may require choosing one injection mechanism end-to-end.

## Decision Log
- Decision: Prefer a **CDI-first** design (containerd CDI injection), with the smallest possible surface area inside Kubernetes.
  - Rationale: deterministic on NixOS; fewer FHS hacks.
  - Date/Owner: 2025-12-20 / ogle
- Decision checkpoint (Milestone 0): pick an operational strategy for the “no interruption” constraint.
  - Decision: Use a brief maintenance window tonight (≤ 1 hour aggregate downtime) for any required `k3s`/containerd restarts.
  - Safety rule: if we approach the time budget without a clear path to completion, revert to the last known-good config and restore service.
  - Date/Owner: 2025-12-20 / ogle
- Decision (Milestone 3): Use NVIDIA device plugin in `cdi-cri` mode with containerd CDI injection.
  - Rationale: standard `nvidia.com/gpu` scheduling + CDI injection, without a containerd runtime handler (`RuntimeClass`) to maintain.
  - Date/Owner: 2025-12-20 / ogle

## Surprises & Discoveries
- 2025-12-20 baseline: host already has CDI specs at `/etc/cdi/nvidia.yaml` and `/var/run/cdi/nvidia-container-toolkit.json`.
- 2025-12-20 baseline: `/etc/cdi/nvidia.yaml` is CDI v0.5.0 with kind `k8s.device-plugin.nvidia.com/gpu`; `devices:` list is currently empty; spec uses `nvidia-cdi-hook`/`update-ldcache` and mounts `/run/opengl-driver` + `/run/nvidia/driver`.
- 2025-12-20 baseline: `/var/run/cdi/nvidia-container-toolkit.json` is CDI v0.5.0 with kind `nvidia.com/gpu`, devices `0/1/2/all`, and global `NVIDIA_VISIBLE_DEVICES=void`.
- 2025-12-20 baseline: Docker `29.1.2` has CDI enabled (`/etc/cdi`, `/var/run/cdi`) and discovers `nvidia.com/gpu=0/1/2/all`; `docker run --rm --device nvidia.com/gpu=all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi -L` succeeds.
- 2025-12-20 baseline: Host has `nvidia-container-toolkit-cdi-generator.service` enabled/active (generates `/var/run/cdi/nvidia-container-toolkit.json`).
- 2025-12-20 baseline: toolchain is minimal on-host (no `python`, `jq`, or `rg`); `nvidia-ctk` isn’t in PATH, but a wrapper exists at `/run/nvidia/driver/usr/bin/nvidia-ctk`.
- 2025-12-20 baseline: `/etc/cdi/nvidia.yaml` references `/run/nvidia/driver/usr/bin/nvidia-cdi-hook`, but that file is currently missing.
- 2025-12-20 baseline: K3s is `v1.34.2+k3s1` with containerd `2.1.5+unknown`; current containerd config contains no CDI-related keys.
- 2025-12-20 baseline: containerd config is on the `io.containerd.cri.v1.runtime` plugin path (containerd 2.x); only `runc` is configured as a runtime.
- 2025-12-20 baseline: `kube-system/nvidia-device-plugin` cannot load NVML (`libnvidia-ml.so.1` missing in container), so it exports `nvidia.com/gpu=0` and waits indefinitely.
- 2025-12-20 baseline: GPU0 is actively used by desktop processes (non-zero VRAM); GPU1/2 mostly idle.
- 2025-12-20 repo review: `hosts/nandstorm/virtualization.nix` enables `hardware.nvidia-container-toolkit.enable = true` and Docker CDI (`virtualisation.docker.daemon.settings.features.cdi = true`).
- 2025-12-20 repo update: repo deploys `nvcr.io/nvidia/k8s-device-plugin:v0.15.0` plus a suspended `kube-system/gpu-smoke-test` CronJob under `hosts/nandstorm/k8s/infrastructure/nvidia/` (no RuntimeClass).
- 2025-12-20 validation: `gpu-smoke-test` runs `nvidia-smi` inside a pod, but requires hostPath mounts for `/nix/store` + host `nvidia-smi` because NixOS binaries use a Nix store dynamic linker.
- 2025-12-20 validation: NVENC works on TITAN V, but `h264_nvenc` can fail with `OpenEncodeSessionEx failed: unsupported device (2)` when a container only has access to a non-primary GPU. Practical fix for Jellyfin: ensure it gets host GPU0 (device node `/dev/nvidia2`).
- (Keep a running log here as we test versions, containerd behavior, plugin output, and Jellyfin/FFmpeg logs.)

## Outcomes & Retrospective
- (Fill in at the end; include what worked, what didn’t, and what we’d do differently.)

## Context and Orientation
- **Target host:** `hosts/nandstorm` (NixOS)
- **Cluster:** single-node K3s cluster on `nandstorm`
- **GPU:** TITAN V ×3
- **Existing repo touchpoints:**
  - Kubernetes manifests: `hosts/nandstorm/k8s/infrastructure/nvidia/`
  - Likely NixOS config entry points: `hosts/nandstorm/default.nix`, `hosts/nandstorm/kube.nix`, plus any dedicated NVIDIA module we create/adjust.
- **Runtime files to validate on-host:**
  - Host CDI spec: `/etc/cdi/nvidia.yaml` (or JSON if we choose that)
  - Device-plugin CDI output (if used): `/var/run/cdi/k8s.device-plugin.nvidia.com-*.json`
  - K3s containerd config: `/var/lib/rancher/k3s/agent/etc/containerd/config.toml` (and template source in NixOS)

## Plan of Work

### Milestone 0: Prod-safe approach & baseline capture
Goal: gather versions, reproduce the current failure mode, and decide how we can proceed without interrupting users.

- Capture:
  - Host GPU: `nvidia-smi -L` and driver version.
  - K3s + containerd versions.
  - Current K3s/containerd CDI-related configuration.
- Reproduce (low-risk):
  - Run a host-side GPU container test (outside K3s) to confirm the driver + toolkit work before touching the cluster.
- Operational decision:
  - Identify whether any required step implies a K3s/containerd restart.
  - If yes, decide one of:
    - a short maintenance window, or
    - adding redundancy to avoid interruption.

### Milestone 1: Host-level GPU + CDI generation
Goal: ensure a correct, deterministic CDI spec exists on the host and can be regenerated declaratively.

- Implement/verify NixOS config:
  - NVIDIA driver enabled.
  - `nvidia-container-toolkit` installed/enabled.
  - Host CDI spec generation enabled (prefer into `/etc/cdi/`).
- Validate:
  - Inspect generated spec and confirm device names and library mounts match real host paths (`/nix/store`, `/run/opengl-driver`, etc.).
  - Confirm a GPU container can run using CDI at the host/containerd level.

### Milestone 2: K3s/containerd CDI integration (no device plugin yet)
Goal: prove K3s containerd can consume CDI and launch a pod with explicit CDI device injection.

- Configure K3s embedded containerd:
  - `enable_cdi = true`
  - `cdi_spec_dirs = [ "/etc/cdi", "/var/run/cdi" ]` (final dirs depend on where we generate specs)
- Explicit workload interface:
  - Determine the exact pod annotation format supported by our Kubernetes + containerd stack for CDI device requests.
  - Document a minimal manifest snippet (annotation + any required resource request) that makes GPUs appear inside the container.
- Validate:
  - A tiny GPU test pod runs successfully and `nvidia-smi` works inside.

### Milestone 3: Decide the architecture (decision checkpoint)
Pick one approach, based on Milestone 2 results.

**Option A (Preferred if viable): Host CDI spec + device plugin only for scheduling**
- Use host-generated CDI specs for injection.
- Device plugin is used for:
  - advertising `nvidia.com/gpu` for scheduling,
  - producing per-pod CDI annotations (or returning CDI device IDs), without generating a conflicting CDI spec.

**Option B: Device plugin manages CDI spec (but in a stable, understood way)**
- Accept plugin-generated `/var/run/cdi/...json`, but prove:
  - no breaking global edits for workloads, and
  - stable behavior (no rewrite races).

**Option C (Fallback): Legacy NVIDIA runtimeClass + hooks**
- Configure a runtime handler that uses NVIDIA hooks/runtime instead of CDI.
- Only choose if CDI is not reliable with our K3s/containerd versions.

Decision output:
- Record chosen option + rationale in **Decision Log**.

### Milestone 4: Deploy device plugin for scheduling
Goal: node advertises `nvidia.com/gpu`, pods schedule, and nothing destabilizes K3s.

- Deploy/update manifests in `hosts/nandstorm/k8s/infrastructure/nvidia/`.
- Validate:
  - Device plugin registers cleanly.
  - Node capacity shows correct GPU count.
  - No CrashLoopBackOff and no continuous CDI spec rewrite loops.

### Milestone 5: End-to-end GPU pod validation
Goal: a minimal GPU workload succeeds repeatedly.

- Apply `hosts/nandstorm/k8s/infrastructure/nvidia/gpu-smoke-test.yaml` (a suspended `CronJob`).
- Run on demand:
  - `kubectl -n kube-system create job --from=cronjob/gpu-smoke-test gpu-smoke-test-$(date +%s)`
  - `kubectl -n kube-system logs -f job/<job-name>`
- Repeatability:
  - Run multiple times and after a controlled K3s restart (if we must do one) to confirm stability.

### Milestone 6: Jellyfin validation
Goal: Jellyfin hardware transcode works reliably.

- Enable Jellyfin GPU request in `hosts/nandstorm/k8s/apps/media/jellyfin.yaml`.
- Validate inside Jellyfin container:
  - `/dev/nvidia*` present (and `/dev/nvidia-caps` if we rely on NVENC/NVDEC).
  - FFmpeg lists `*_nvenc` / `*_cuvid`.
  - A tiny `h264_nvenc` smoke transcode succeeds; if it fails with `unsupported device (2)` on a multi-GPU host, suspect a "GPU0 visibility" issue (see **Surprises & Discoveries**) rather than missing NVENC.
- If failures persist:
  - Capture Jellyfin + FFmpeg logs, and record:
    - Jellyfin manifest GPU request (`resources.limits.nvidia.com/gpu`).
    - CDI spec(s) used (typically `/var/run/cdi/k8s.device-plugin.nvidia.com-*.json`).
    - Any containerd injection errors from `journalctl -u k3s`.

### Milestone 7: Reboot/impermanence verification + hardening
Goal: no manual steps after reboot; everything comes back.

- Reboot host.
- Validate:
  - CDI spec exists (regenerated declaratively).
  - Device plugin comes up.
  - `gpu-smoke-test` passes.
  - Jellyfin transcode still works.
- If any host paths need persistence, update `environment.persistence."/persist".directories`.

## Concrete Steps (Repo Touchpoints)
- NixOS:
  - Add/adjust a dedicated module (e.g. `hosts/nandstorm/nvidia-k3s.nix`).
  - Import it from `hosts/nandstorm/default.nix`.
  - Ensure K3s containerd CDI config is templated declaratively.
- Kubernetes:
  - Update `hosts/nandstorm/k8s/infrastructure/nvidia/nvidia-device-plugin.yaml`.
  - Use `hosts/nandstorm/k8s/infrastructure/nvidia/gpu-smoke-test.yaml` for repeatable validation (suspended `CronJob`).

## Idempotence and Recovery
- NixOS: `nixos-rebuild switch --flake .#nandstorm` is idempotent.
- K8s: `kubectl apply -k hosts/nandstorm/k8s` is idempotent.
- Recovery:
  - If K3s becomes unstable, first remove/disable the device plugin DaemonSet and revert containerd config changes.
  - Keep host GPU working in isolation as the baseline.

## Artifacts and Notes
- Avoid long-running host-side patch loops that mutate `/var/run/cdi/*`.
- Prefer: generate correct CDI once (declaratively) and consume it.

## Interfaces and Dependencies
- NixOS: `hardware.nvidia`, `hardware.nvidia-container-toolkit`
- K3s/containerd: CDI support (containerd 1.7+ strongly preferred)
- NVIDIA device plugin: version pinned and behavior validated for our selected strategy
