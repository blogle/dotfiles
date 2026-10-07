{ self, system }:
let
  pkgs = self.legacyPackages.${system};
  deployChecks = self.checks.${system};
in
{
  schemaVersion = 1;
  stages = {
    pr-fast = {
      flake-evaluation =
        let
          evaluatedTargets = [
            self.nixosConfigurations.modulus.config.system.build.toplevel.drvPath
            self.nixosConfigurations.nandstorm.config.system.build.toplevel.drvPath
            self.homeConfigurations.home.activationPackage.drvPath
          ];
        in
        builtins.deepSeq evaluatedTargets (pkgs.runCommand "dotfiles-flake-evaluation" { } "touch $out");
    } // {
      deploy-schema = deployChecks.deploy-schema;
    };

    candidate = {
      home-activation = self.homeConfigurations.home.activationPackage;
      modulus-toplevel = self.nixosConfigurations.modulus.config.system.build.toplevel;
      nandstorm-toplevel = self.nixosConfigurations.nandstorm.config.system.build.toplevel;
      deploy-activate = deployChecks.deploy-activate;
    };
  };
}
