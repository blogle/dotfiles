# tailscale.nix
{ config, pkgs, ... }: {
    # the nix expression containing age secret configuration, enabling tailscale packages and service, networking rules, and the systemd autoconnect unit file
    age.secrets.tailscale.file = ../../secrets/tailscale.age;

    # We'll install the package to the system, enable the service, and set up some networking rules
    environment.systemPackages = with pkgs; [ tailscale ];

    services.tailscale = {
      enable = true;
      authKeyFile = config.age.secrets.tailscale.path;
      # Act as subnet router (MetalLB pool) and exit-node client
      useRoutingFeatures = "both";
      extraUpFlags = [
        # Advertise only the minimal covering CIDR for 10.0.0.100-120
        "--advertise-routes=10.0.0.96/27"
        # Keep using the specified exit node and allow LAN access
        "--exit-node=us-sea-wg-001.mullvad.ts.net"
        "--exit-node-allow-lan-access"
      ];
    };

    networking = {
        firewall = {
            checkReversePath = "loose";
            allowedUDPPorts = [ config.services.tailscale.port ];
            trustedInterfaces = [ "tailscale0" ];
        };
    };

    # Enable subnet routing
    boot.kernel.sysctl = {
      "net.ipv4.conf.all.forwarding" = true;
      "net.ipv6.conf.all.forwarding" = true;
    };

}
