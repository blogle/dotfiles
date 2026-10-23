set dotenv-load := false

check:
  nix flake check --no-build
  python3 -m unittest tests.test_sdlc_fleet

ci-fast:
  nix build .#ci.x86_64-linux.fast.flake-evaluation --no-link

ci-candidate:
  nix build .#ci.x86_64-linux.verify.deploy-schema .#ci.x86_64-linux.verify.home-activation .#ci.x86_64-linux.verify.modulus-toplevel .#ci.x86_64-linux.verify.nandstorm-toplevel .#ci.x86_64-linux.verify.deploy-activate --no-link

skills:
  skills add https://github.com/blogle/sdlc/tree/v1/skills/sdlc --skill sdlc --agent opencode --yes

skills-update:
  skills update -p -y
