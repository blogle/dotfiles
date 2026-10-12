# SDLC Fleet

`manifest.yaml` is the owner-pinned inventory. Only `anvil` is enabled; `sdlc`
and `dotfiles` remain suspended.

The workflow is intentionally thin. It checks out the selected Anvil commit,
changes into that checkout, and runs the SDLC CLI exported by Anvil's locked
flake:

```sh
nix run .#sdlc -- policy plan --repo blogle/anvil
```

The read-only plan targets the current head of Anvil PR #90, so it does not
attempt to plan the nonexistent policy file on Anvil `main`.

Protected reconciliation uses Anvil `main` after merge. For the first canary,
an operator may manually dispatch with `bootstrap_pr90=true`; the workflow
queries PR #90 and checks out its exact current head, not an arbitrary ref.
Policy apply and check require the dotfiles repository variable
`SDLC_FLEET_APPLY=1`. The App token is scoped to `blogle/anvil` and has only
Administration, Contents read, Secrets write, and Variables write.

Release setup is a separate explicit step. Only when both
`SDLC_FLEET_APPLY=1` and `SDLC_FLEET_RELEASE_ENABLE=1` are set does the
workflow copy the two release App values into Anvil repository secrets and set
`SDLC_RELEASE_ACTIVATE=true` last. Repository secrets are used for this MVP
because the existing Anvil v1.3 release caller uses `secrets: inherit`;
environment-secret migration is deferred.

## Operator Steps

1. Review Anvil PR #90 and its policy/release workflows.
2. Set `SDLC_FLEET_APPLY=1` and manually dispatch with `bootstrap_pr90=true`
   to apply/check the policy from PR #90’s verified current head.
3. After Anvil is merged, unset `SDLC_FLEET_APPLY` or run the protected
   workflow against `main` to confirm the same policy.
4. Later, set `SDLC_FLEET_RELEASE_ENABLE=1` for a separate explicit release
   credential/activation run; activation remains off by default.

No App installation, repository policy, secret, variable, merge, or queue
changes are performed by this PR.
