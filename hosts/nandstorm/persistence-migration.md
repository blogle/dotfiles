# Persistence Migration

## Purpose

`/persist` is its own ZFS dataset. Declaring directories beneath it in
`environment.persistence."/persist"` creates bind mounts from
`/persist/persist/<name>` over `/persist/<name>`. Those bind mounts can hide
the application state stored directly in the ZFS dataset after a reboot.

The NixOS configuration now removes those redundant child declarations. This
document describes the required one-time migration before deploying that
change.

## Maintenance Window

This procedure stops k3s and interrupts every workload on `nandstorm`.
Do not run it while anyone is using cluster services.

Run the commands as `root` on `nandstorm`. Set a timestamp once so every
backup has a matching name:

```sh
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
```

## Backup

Create a ZFS snapshot and archive the currently active bind-mount sources:

```sh
zfs snapshot rpool/safe/persist@before-bind-mount-migration-$timestamp
tar -C /persist/persist -czf /persist/recovery/bind-sources-$timestamp.tgz \
  acestream-proxy bitmagnet dispatcharr dojo jellyfin jellyseerr \
  m3u-playlists penpot prowlarr radarr sonarr teamarr transmission
```

## Migrate

Stop k3s, then stop the redundant mounts. This exposes the canonical ZFS
directories at `/persist/<name>`:

```sh
systemctl stop k3s

names='acestream-proxy bitmagnet dispatcharr dojo jellyfin jellyseerr m3u-playlists penpot prowlarr radarr sonarr teamarr transmission'
units=''
for name in $names; do
  units="$units $(systemd-escape --path --suffix=mount /persist/$name)"
done
systemctl stop $units
```

Copy the active bind-mount sources into those exposed canonical directories:

```sh
for name in $names; do
  rsync -aHAX --delete "/persist/persist/$name/" "/persist/$name/"
done
```

Deploy the NixOS configuration that removes the child persistence entries.
From this repository:

```sh
nix run github:serokell/deploy-rs -- .#nandstorm
```

## Verify

After deployment, ensure the old bind mounts are absent and start k3s:

```sh
for name in $names; do
  systemctl is-active "$(systemd-escape --path --suffix=mount /persist/$name)" && exit 1 || true
done

systemctl start k3s
kubectl -n media get pods
```

Check that each application has its expected database and state. Reboot
`nandstorm` once during the maintenance window, then verify the media apps do
not enter onboarding. Retain the ZFS snapshot and archive until that reboot
test succeeds.
