# SDLC Fleet

`manifest.yaml` is the owner-pinned inventory. Only `anvil` is enabled; `sdlc`
and `dotfiles` remain suspended.

The workflow is intentionally thin. It checks out the selected Anvil commit,
changes into that checkout, and runs the SDLC CLI exported by Anvil's locked
flake:

```sh
nix run .#sdlc -- policy plan --repo blogle/anvil
```

The pull-request plan targets the current head of Anvil PR #90 by default, so
it does not attempt to plan the nonexistent policy file on Anvil `main`.
`workflow_dispatch` accepts `anvil_ref` for another read-only target.

Protected reconciliation always runs `policy plan`. It runs `policy apply` and
`policy check` only when the operator sets the dotfiles repository variable
`SDLC_FLEET_APPLY=1`. The App token is scoped to `blogle/anvil` and has only
Administration, Contents read, Secrets write, and Variables write.

After policy verification, the workflow copies the two release App values into
Anvil repository secrets and sets `SDLC_RELEASE_ACTIVATE=true` last. Repository
secrets are used for this MVP because the existing Anvil v1.3 release caller
uses `secrets: inherit`; environment-secret migration is deferred.

## Operator Steps

1. Review Anvil PR #90 and its policy/release workflows.
2. Dispatch this workflow with `anvil_ref` set to the exact approved Anvil
   commit for a read-only plan.
3. After Anvil is merged and release credentials are confirmed, set
   `SDLC_FLEET_APPLY=1` and run the protected workflow once.
4. Remove or unset `SDLC_FLEET_APPLY` after convergence if ongoing scheduled
   reconciliation is not desired.

No App installation, repository policy, secret, variable, merge, or queue
changes are performed by this PR.
