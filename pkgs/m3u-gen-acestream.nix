{ lib, fetchFromGitHub, buildGoModule }:

buildGoModule rec {
  pname = "m3u-gen-acestream";
  version = "2.2.2";

  src = fetchFromGitHub {
    owner = "SCP002";
    repo = "m3u_gen_acestream";
    rev = "v${version}";
    hash = "sha256-CXrNhSzst6Ecv0nU63lc2es8CLPGWrweimPTV88MwnY=";
  };

  modRoot = "src";
  vendorHash = "sha256-DRAnEl/lk9dVdvYxUfwGmokLP59QFdqgJWBzgceceSA=";

  meta = with lib; {
    description = "M3U playlist generator for Ace Stream";
    homepage = "https://github.com/SCP002/m3u_gen_acestream";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
  };
}