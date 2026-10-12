# Fleet Controller

`manifest.yaml` is the declarative enrollment list. It is JSON-compatible YAML
so validation uses only the Python standard library. IDs are immutable GitHub
IDs obtained from read-only API calls; a name change cannot silently replace a
repository.

`security-floor.json` is intentionally smaller than SDLC policy: it only
forbids destructive changes and App/agent bypasses. Its null human bypass is a
safe unconfigured value; reconciliation refuses to proceed until an operator
supplies exactly one real personal GitHub user ID.

`controller.json` pins the current SDLC prepare-only PR #80 head. The
controller verifies the immutable commit and GitHub compare result proving it
is an ancestor of protected SDLC `main`; a merged PR head or squash metadata
alone is never accepted. While PR #80 is open or diverged from `main`,
reconciliation is unknown and reports an explicit repin requirement.
`policy.json` is the worker input template; its null bypass is filled only from
the operator floor at runtime.

The workflow is prepare-only. Pull requests run a read-only plan and invoke
the real pinned SDLC CLI contract. Protected
`master` runs diagnostics and remains a no-op until an operator configures the
four App credentials and intentionally sets `SDLC_FLEET_APPLY=1` in the
protected environment. The controller delegates policy and GitHub mutation to
the SDLC CLI `fleet` public interface with separate manifest, policy,
attestation, consumer-pin, and human-bypass inputs. A successful worker call
means only `prepared`; it never means activation readiness or a completed
mutation.

`enabled: false` is an intentional pause for activation, while `state:
suspended` pauses all automated mutation. Neither state removes existing GitHub
protections or secrets. Enabled repositories remain `unknown` until policy,
installation, checks, and release credentials are verified; unsafe results
disable activation, while transient unknown results retain current activation.
Consumer check names and ruleset policy remain owned by SDLC.

Each active consumer is resolved independently from its immutable default-branch
`flake.lock`. The controller validates the `blogle/sdlc` owner/repository,
revision, immutable release ref, commit existence, and protected-main ancestry,
then passes that consumer-specific revision to SDLC. Different releases and a
rollback are not replaced by a uniform fleet pin.

Release App propagation is environment-scoped only. Bootstrap must explicitly
grant and verify `Environments: write` in addition to the agreed Actions
Secrets/Variables and Administration permissions, and the called release job
must declare `environment: sdlc-release` and read its environment secrets.
`secrets: inherit` does not provide that wiring. Missing or unknown
`Environments: write`, or missing workflow wiring, blocks readiness; the
controller never falls back to repository-wide secrets.

The current SDLC release reusable workflow does not yet prove this environment
contract. The canonical SDLC fleet specification should document the required
permission and caller/called-workflow wiring before bootstrap. No App
permission has been changed here.

Operator bootstrap checklist, deferred until the source pin is protected:
create/install the fleet App only for Anvil with Administration: write, Actions
Secrets: write, Actions Variables: write, Environments: write, and Contents:
read; provide its ID/private key plus the separate release App ID/private key
as protected secrets in the fleet-reconcile environment; set the protected
environment variable `SDLC_FLEET_APPLY=1`; and configure `sdlc-release` as a
protected environment restricted to the release branch/workflow. The release
App itself must not receive Administration, Secrets, Variables, or Environments
write. None of these bootstrap actions has been performed.

The security-review check is expected to be red on this draft until a human
approves its exact head. CODEOWNERS and this check are only prerequisites;
operators must separately require them in GitHub rulesets. They are not
currently proven external protection and cannot authorize automatic queueing.
