# Muxarr Setup

Muxarr is exposed at `https://muxarr.thejeffer.net` and requires the Pocket ID
`media-users` group through Traefik SSO. Its configuration and database are
persisted at `/persist/muxarr`; media is mounted at `/media`.

After deployment, complete Muxarr's setup wizard and configure Sonarr and
Radarr using their in-cluster addresses:

```text
http://sonarr.media.svc.cluster.local:8989
http://radarr.media.svc.cluster.local:7878
```

Create API keys in Sonarr and Radarr during setup rather than committing them
to this repository. Configure Muxarr's media profiles using paths beneath
`/media`, then use its preview flow before enabling automatic webhook
processing. Muxarr modifies media files in place.
