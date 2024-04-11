# tailscale.nix
{ config, pkgs, ... }: {
    # the nix expression containing age secret configuration, enabling tailscale packages and service, networking rules, and the systemd autoconnect unit file
    age.secrets.tailscale.file = ../../secrets/tailscale.age;

    # We'll install the package to the system, enable the service, and set up some networking rules
    environment.systemPackages = with pkgs; [ tailscale ];
    services.tailscale.enable = true;
    networking = {
        firewall = {
            checkReversePath = "loose";
            allowedUDPPorts = [ config.services.tailscale.port ];
            trustedInterfaces = [ "tailscale0" ];
        };
    };

    # Here is the magic, where we automatically connect with the tailscale CLI by passing our secret token, and ensure that agenix mounting was completed
    systemd.services.tailscale-autoconnect = {
        description = "Automatic connection to Tailscale";

        # We must make sure that both the tailscale service and the agenix file mounting are running / complete before trying to connect to tailscale
        after = [ "network-pre.target" "tailscale.service" "run-agenix.d.mount" ];
        wants = [ "network-pre.target" "tailscale.service" "run-agenix.d.mount" ];
        wantedBy = [ "multi-user.target" ];

        # Set this service as a oneshot job
        serviceConfig.Type = "oneshot";

        # Run the following shell script for the job, passing the mounted secret for the tailscale connection
        script = with pkgs; ''
            # wait for tailscaled to settle
            sleep 2

            # check if we are already authenticated to tailscale
            status="$(${tailscale}/bin/tailscale status -json | ${jq}/bin/jq -r .BackendState)"
            if [ $status = "Running" ]; then
                exit 0
            fi

            # otherwise authenticate with tailscale
            ${tailscale}/bin/tailscale up -authkey "$(cat "${config.age.secrets.tailscale.path}")"
        '';
    };
}
