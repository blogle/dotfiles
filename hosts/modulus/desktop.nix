{ config, pkgs, ... }:

{


  fonts.fontconfig.dpi = 192;

  # Enable the X11 windowing system.
  services.xserver = {
    enable = true;
    displayManager = {
      lightdm = {
        enable = true;
        greeter.enable = false;
      };
      autoLogin = {
        enable = true;
        user = "ogle";
      };

      defaultSession = "xsession";
      session = [{
        manage = "desktop";
        name = "xsession";
        start = ''
          exec $HOME/.xsession
        '';
       }];

    };

    xkbOptions = "caps:escape";
  };

  # Enable touchpad support.
  services.xserver.libinput = {
    enable = true;
    tapping = false;
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
    extraModules = [ pkgs.pulseaudio-modules-bt ];
  };

  # Enable bluetooth.
  hardware.bluetooth = {
    enable = true;
    package = pkgs.bluezFull;
    powerOnBoot = true;
    settings = {
      General = {
        Autoconnect = true;
        Enable = "Source,Sink,Media,Socket";
      };
    };
  };
}
