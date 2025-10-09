{ config, lib, pkgs, ... }:

{
  # Headless Steam + Gamescope session with performance tooling

  # Create a dedicated user to run the session
  users.users.steam = {
    isNormalUser = true;
    description = "Steam session user";
    home = "/home/steam";
    createHome = true;
    shell = pkgs.bashInteractive;
    extraGroups = [ "video" "render" "input" "gamemode" ];
  };

  # Persist Steam state across reboots (impermanence)
  environment.persistence."/persist".directories = [
    { directory = "/home/steam"; user = "steam"; group = "steam"; mode = "0700"; }
  ];

  # Minimal Wayland greeter that auto-starts the Gamescope Steam session on TTY
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "steam-gamescope";
        user = "steam";
      };
    };
  };

  # Gamescope + Steam configuration
  programs.gamescope = {
    enable = true;
    capSysNice = true; # allow renice for smoother frame pacing
    env = {
      # Favor NVIDIA rendering if multiple GPUs are present
      __NV_PRIME_RENDER_OFFLOAD = "1";
      __VK_LAYER_NV_optimus = "NVIDIA_only";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    };
  };

  programs.steam = {
    enable = true;
    gamescopeSession = {
      enable = true;
      # Add common session args as needed; keep minimal by default
      args = [ ];
      env = {
        # Enable MangoHud overlay globally inside the Steam session
        MANGOHUD = "1";
      }; # additional env for the session wrapper if required
      steamArgs = [ "-tenfoot" "-pipewire-dmabuf" ];
    };

    # Helpful extras inside Steam's FHS env
    extraPackages = with pkgs; [
      gamescope
      mangohud
      protontricks
    ];

    # Prefer Proton-GE when available for wider game compatibility
    extraCompatPackages = lib.optional (pkgs ? proton-ge-bin) pkgs.proton-ge-bin;

    # Open Steam networking ports for Remote Play + LAN transfers
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };

  # Enable Feral GameMode for on-demand performance tweaks
  programs.gamemode = {
    enable = true;
    enableRenice = true;
    settings = {
      general = {
        renice = 10;
      };
      # GPU tuning is disabled by default; enable carefully if desired
      # gpu.apply_gpu_optimisations = "accept-responsibility";
      # gpu.gpu_device = 0;
    };
  };

  # PipeWire for audio (Steam Remote Play, etc.)
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
}
