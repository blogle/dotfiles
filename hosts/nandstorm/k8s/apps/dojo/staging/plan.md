# Deploy Dojo to Staging Environment

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

Reference: [.agent/PLANS.md](../.agent/PLANS.md) - This document must be maintained in accordance with PLANS.md.

## Purpose / Big Picture

This plan configures the `staging` deployment of the `dojo` application in the `dotfiles` repository, targeting the `nandstorm` Kubernetes cluster. It wires up the GitOps state so that the cluster pulls the Kustomize overlay defined in the `dojo` repository (`github.com/blogle/dojo`).

After this work is complete, the `nandstorm` cluster will have a `dojo-staging` namespace running the `dojo` application, accessible via `staging-dojo.thejeffer.net` (or similar ingress), with persistent storage mapped to the host's `/persist` volume.

## Progress

- [x] **Milestone 1: Create Staging Manifests**
    - [x] Create `hosts/nandstorm/k8s/apps/dojo/staging` directory.
    - [x] Create `namespace.yaml` for `dojo-staging`.
    - [x] Create `volumes.yaml` defining `dojo-staging-pv` pointing to `/persist/dojo/staging`.
    - [x] Create `ingress.yaml` for `staging-dojo.thejeffer.net`.
    - [x] Create `kustomization.yaml` referencing the remote `dojo` overlay and local resources.
- [x] **Milestone 2: Integrate with Cluster**
    - [x] Update `hosts/nandstorm/k8s/apps/kustomization.yaml` to include `dojo/staging`.
    - [x] Verify `kubectl diff -k hosts/nandstorm/k8s` (dry run if possible, or just inspection).

## Surprises & Discoveries

*None yet.*

## Decision Log

- Decision: Use `hostPath` with `DirectoryOrCreate` under `/persist/dojo/staging` for storage.
  Rationale: Matches existing pattern in `media-volumes.yaml` for the `nandstorm` cluster, which lacks dynamic storage provisioning.
  Date: 2025-11-26

- Decision: Define Ingress in `dotfiles` repo.
  Rationale: Ingress configuration (hosts, issuer) is environment-specific and infrastructure-dependent, fitting better in the infra repo (`dotfiles`) than the app repo.
  Date: 2025-11-26

## Context and Orientation

- **`dotfiles` repo**: The infrastructure repository managing the NixOS configuration and Kubernetes manifests for `nandstorm`.
- **`dojo` repo**: The application repository providing the Kustomize base and overlays.
- **`hosts/nandstorm/k8s/apps`**: The root for application manifests in the cluster.

## Plan of Work

### 1. Create Staging Directory Structure
We will create `hosts/nandstorm/k8s/apps/dojo/staging`.

### 2. Create Resource Files
- **`namespace.yaml`**: Defines `Namespace/dojo-staging`.
- **`volumes.yaml`**: Defines `PersistentVolume/dojo-staging-pv` (5Gi, hostPath).
- **`ingress.yaml`**: Defines `Ingress/dojo` (host: `staging-dojo.thejeffer.net`).
- **`kustomization.yaml`**:
    - Resources: `namespace.yaml`, `volumes.yaml`, `ingress.yaml`, `github.com/blogle/dojo//deploy/k8s/overlays/staging?ref=master`.
    - Patches: Bind `PersistentVolumeClaim/dojo-data` to `dojo-staging-pv`.

### 3. Register Application
Modify `hosts/nandstorm/k8s/apps/kustomization.yaml` to add `dojo/staging` to the `resources` list.

## Concrete Steps

1.  **Create Directory**:
    ```bash
    mkdir -p hosts/nandstorm/k8s/apps/dojo/staging
    ```

2.  **Write Files**:
    Use `write_file` for:
    - `hosts/nandstorm/k8s/apps/dojo/staging/namespace.yaml`
    - `hosts/nandstorm/k8s/apps/dojo/staging/volumes.yaml`
    - `hosts/nandstorm/k8s/apps/dojo/staging/ingress.yaml`
    - `hosts/nandstorm/k8s/apps/dojo/staging/kustomization.yaml`

3.  **Update Parent Kustomization**:
    Use `replace` (or `write_file` if simple) to add `dojo/staging` to `hosts/nandstorm/k8s/apps/kustomization.yaml`.

4.  **Validation**:
    Run `kubectl kustomize hosts/nandstorm/k8s/apps/dojo/staging` to verify the manifest renders correctly (requires `kubectl` installed).

## Validation and Acceptance

1.  **Render Manifests**:
    Run `kubectl kustomize hosts/nandstorm/k8s/apps/dojo/staging`.
    Expect output containing:
    - Namespace `dojo-staging`.
    - Deployment `dojo` with image `ghcr.io/blogle/dojo:edge`.
    - PVC `dojo-data` bound to volume `dojo-staging-pv`.
    - Ingress with host `staging-dojo.thejeffer.net`.

## Idempotence and Recovery

- Creating files is idempotent.
- Updates to `kustomization.yaml` should be careful to avoid duplication.

## Interfaces and Dependencies

- **Dojo Repo**: Must be public or accessible for Kustomize to pull the overlay.
- **Nandstorm Cluster**: Must be reachable for actual deployment (though we are just committing configs here).
