{ config, pkgs, ... }:

{  users.users.ogle = {
    name = "ogle";
    group = "users";
    extraGroups = [ "wheel" "vboxusers" "docker" "libvirtd" ];
    createHome = true;
    home = "/home/ogle";
    uid = 1000;
    isNormalUser = true;
  };

}
