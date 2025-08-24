# Repository Guidelines

## Project Structure & Module Organization
- `flake.nix`: Entry point defining inputs, overlays, and outputs.
- `hosts/<host>`: NixOS machine configs (e.g., `modulus`, `nandstorm`).
- `home/`: Home Manager config for user `ogle`.
- `modules/`: Reusable NixOS/Home Manager modules.
- `pkgs/`: Local overlays and custom packages.
- `secrets/`: Age-encrypted secrets and `secrets.nix` key mapping.
- `hosts/nandstorm/k8s/`: Kustomize manifests for the single-node k3s cluster.

## Build, Test, and Development Commands
- `nix flake check`: Run flake and deploy checks.
- `home-manager switch --flake .#home`: Apply Home Manager config.
- `sudo nixos-rebuild {build,test,switch} --flake .#<host>`: Build or activate a host.
- `nix run github:serokell/deploy-rs -- .#nandstorm`: Remote deploy via deploy-rs.
- `kubectl diff -k hosts/nandstorm/k8s && kubectl apply -k hosts/nandstorm/k8s`: Review and apply k8s changes.

## Coding Style & Naming Conventions
- Nix: 2-space indent, trailing commas allowed, attributes kebab-case.
- Files/dirs: lower-kebab-case; host dirs match hostname.
- Keep modules focused and colocate host-specific logic under `hosts/<host>/`.
- Secrets: name as `*.age` with clear purpose; wire keys in `secrets/secrets.nix`.

## Testing Guidelines
- Run `nix flake check` before opening a PR.
- Build hosts locally with `nixos-rebuild build --flake .#<host>`; verify switch on a test machine.
- For Kubernetes, `kubectl diff -k hosts/nandstorm/k8s` and verify pods/services before `apply`.

## Commit & Pull Request Guidelines
- Commits: short, imperative subjects (e.g., "Fix k8s media volumes"). Optional scope prefixes like `hosts/nandstorm:` or `k8s:` help.
- PRs: include summary, affected hosts, validation steps/commands, k8s impact, and note any secrets added/rotated (with key updates in `secrets.nix`).

## Declarative State & Impermanence
- `nandstorm` uses impermanence: all non-persisted state is wiped on reboot.
- Everything must be declarative in this repo (services, users, packages, sysctl, k8s setup).
- Persist required dirs via `environment.persistence."/persist".directories` in `hosts/nandstorm/default.nix` (e.g., `/var/lib/{rancher,kubelet,containerd}`, `/var/log`).
- Kubernetes volumes must use hostPath under `/persist/...` and those paths must be listed in persistence; avoid `emptyDir` or ephemeral storage.

## Security & Configuration Tips
- Secrets are never stored in plaintext. Use agenix: `agenix -e secrets/<name>.age` (recipients in `secrets/secrets.nix`).
- Reference as `age.secrets.<name>.file = ./secrets/<name>.age;` and, for k8s, load via the configured NixOS service (e.g., Cloudflare token) rather than committing raw Secrets.
