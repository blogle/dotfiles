# Repository Guidelines

## Project Structure & Module Organization
- `flake.nix`: Entry point defining inputs, overlays, and outputs.
- `hosts/<host>`: NixOS machine configs (e.g., `modulus`, `nandstorm`).
- `home/`: Home Manager config for user `ogle`.
- `modules/`: Reusable NixOS/Home Manager modules.
- `pkgs/`: Local overlays and custom packages.
- `secrets/`: Age-encrypted secrets and `secrets.nix` key mapping.
- `addrspace/`: Kustomize manifests for the `addrspace` k3s cluster.
- Kubernetes desired-state work belongs under `addrspace/`; `hosts/nandstorm/`
  contains node OS configuration only.

## Build, Test, and Development Commands
- This repository follows the shared SDLC contract. Read the committed OpenCode skill at `.agents/skills/sdlc/SKILL.md` for the SDLC workflow and integration protocol whenever changing CI, build/test contracts, Mergify policy, changelog fragments, or release workflows.
- `nix develop` provides the SDLC CLI, skills CLI, `just`, and `nix-eval-jobs`.
- `just check`, `just ci-fast`, and `just ci-candidate`: Run repository checks and the corresponding SDLC derivation stage.
- `just skills`: Install the canonical SDLC skill with Vercel's official `skills` CLI; `just skills-update` updates the committed installation using the CLI's native update command.
- `nix flake check`: Run flake and deploy checks.
- `home-manager switch --flake .#home`: Apply Home Manager config.
- `deploy .#<host>` or `nix run github:serokell/deploy-rs -- .#<host>`: Deploy NixOS config to a remote host via deploy-rs (primary method for remote hosts like nandstorm).
- `sudo nixos-rebuild switch --flake .#<host>`: Local rebuild only (use when physically on the machine, e.g., on modulus).
- `kubectl diff -k addrspace && kubectl apply -k addrspace`: Review and apply k8s changes.

## Coding Style & Naming Conventions
- Nix: 2-space indent, trailing commas allowed, attributes kebab-case.
- Files/dirs: lower-kebab-case; host dirs match hostname.
- Keep modules focused and colocate host-specific logic under `hosts/<host>/`.
- Secrets: name as `*.age` with clear purpose; wire keys in `secrets/secrets.nix`.

## Testing Guidelines
- Run `nix flake check` before opening a PR.
- Build hosts locally with `nixos-rebuild build --flake .#<host>`; verify switch on a test machine.
- For Kubernetes, follow `addrspace/README.md` for the established-cluster and fresh-bootstrap workflows; review `kubectl diff -k addrspace` before applying.

## Commit & Pull Request Guidelines
- Commits: short, imperative subjects (e.g., "Fix k8s media volumes"). Optional scope prefixes like `hosts/nandstorm:` or `k8s:` help.
- PRs: include summary, affected hosts, validation steps/commands, k8s impact, and note any secrets added/rotated (with key updates in `secrets.nix`).
- Every PR targeting `master` must carry exactly one of `integration:auto` or `integration:review`; `integration:review` waits for approval of the exact PR head before Mergify automatically queues it.

## Declarative State & Impermanence
- `nandstorm` uses impermanence: all non-persisted state is wiped on reboot.
- Everything must be declarative in this repo (services, users, packages, sysctl, k8s setup).
- Persist required node directories via `environment.persistence."/persist".directories` in `hosts/nandstorm/default.nix` (e.g., `/var/lib/{rancher,kubelet,containerd}`, `/var/log`).
- Kubernetes mutable application state should use OpenEBS ZFS PVCs. Intentional direct hostPath data (such as `/media` and `/persist/knowledge`) must use persisted paths; avoid ephemeral storage for durable state.

## Security & Configuration Tips
- Secrets are never stored in plaintext. Use agenix: `agenix -e secrets/<name>.age` (recipients in `secrets/secrets.nix`).
- Reference as `age.secrets.<name>.file = ./secrets/<name>.age;` and, for k8s, load via the configured NixOS service (e.g., Cloudflare token) rather than committing raw Secrets.
