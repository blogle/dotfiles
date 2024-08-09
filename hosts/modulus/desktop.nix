{ config, pkgs, ... }:

{
  # Enable the X11 windowing system.
  services.xserver = {
    enable = true;
    dpi = 192;
    displayManager = {
      lightdm = {
        enable = true;
        greeter.enable = false;
      };

      session = [{
        manage = "desktop";
        name = "xsession";
        start = ''
          exec $HOME/.xsession
        '';
       }];

     };

    xkb.options = "caps:escape";
  };

  services.displayManager = {
    defaultSession = "xsession";
    autoLogin = {
      enable = true;
      user = "ogle";
    };
  };

  # Enable touchpad support.
  services.libinput = {
    enable = true;
    touchpad.tapping = false;
  };


  # TODO switch to pipewire for audio

  # Enable audio
  sound.enable = true;
  hardware.pulseaudio = {
    enable = true;
    package = pkgs.pulseaudioFull;
    extraConfig = ''
      load-module module-switch-on-connect
    '';
  };

  # Enable bluetooth.
  hardware.bluetooth = {
    enable = true;
    package = pkgs.bluez;
    powerOnBoot = true;
    settings = {
      General = {
        Autoconnect = true;
        Enable = "Source,Sink,Media,Socket";
      };
    };
  };

  # Allow buttons on bluetooth headphones to control audio.
  systemd.user.services.mpris-proxy = {
	description = "Mpris proxy";
    after = [ "network.target" "sound.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig.ExecStart = "${pkgs.bluez}/bin/mpris-proxy";
  };

}
