self: super:

{

  cog = super.callPackage ./pkgs/cog.nix {};
  linuxPackages = super.linuxPackages_5_8;

}
