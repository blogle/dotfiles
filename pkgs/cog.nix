{ buildGoModule }:

buildGoModule rec {
  pname = "cog";
  version = "v1.2.3";
  src = builtins.fetchGit {
    url = "ssh://git@github.com/standard-ai/${pname}.git";
    rev = "03951df6e885cc20d89d4f1c5be5e3c11e802206";
  };

  modRoot = "src";

  # SC Specific environment variables
  default_vaultAddress="https://vault-iap.nonstandard.ai";
  default_vaultProxyHost="cog-vault-proxy.nonstandard.ai";
  default_vaultIAPServiceAccount="vault-iap-access@standard-users-auth-d8e2dc.iam.gserviceaccount.com";
  default_vaultIAPClientID="621725766798-e7c00l998jkc7imo9ha3jhl0tk12oj33.apps.googleusercontent.com";
  default_gcsBucket="sc-inventory";
  default_gcsFilename="inventory.yml";
  default_binaryGCSBucket="sc-binaries";
  default_binaryGCSPath="SRE";

  ldFlags = [
      "-X main.buildInstallMethod=nix"
      "-X main.buildDate=0"
      "-X main.buildHash=${src.rev}"
      "-X main.buildVersion=${version}"
      "-X main.buildOS=linux"
      "-X main.buildArch=x86_64-linux"

      "-X main.default_vaultAddress=${default_vaultAddress}"
      "-X main.default_vaultProxyHost=${default_vaultProxyHost}"
      "-X main.default_vaultIAPServiceAccount=${default_vaultIAPServiceAccount}"
      "-X main.default_vaultIAPClientID=${default_vaultIAPClientID}"
      "-X main.default_gcsBucket=${default_gcsBucket}"
      "-X main.default_gcsFilename=${default_gcsFilename}"
      "-X main.default_binaryGCSBucket=${default_binaryGCSBucket}"
      "-X main.default_binaryGCSPath=${default_binaryGCSPath}"
  ];

  vendorSha256 = "l7qiIvpuQLCgTKEz6bV75lhVKIulUPtC8ZH+8Ew+wlE=";
  subPackages = [ "." ];
}
