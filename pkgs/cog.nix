{ buildGoModule }:

buildGoModule rec {
  pname = "cog";
  version = "v1.2.3";
  src = builtins.fetchGit {
    url = "ssh://git@github.com/standard-ai/${pname}.git";
    rev = "03951df6e885cc20d89d4f1c5be5e3c11e802206";
  };

  modRoot = "src";

  buildFlagsArray = 
  ''
      -ldflags=
      -X main.buildInstallMethod=nix
      -X main.buildDate=0
      -X main.buildHash=${src.rev}
      -X main.buildVersion=${version}
      -X main.buildOS=linux
      -X main.buildArch=x86_64-linux
  '';

  vendorSha256 = "l7qiIvpuQLCgTKEz6bV75lhVKIulUPtC8ZH+8Ew+wlE=";
  subPackages = [ "." ];
}
