# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./graphics.nix
    ./virtualization.nix
    ./tailscale.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    zfs rollback -r rpool/local/root@blank
  '';

  boot.loader = {
    systemd-boot.enable = true;
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot";
    };
  #  grub = {
  #    enable = true;
  #    efiSupport = true;
  #    #efiInstallAsRemovable = true;
  #    version = 2;
  #    device = "nodev";
  #  };
  };
  
  networking.hostId = "deadb33f";
  networking.hostName = "nandstorm"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Set your time zone.
  # time.timeZone = "Europe/Amsterdam";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkbOptions in tty.
  # };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;


  

  # Configure keymap in X11
  # services.xserver.layout = "us";
  # services.xserver.xkbOptions = {
  #   "eurosign:e";
  #   "caps:escape" # map caps to escape.
  # };

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.mutableUsers = false;
  users.users.root.initialPassword = "hunter2";
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDMbxQQ6asa917aD8HTavEinmIEsm6G3pZEOv7Rf33JCvvrdCW5ktOsjBm0oeRLt3aeC0QZa3nrMXixP7GCmJQWFPnAsQLlrpZnNRte5GB9X0wcUTUcvLo1kXzTBB5CRhSwdVQ9+/Ztc+LSiObPqFfsYY2pa85wYU6Q+Hu+aYSDrTvCzcL1ojEvUKnOmSWFYQ+fmYV7skKJL3Xr66zpWeCKyVtY8h7Ju3H3IWZTTl8Fyqtej63uHxqjQlMNzEjUL9Nzmev+O8+lCKvHXG+8dQBAYe3+tsIi1NKLSODSKxLpka52XIiNrgGnnr74YTZ8sp8Sd9STr3HUPr7uNK5I8DSL brandon@standard.ai"
  ];
  
  users.users.ogle = {
    name = "ogle";
    group = "users";
    extraGroups = [ "wheel" "docker" ];
    createHome = true;
    home = "/home/ogle";
    uid = 1000;
    isNormalUser = true;
    packages = with pkgs; [
      vim
      google-cloud-sdk
    ];

    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDMbxQQ6asa917aD8HTavEinmIEsm6G3pZEOv7Rf33JCvvrdCW5ktOsjBm0oeRLt3aeC0QZa3nrMXixP7GCmJQWFPnAsQLlrpZnNRte5GB9X0wcUTUcvLo1kXzTBB5CRhSwdVQ9+/Ztc+LSiObPqFfsYY2pa85wYU6Q+Hu+aYSDrTvCzcL1ojEvUKnOmSWFYQ+fmYV7skKJL3Xr66zpWeCKyVtY8h7Ju3H3IWZTTl8Fyqtej63uHxqjQlMNzEjUL9Nzmev+O8+lCKvHXG+8dQBAYe3+tsIi1NKLSODSKxLpka52XIiNrgGnnr74YTZ8sp8Sd9STr3HUPr7uNK5I8DSL brandon@standard.ai"
      ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  # environment.systemPackages = with pkgs; [
  #   vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #   wget
  # ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "yes";

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.11"; # Did you read the comment?

}

