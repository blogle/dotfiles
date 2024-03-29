# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" "rtsx_pci_sdmmc" ];
  boot.initrd.kernelModules = [ "dm-snapshot" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/4d71dab8-edc2-4d39-8f3f-1108fa0383cf";
      fsType = "ext4";
    };

  fileSystems."/home" =
    { device = "/dev/disk/by-uuid/b8c6e962-fb8a-4dd2-90c7-e198c3c7222a";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/03FE-1545";
      fsType = "vfat";
    };

  swapDevices =
    [ { device = "/dev/disk/by-uuid/b2608a35-429a-4798-a700-c2441bb28656"; }
    ];

  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
}
