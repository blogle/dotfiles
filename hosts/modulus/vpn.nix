{ config, pkgs, ... }:
{
  services.tailscale = { enable = true; };
  networking.firewall.allowedUDPPorts = [ services.tailscale.port ];
}
