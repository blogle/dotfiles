# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, ... }:

{
  imports =
    [ <nixpkgs/nixos/modules/installer/scan/not-detected.nix>
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/85cdc85c-50f3-4b7b-bc5b-10fcc76a3c4c";
      fsType = "ext4";
    };

  fileSystems."/home" =
    { device = "/dev/disk/by-uuid/410b8f95-0a86-4eef-835e-fe8a5e0f9403";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/53DD-7C8F";
      fsType = "vfat";
    };

  swapDevices =
    [ { device = "/dev/disk/by-uuid/ca46fa77-579e-47d9-a98a-8df6a28bb075"; }
    ];

  nix.maxJobs = lib.mkDefault 12;
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
}
