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

  vim-build = pkgs.vim-full.override {
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
    pkgs.codex
    pkgs.brightnessctl
    pkgs.bind
    pkgs.deploy-rs
    pkgs.docker
    pkgs.docker-compose
    pkgs.flameshot
    pkgs.ffmpeg-full
    pkgs.gemini-cli
    pkgs.git
    pkgs.gnumake
    pkgs.google-chrome
    pkgs.hotspot
    pkgs.home-manager
    pkgs.htop
    pkgs.jq
    pkgs.kubectl
    pkgs.kubeseal
    pkgs.ngrok
    pkgs.nmap
    pkgs.opencode
    pkgs.pavucontrol
    pkgs.pywal
    pkgs.ripgrep
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

  programs.tmux =
  let tmux-pain-control = pkgs.writeScript "tmux-pain-control"
    (builtins.readFile ./config/tmux-pain-control.tmux);
  in {
    enable = true;

    baseIndex = 1;
    escapeTime = 0;
    historyLimit = 50000;
    keyMode = "vi";

    terminal = "xterm-256color";
    extraConfig = ''
      # Rebind prefix key to backtick.
      # Note: home-manager doesn't seem to correctly re-bind prefix.
      unbind C-a
      set -g prefix `
      bind ` send-prefix

      # Disable the i so we can use it for window nav
      unbind-key i
      bind-key ? show-messages

      # Run our custom plugin for window manipulatioN
      run-shell ${tmux-pain-control}
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

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };

  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true;
    defaultCacheTtl = 1800;
    enableSshSupport = true;
    pinentry.package = pkgs.pinentry-gtk2;
  };

  programs.bash =
  let
    wallpaper = ./config/wallpaper/bhambay.webp;
  in {
    enable = true;
    initExtra = ''
      if [ -f "$HOME/.cache/wal/sequences" ]; then
        cat $HOME/.cache/wal/sequences
      else
        wal -i ${wallpaper} -q
      fi
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
    settings = {
      user = {
        name = "Brandon Ogle";
        email = "oglebrandon@gmail.com";
      };
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
      extensions.packages = with pkgs.nur.repos.rycee; [
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
