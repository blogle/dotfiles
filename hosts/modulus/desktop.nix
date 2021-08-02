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



  # Enable audio
  sound.enable = true;
  hardware.pulseaudio = {
    enable = true;
    package = pkgs.pulseaudioFull;
    extraConfig = ''
      load-module module-switch-on-connect
      load-module module-bluetooth-discover a2dp_config="ldac_eqmid=hq ldac_fmt=f32"
    '';
    extraModules = [ pkgs.pulseaudio-modules-bt ];
  };

  # Enable bluetooth.
  hardware.bluetooth = {
    enable = true;
    package = pkgs.bluezFull;
    powerOnBoot = true;
    config = {
      General = {
        Autoconnect = true;
        ControllerMode = "bredr";
        MultiProfile = "multiple";
        Enable = "Source,Sink,Media,Socket";
      };
    };
  };
}
