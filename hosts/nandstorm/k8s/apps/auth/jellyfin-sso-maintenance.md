# Jellyfin Browser SSO Maintenance

## Scope

This procedure adds a Pocket ID sign-in button to Jellyfin's web login page.
It does not add Traefik forward-auth to Jellyfin and does not replace native
Jellyfin accounts. TV and mobile clients must continue to use local Jellyfin
authentication through `/Users/AuthenticateByName`.

Schedule this during a maintenance window. Installing or updating the plugin
requires a Jellyfin restart.

## Prerequisites

1. Retain one tested local Jellyfin administrator account. Do not link the
   only administrator account to SSO during initial setup.
2. Create a Pocket ID OIDC client named `Jellyfin`:
   - Client launch URL: `https://jellyfin.thejeffer.net`
   - Callback URL: `https://jellyfin.thejeffer.net/sso/OID/redirect/PocketID`
   - Allowed user groups: `media-users`
   - Enable PKCE.
3. Record the client ID and secret outside this repository. The plugin stores
   its client configuration in Jellyfin's persistent data, so a Kubernetes
   SealedSecret cannot supply it without exposing the value in the plugin API.

## Backup

Stop Jellyfin before taking a consistent backup of its configuration:

```sh
kubectl -n media scale deployment/jellyfin --replicas=0
kubectl -n media wait --for=delete pod -l app=jellyfin --timeout=120s
ssh root@nandstorm 'timestamp=$(date -u +%Y%m%dT%H%M%SZ) && install -d -m 700 /persist/recovery && tar -C /persist/jellyfin -czf /persist/recovery/jellyfin-before-sso-$timestamp.tgz .'
kubectl -n media scale deployment/jellyfin --replicas=1
kubectl -n media rollout status deployment/jellyfin --timeout=180s
```

## Install Plugin

1. Sign in to the Jellyfin web UI with the retained local administrator.
2. Add this plugin repository under Dashboard > Plugins > Repositories:

   ```text
   https://raw.githubusercontent.com/9p4/jellyfin-plugin-sso/manifest-release/manifest.json
   ```

3. Install `SSO-Auth`, pin the compatible release rather than a nightly, and
   restart Jellyfin when prompted. The upstream project is archived and labels
   itself alpha software; do not install a nightly build in production.

## Configure Pocket ID

Configure the provider in the plugin's admin UI if the installed release
exposes it. Otherwise use its API with an administrator API key. Keep the
client secret in the current shell only:

```sh
export JELLYFIN_API_KEY='<local administrator API key>'
export JELLYFIN_OIDC_CLIENT_ID='<Pocket ID client ID>'
export JELLYFIN_OIDC_CLIENT_SECRET='<Pocket ID client secret>'

curl --fail --silent --show-error \
  -X POST \
  -H 'Content-Type: application/json' \
  -d "{\"oidEndpoint\":\"https://id.thejeffer.net/.well-known/openid-configuration\",\"oidClientId\":\"$JELLYFIN_OIDC_CLIENT_ID\",\"oidSecret\":\"$JELLYFIN_OIDC_CLIENT_SECRET\",\"enabled\":true,\"enableAuthorization\":false,\"enableAllFolders\":false,\"enabledFolders\":[],\"adminRoles\":[],\"roles\":[],\"enableFolderRoles\":false,\"folderRoleMapping\":[],\"roleClaim\":\"groups\",\"oidScopes\":[\"groups\"],\"defaultUsernameClaim\":\"email\",\"schemeOverride\":\"https\"}" \
  "https://jellyfin.thejeffer.net/sso/OID/Add/PocketID?api_key=$JELLYFIN_API_KEY"
```

`enableAuthorization` is intentionally `false` for the initial rollout. An
SSO-created account receives no library or administrative access until the
local Jellyfin administrator grants it explicitly. Do not enable group-to-role
mapping until that initial flow has been tested with a non-administrator.

## Add Login Button

Under Dashboard > General > Branding, add this to Login Disclaimer:

```html
<form action="/sso/OID/start/PocketID">
  <button class="raised block emby-button button-submit" type="submit">
    Sign in with Pocket ID
  </button>
</form>
```

If needed, add this custom CSS in the same branding section:

```css
a.raised.emby-button {
  padding: 0.9em 1em;
  color: inherit !important;
}

.disclaimerContainer {
  display: block;
}
```

## Verify

1. In a private browser window, visit `https://jellyfin.thejeffer.net` and
   select Sign in with Pocket ID.
2. Complete Pocket ID authentication and confirm the new Jellyfin account has
   no unexpected permissions.
3. Sign in with the retained local administrator and grant the intended
   libraries and permissions to the SSO account.
4. Confirm a TV or mobile client can still sign in with its existing local
   Jellyfin account through `10.0.0.101:8096`.
5. Confirm Jellyfin's normal web login still works with local accounts.

## Rollback

1. Use the local Jellyfin administrator or the direct service at
   `10.0.0.101:8096` to disable the SSO provider or plugin.
2. If Jellyfin cannot start after plugin installation, scale the deployment to
   zero, remove the plugin directory under `/persist/jellyfin/plugins/`, then
   scale it back to one.
3. If needed, restore the archive created in Backup while Jellyfin is stopped,
   then start it and verify local accounts before retrying.
