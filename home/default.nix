{ config, pkgs, inputs, ... }:

# minimal config, suitable for servers

{
  imports = [
    # shell config
    #./shell
  ];

  programs.home-manager.enable = true;
  home = {
    username = "ogle";
    homeDirectory = "/home/ogle";
    stateVersion = "20.09";
  };

  home.packages = with pkgs; [

    # file managers
    # xplr

    ripgrep # better grep
  ];
  home.extraOutputsToInstall = [ "doc" "info" "devdoc" ];


  programs = {
    #git = {
    #  enable = true;
    #  ignores = [ "*~" "*.swp" "result" ];
    #  signing = {
    #    key = "3AC82B48170331D3";
    #    signByDefault = true;
    #  };
    #  userEmail = "fufexan@pm.me";
    #  userName = "Mihai Fufezan";
    #};

    ssh.enable = true;
  };
}
