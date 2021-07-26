{ config, pkgs, ... }: 
{
  
  environment.systemPackages = [ 
    pkgs.cudatoolkit
    pkgs.linuxPackages.nvidia_x11
  ];

  hardware.opengl.driSupport32Bit = true;
}
