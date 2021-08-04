{ buildGoModule }:
buildGoModule rec {
  pname = "cog";
  version = "v1.1.3";
  src = builtins.fetchGit {
    url = "ssh://git@github.com/Standard-Cognition/${pname}.git";
    rev = "dddfde87876f607cb35183acdb26a5b28a2b4e15";
  };

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

  modSha256 = "18rcsi5rrkw9bhcm5acjyawr4xc0hmidsvalcsk9fgfksbnssj0g";
  subPackages = [ "." ];
}
