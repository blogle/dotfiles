# Fleet Controller

`manifest.yaml` is the declarative enrollment list. It is JSON-compatible YAML
so validation uses only the Python standard library. IDs are immutable GitHub
IDs obtained from read-only API calls; a name change cannot silently replace a
repository.

`security-floor.json` is intentionally smaller than SDLC policy: it only
forbids destructive changes and App/agent bypasses. Its null human bypass is a
safe unconfigured value, so no automated actor can become a break-glass actor.

The workflow is prepare-only. Pull requests run a read-only plan. Protected
`master` runs diagnostics and remains a no-op until an operator configures the
four App credentials and intentionally sets `SDLC_FLEET_APPLY=1` in the
protected environment. The controller delegates policy and GitHub mutation to
the SDLC CLI `fleet` public interface; an older CLI is reported as unsupported,
never treated as success or executed with credentials.

`enabled: false` is an intentional pause for activation, while `suspended:
true` pauses all automated mutation. Neither state removes existing GitHub
protections or secrets. Consumer check names and ruleset policy remain owned by
SDLC.
