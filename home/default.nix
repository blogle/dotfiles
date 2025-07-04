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

  vscode = pkgs.vscode-with-extensions.override {
    vscodeExtensions = with pkgs.nix-vscode-extensions.vscode-marketplace; [
      ms-dotnettools.csdevkit
      rooveterinaryinc.roo-cline
      visualstudiotoolsforunity.vstuc
      vscodevim.vim
    ];
  };

  python = pkgs.python313;

  rust = pkgs.rust-bin.stable.latest.default;

in
{
  # Let Home Manager install and manage itself.
  programs.home-manager.path = pkgs.home-manager-path;
  home.packages =
  [
    pkgs.agenix
    pkgs.alsa-utils
    pkgs.arandr
    pkgs.brightnessctl
    pkgs.google-chrome
    pkgs.bind
    pkgs.deploy-rs
    pkgs.docker
    pkgs.docker-compose
    pkgs.flameshot
    pkgs.ffmpeg-full
    pkgs.git
    pkgs.gnumake
    pkgs.hotspot
    pkgs.home-manager
    pkgs.htop
    pkgs.jq
    pkgs.kubectl
    pkgs.ngrok
    pkgs.nmap
    pkgs.nodejs_latest
    pkgs.pavucontrol
    pkgs.pywal
    pkgs.ripgrep
    pkgs.rust-analyzer
    pkgs.socat
    pkgs.spotify
    pkgs.uv
    pkgs.vlc
    pkgs.wget
    pkgs.wireshark
    pkgs.xdg-utils
    pkgs.zip
    pkgs.unzip
    pkgs.unityhub
    pkgs.zoom-us
    python
    rust
    st
    vim
    vscode
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
    pinentryPackage = pkgs.pinentry-gtk2;
  };

  programs.bash =
  let
    wallpaper = ./config/wallpaper/bhambay.webp;
  in {
    enable = true;
    bashrcExtra = ''
      wal -i ${wallpaper}

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
    userEmail = "oglebrandon@gmail.com";
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
      nativeMessagingHosts = [
        pkgs.tridactyl-native
      ];
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
