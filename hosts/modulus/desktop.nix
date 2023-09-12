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

    # Enable touchpad support.
    libinput = {
      enable = true;
      touchpad.tapping = false;
    };

    xkbOptions = "caps:escape";
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
	Unit.Description = "Mpris proxy";
	Unit.After = [ "network.target" "sound.target" ];
	Service.ExecStart = "${pkgs.bluez}/bin/mpris-proxy";
	Install.WantedBy = [ "default.target" ];
  };

}
