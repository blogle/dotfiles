{ lib, fetchFromGitHub, buildGoModule }:

buildGoModule rec {
  pname = "m3u-gen-acestream";
  version = "2.2.2";

  src = fetchFromGitHub {
    owner = "SCP002";
    repo = "m3u_gen_acestream";
    rev = "v${version}";
    hash = "sha256-rS1njbOKx/7GFqm09O1YxLnc6LgB6+Qgc6l4gv6f1qM=";
  };

  goModulesPath = "src";
  vendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  # disableCheck = true;

  meta = with lib; {
    description = "M3U playlist generator for Ace Stream";
    homepage = "https://github.com/SCP002/m3u_gen_acestream";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
  };
}