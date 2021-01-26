{ config, pkgs, ... }:

let
  homeDir = "/home/ogle";#builtins.getEnv "HOME";
  #pkgsUnstable = import <nixpkgs-unstable> {};

  _1password = pkgs._1password.overrideAttrs (attrs: {
    src = pkgs.fetchzip {
      url = "https://cache.agilebits.com/dist/1P/op/pkg/v${attrs.version}/op_linux_amd64_v${attrs.version}.zip";
      sha256 = "0qj5v8psqyp0sra0pvzkwjpm28kx3bgg36y37wklb6zl2ngpxm5g";
	  stripRoot = false;
	};
  });

  cog = pkgs.callPackage ./cog.nix {};

  clipboard = pkgs.fetchurl { 
    url = https://st.suckless.org/patches/clipboard/st-clipboard-0.8.3.diff; 
    sha256 = "1h1nwilwws02h2lnxzmrzr69lyh6pwsym21hvalp9kmbacwy6p0g";
  };

  firefox-nogpu = pkgs.writeShellScriptBin "firefox-nogpu" ''
    CUDA_VISIBLE_DEVICES="" firefox
  '';

  st-xresources = pkgs.fetchurl {
    url = https://st.suckless.org/patches/xresources/st-xresources-20180309-c5ba9c0.diff;
    sha256 = "1qgck68sf4s47dckvl9akjikjfqhvrv70bip0l3cy2mb1wdlln6d";
  };

  st = pkgs.st.override {
    conf = builtins.readFile "${homeDir}/.config/st-config.h";
    patches = [ clipboard ];
  };

  vim-build = pkgs.vim_configurable.override {
    python = python;
  };

  vim = vim-build.customize {
    name = "vim";
    vimrcConfig.customRC = pkgs.lib.readFile /home/ogle/.vimrc;
    vimrcConfig.packages.myVimPackage = with pkgs.vimPlugins; {
      start = [];
      opt = [];
    };
  };

  obsidian = 
  let version = "0.6.4"; 
  in pkgs.appimageTools.wrapType2 {
    name = "obsidian";
	src = pkgs.fetchurl {
	  url = "https://github.com/obsidianmd/obsidian-releases/releases/download/v${version}/Obsidian-${version}.AppImage";
	  sha256 = "14yawv9k1j4lly9c5hricvzn9inzx23q38vsymgwwy6qhkpkrjcb";
    };

    extraPkgs = pkgs: [ pkgs.hicolor-icon-theme pkgs.wrapGAppsHook ];

    profile = let 
      gtk = pkgs.gnome3.gtk3;
      gdesktop-schemas = pkgs.gnome3.gsettings-desktop-schemas;
    in ''
	  export LC_ALL=C.UTF-8
	  export XDG_DATA_DIRS=${gdesktop-schemas}/share/gsettings-schemas/${gdesktop-schemas.name}:${gtk}/share/gsettings-schemas/${gtk.name}:$XDG_DATA_DIRS
	'';
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
    #pkgs.arcanist
    #pkgs.ansible
    #pkgs.google-cloud-sdk
    #pkgs.google-chrome
    pkgs.bind
    #pkgs.berglas
    #pkgs.dive
    pkgs.docker
    pkgs.docker-compose
    #pkgs.flameshot
    pkgs.git
    pkgs.git-lfs
    pkgs.gnumake
    pkgs.htop
    pkgs.jq
    pkgs.niv
    pkgs.nmap
    #pkgs.paprefs
    pkgs.pavucontrol
    pkgs.polybar
    #pkgs.php
    pkgs.pywal
    pkgs.ripgrep
    pkgs.rls
    #pkgs.slack
    pkgs.socat
    pkgs.spotify
    #pkgs.terraform
    #pkgs.tmate
    pkgs.tmux
    #pkgs.tree
    pkgs.vlc
    pkgs.wget
    pkgs.xdg_utils
    pkgs.xorg.xbacklight
    pkgs.zoom-us
    pkgs.zotero
    _1password
    #cog
    firefox-nogpu
    obsidian
    st
    python
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
      config = "${homeDir}/.config/xmonad/xmonad.hs";
      extraPackages = 
      haskellPackages: [
        haskellPackages.xmonad-contrib
      ];
    };

    initExtra = let
      config = homeDir + "/xkb/symbols/qgmlwy.xkb";
    in ''
      ${pkgs.xorg.xkbcomp}/bin/xkbcomp ${config} $DISPLAY'';
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
      auth = "eval $(${_1password}/bin/op signin)";
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


  programs.firefox = { enable = true; };
  programs.rofi = {
    enable = true;
    terminal = "${pkgs.st}/bin/st";
    theme = "${homeDir}/.config/rofi/theme.rasi";
    font = "System San Francisco Display Regular 36";
    extraConfig = ''
	  rofi.show: run
	  rofi.blur-background : true
	  rofi.modi: window,ssh,run
    '';
  };

}
