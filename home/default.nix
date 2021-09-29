{ config, pkgs, ... }:

let
  homeDir = "/home/ogle";#builtins.getEnv "HOME";
  #pkgsUnstable = import <nixpkgs-unstable> {};

  st-xresources = pkgs.fetchurl {
    url = https://st.suckless.org/patches/xresources/st-xresources-20180309-c5ba9c0.diff;
    sha256 = "1qgck68sf4s47dckvl9akjikjfqhvrv70bip0l3cy2mb1wdlln6d";
  };

  st = pkgs.st.override {
    conf = builtins.readFile ./config/st-config.h;
    patches = [ pkgs.st-clipboard ];
  };

  vim-build = pkgs.vim_configurable.override {
    python = python;
  };

  vim = vim-build.customize {
    name = "vim";
    vimrcConfig.customRC = builtins.readFile ./config/.vimrc;
  };

  python = pkgs.python36.withPackages (ps: [
    ps.python-language-server
    ps.pyls-mypy ps.pyls-isort ps.pyls-black
  ]);

in
{
  # Let Home Manager install and manage itself.
  programs.home-manager.path = pkgs.home-manager-path;
  home.packages =
  [
    pkgs.alsaUtils
    pkgs.arandr
    pkgs.arcanist
    pkgs.berglas
    pkgs.brightnessctl
    pkgs.cog
    pkgs.google-cloud-sdk
    pkgs.bind
    pkgs.docker
    pkgs.docker-compose
    pkgs.flameshot
    pkgs.git
    pkgs.git-lfs
    pkgs.gnumake
    pkgs.htop
    pkgs.jq
    pkgs.niv
    pkgs.nmap
    pkgs.pavucontrol
    pkgs.pywal
    pkgs.ripgrep
    pkgs.rls
    pkgs.socat
    pkgs.spotify
    pkgs.vlc
    pkgs.wget
    pkgs.xdg_utils
    pkgs.zoom-us
    pkgs.obsidian
    st
    vim
  ];

  home.sessionVariables = {
    EDITOR = "vim";
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
      ${pkgs.xorg.xkbcomp}/bin/xkbcomp ${./config/qgmlwy.xkb} $DISPLAY'';
    };

  xresources = {
    extraConfig = ''
      #include "/home/ogle/.cache/wal/colors.Xresources"
    '';
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
      wal -Rq
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
	  "filter \"lfs\"" = {
		 clean = "${pkgs.git-lfs}/bin/git-lfs clean -- %f";
		 smudge = "${pkgs.git-lfs}/bin/git-lfs smudge --skip -- %f";
		 process = "${pkgs.git-lfs}/bin/git-lfs filter-process --skip";
         required = true;
       };
    };
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
    extensions = with pkgs.nur.repos.rycee; [
      firefox-addons.onepassword-password-manager
      firefox-addons.tridactyl
    ];

  };

  programs.rofi = {
    enable = true;
    terminal = "${pkgs.st}/bin/st";
    theme = ./config/theme.rasi;
    font = "System San Francisco Display Regular 36";
    extraConfig = {
	  show = "run";
	  blur-background = "true";
	  modi ="window,ssh,run";
    };
  };

}
