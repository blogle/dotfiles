# Cluster SSO

Pocket ID provides local-only OIDC at `https://id.thejeffer.net`. Tinyauth is
the shared Traefik forward-auth endpoint at `https://auth.thejeffer.net`.
Both use SQLite persisted under `/persist`; neither relies on a third-party
identity provider.

## Manual Bootstrap Before Apply

1. Apply only `namespace.yaml`, `pocket-id-secrets.sealed.yaml`, and
   `pocket-id.yaml`, then create the first Pocket ID administrator at
   `https://id.thejeffer.net`. Pocket ID authenticates administrators with
   passkeys, so an initial administrator cannot be pre-created as a Kubernetes
   password secret.
2. Create a Pocket ID OIDC client named `tinyauth` with callback URL
   `https://auth.thejeffer.net/api/oauth/callback/pocketid`.
3. Create `tinyauth-credentials.sealed.yaml` using its client ID, secret, and
   no plaintext Secret is committed:

   ```sh
   kubectl create secret generic tinyauth-credentials \
     --namespace auth \
     --from-literal=client-id='<Pocket ID client ID>' \
     --from-literal=client-secret='<Pocket ID client secret>' \
     --dry-run=client -o yaml \
     | kubeseal --format yaml \
         --controller-name sealed-secrets-controller \
         --controller-namespace kube-system \
     > hosts/nandstorm/k8s/apps/auth/tinyauth-credentials.sealed.yaml
   ```

4. Add `tinyauth-credentials.sealed.yaml` to `kustomization.yaml`. Tinyauth
   persists its cryptographically random session IDs in SQLite; v5.1.0 has no
   independent session-secret setting. Its secure cookie is scoped to
   `.thejeffer.net` from `TINYAUTH_APPURL`, so it is shared by all protected
   subdomains. Create a Pocket ID `media-users` group
   and add approved people to it. The current media apps require that group;
   future apps can require independent groups such as `dev-users`.
5. Install `jellyfin-plugin-sso` from
   `https://raw.githubusercontent.com/9p4/jellyfin-plugin-sso/manifest-release/manifest.json`.
   Create a separate Pocket ID client with callback URL
   `https://jellyfin.thejeffer.net/sso/OID/redirect/PocketID`, then configure
   the plugin API with issuer `https://id.thejeffer.net`, that client ID and
   secret, and an explicit user/group policy. Keep local Jellyfin accounts
   enabled for TV and mobile clients.
6. After Traefik forward-auth is working, scale Sonarr and Radarr to zero,
   edit each persisted `/config/config.xml` to set
   `<AuthenticationMethod>External</AuthenticationMethod>`, then scale back to
   one. Do not use "Disabled for Local Addresses". Their Services are already
   ClusterIP-only and the single `/` ingress path covers their UI and API.

## Apply Order

The prior OAuth2 Proxy ingress owns `auth.thejeffer.net`, so it cannot coexist
with the Tinyauth ingress. After completing the bootstrap above, run this
during a maintenance window:

```sh
kubectl -n auth delete ingress oauth2-proxy
kubectl apply -k hosts/nandstorm/k8s/apps
```

Verify a private browser session can access each protected hostname and that
Jellyfin native clients still use local login. Only then retire the obsolete
OAuth2 Proxy workload and its SealedSecrets:

```sh
kubectl -n auth delete deployment,service oauth2-proxy
kubectl -n auth delete sealedsecret oauth2-proxy-cookie oauth2-proxy-credentials
```

Set Servarr External mode only after that verification succeeds. For each app,
stop it before editing because it rewrites `config.xml` on clean shutdown:

```sh
kubectl -n media scale deployment/radarr --replicas=0
ssh root@nandstorm "perl -0pi -e 's#<AuthenticationMethod>.*?</AuthenticationMethod>#<AuthenticationMethod>External</AuthenticationMethod>#' /persist/radarr/config.xml"
kubectl -n media scale deployment/radarr --replicas=1
```

Repeat for `sonarr`. Confirm the element was changed before scaling each
deployment up. Do not apply External mode to another Servarr app until every
one of its ingress routes uses the same forward-auth middleware and its
Service remains ClusterIP-only.

OpenCode has no manifest in this repository. Add `auth-sso-auth@kubernetescrd`
to every OpenCode ingress route once its deployment location is identified.
