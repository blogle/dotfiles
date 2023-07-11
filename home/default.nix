{ config, pkgs, ... }:

let

  rofi-theme = ./config/theme.rasi;
  st-xresources = pkgs.fetchurl {
    url = https://st.suckless.org/patches/xresources/st-xresources-20180309-c5ba9c0.diff;
    sha256 = "1qgck68sf4s47dckvl9akjikjfqhvrv70bip0l3cy2mb1wdlln6d";
  };

  st = pkgs.st.override {
    conf = builtins.readFile ./config/st-config.h;
    patches = [ pkgs.st-clipboard ];
  };

  vim-build = pkgs.vim_configurable.override {
    python3 = python;
  };

  vim = vim-build.customize {
    name = "vim";
    vimrcConfig.customRC = builtins.readFile ./config/.vimrc;
  };

  python = pkgs.python39;

  rust = pkgs.rust-bin.stable.latest.default;

in
{
  # Let Home Manager install and manage itself.
  programs.home-manager.path = pkgs.home-manager-path;
  home.packages =
  [
    pkgs.alsa-utils
    pkgs.arandr
    pkgs.berglas
    pkgs.brightnessctl
    pkgs.cbt
    pkgs.google-cloud-sdk
    pkgs.google-chrome
    pkgs.bind
    pkgs.deploy-rs
    pkgs.docker
    pkgs.docker-compose
    pkgs.flameshot
    pkgs.ffmpeg-full
    pkgs.git
    pkgs.git-lfs
    pkgs.gnumake
    pkgs.hotspot
    pkgs.home-manager
    pkgs.htop
    pkgs.jq
    pkgs.mutagen
    pkgs.niv
    pkgs.nmap
    pkgs.nodejs_latest
    pkgs.pavucontrol
    pkgs.pywal
    pkgs.ripgrep
    pkgs.rust-analyzer
    pkgs.slack
    pkgs.socat
    pkgs.spotify
    pkgs.vlc
    pkgs.wget
    pkgs.wireshark
    pkgs.xdg-utils
    pkgs.zoom-us
    python
    rust
    st
    vim
  ];

  home.sessionVariables = {
    EDITOR = "vim";
    SSH_ASKPASS = pkgs.writeShellScript "ask-pass" ''
      rofi -dmenu -password -i -no-fixed-num-lines -p "Password:" -theme ${rofi-theme}
    '';
  };

  # X11 Configuration
  xsession = {
    enable = true;
    windowManager.xmonad = {
      enable = true;
      config = ./config/xmonad.hs;
      enableContribAndExtras = true;
    };

    initExtra = ''
        # Configure desired keybindings
        ${pkgs.xorg.xkbcomp}/bin/xkbcomp ${./config/qgmlwy.xkb} $DISPLAY
    '';
  };

  xresources = {
    #extraConfig = ''
    #  #include "/home/ogle/.cache/wal/colors.Xresources"
    #'';
  };

  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true;
    defaultCacheTtl = 1800;
    enableSshSupport = true;
    pinentryFlavor = "gtk2";
  };

  programs.bash = {
    enable = true;
    bashrcExtra = ''
      #wal -Rq
      export VAULT_USERNAME=ogle
      export VAULT_ADDR=https://vault.nonstandard.ai:8200

      # Required to make Ansible work properly
      export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

      . ~/.profile
    '';
    shellAliases = {
      #auth = "eval $(${_1password}/bin/op signin)";
      docker-clean = "${pkgs.docker}/bin/docker rmi $(docker images -q)";
      pbcopy = "${pkgs.xsel}/bin/xsel --clipboard --input";
      pbpaste = "${pkgs.xsel}/bin/xsel --clipboard --output";
    };
  };

  programs.git = {
    enable = true;
    userName = "Brandon Ogle";
    userEmail = "brandon@standardcognition.com";
    #delta = { enable = true; };
    extraConfig = {
      credential.helper = "store";
	  "filter \"lfs\"" = {
		 clean = "${pkgs.git-lfs}/bin/git-lfs clean -- %f";
		 smudge = "${pkgs.git-lfs}/bin/git-lfs smudge --skip -- %f";
		 process = "${pkgs.git-lfs}/bin/git-lfs filter-process --skip";
         required = true;
       };
    };
  };

  programs.keychain = {
    enable = true;
    # I just want the xsession integration
    enableBashIntegration = false;
    enableFishIntegration = false;
    enableZshIntegration = false;
    enableNushellIntegration = false;
  };

  programs.tmux =
  # This file needs to be made executable
  let tmux-pain-control = pkgs.writeScript "tmux-pain-control-tmux"
    (builtins.readFile ./config/tmux-pain-control.tmux);
  in {
    enable = true;
    terminal = "xterm-256color";
    prefix = "`";
    historyLimit = 50000;
    extraConfig = ''
      unbind-key i
      bind-key ? show-messages

      run-shell ${tmux-pain-control}
    '';

  };


  home.file.firefox-vim = {
    source = ./config/vimperatorrc;
    target = ".tridactylrc";
  };
  programs.firefox = {
    profiles.default.id = 0;

    enable = true;

    package = pkgs.firefox.override {
      cfg.enableTridactylNative = true;
    };

    profiles.default = {
      extensions = with pkgs.nur.repos.rycee; [
        firefox-addons.onepassword-password-manager
        firefox-addons.tridactyl
      ];
    };
  };

  programs.rofi = {
    enable = true;
    terminal = "${pkgs.st}/bin/st";
    theme = rofi-theme;
    font = "System San Francisco Display Regular 36";
    extraConfig = {
	  show = "run";
	  blur-background = "true";
	  modi ="window,ssh,run";
    };
  };

}
