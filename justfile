set dotenv-load := false

check:
  nix flake check --no-build

ci-fast:
  nix build .#hydraJobs.x86_64-linux.ci-pr-fast.deploy-schema .#hydraJobs.x86_64-linux.ci-pr-fast.deploy-activate .#hydraJobs.x86_64-linux.ci-pr-fast.flake-evaluation --no-link

ci-candidate:
  nix build .#hydraJobs.x86_64-linux.ci-candidate.home-activation .#hydraJobs.x86_64-linux.ci-candidate.modulus-toplevel .#hydraJobs.x86_64-linux.ci-candidate.nandstorm-toplevel --no-link

skills:
  skills add blogle/sdlc --skill sdlc --agent opencode -y

skills-update:
  skills update -y
