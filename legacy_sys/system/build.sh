#!/usr/bin/env bash
profile=/nix/var/nix/profiles/system
config=$(nix-build -A toplevel)
nix-env -p $profile --set $config
$config/bin/switch-to-configuration $@
