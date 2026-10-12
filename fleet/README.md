# SDLC Fleet

`manifest.yaml` is the owner-pinned inventory. Only `anvil` is enabled; `sdlc`
and `dotfiles` remain suspended.

The workflow is intentionally thin. It dispatches the SDLC CLI exported by
Anvil's flake directly:

```sh
nix run 'github:blogle/anvil#sdlc' -- ruleset plan --repo blogle/anvil
```

The pull-request plan uses `github:blogle/anvil/<current-pr-90-head>#sdlc` for
the first-canary validation. Protected reconciliation uses
`github:blogle/anvil#sdlc` after merge. A manual `bootstrap_pr90=true` dispatch
uses the exact current PR #90 head for initial apply.

Protected reconciliation uses Anvil `main` after merge. For the first canary,
an operator may manually dispatch with `bootstrap_pr90=true`; the workflow
queries PR #90 and uses its exact current head, not an arbitrary ref.
Ruleset apply and check require the dotfiles repository variable
`SDLC_FLEET_APPLY=1`. The App token is scoped to `blogle/anvil` and has only
Administration, Contents read, Secrets write, and Variables write.

The `ruleset` commands depend on the new SDLC worker release. Until that
release is available, the workflow verifies Nix resolution and reports the
dependency without a compatibility fallback.

Release setup is a separate explicit step. Only when both
`SDLC_FLEET_APPLY=1` and `SDLC_FLEET_RELEASE_ENABLE=1` are set does the
workflow copy the two release App values into Anvil repository secrets and set
`SDLC_RELEASE_ACTIVATE=true` last. Repository secrets are used for this MVP
because the existing Anvil v1.3 release caller uses `secrets: inherit`;
environment-secret migration is deferred.

## Operator Steps

1. Review Anvil PR #90 and its ruleset/release workflows.
2. After the SDLC worker release includes `ruleset`, set `SDLC_FLEET_APPLY=1`
   and manually dispatch with `bootstrap_pr90=true` to apply/check the ruleset
   from PR #90’s verified current head.
3. After Anvil is merged, run the protected workflow against `main` to confirm
   the same ruleset.
4. Later, set `SDLC_FLEET_RELEASE_ENABLE=1` for a separate explicit release
   credential/activation run; activation remains off by default.

No App installation, ruleset, secret, variable, merge, or queue changes are
performed by this PR.
