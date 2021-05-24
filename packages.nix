self: super:

let
in

{

  cog = super.callPackage ./pkgs/cog.nix {};
  screenconfig = self.pythonPackages.screenconfig;
  linuxPackages = super.linuxPackages_5_4;


  python = self.python3;
  pythonPackages = self.python.pkgs;
  python3 = super.python3.override {
    packageOverrides = self: super: {
      screenconfig = super.callPackage ./pkgs/screenconfig.nix {};
    };
  };

}
