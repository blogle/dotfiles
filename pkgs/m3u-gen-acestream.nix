{ lib, fetchFromGitHub, go, stdenv }:

stdenv.mkDerivation rec {
  pname = "m3u-gen-acestream";
  version = "2.2.2";

  src = fetchFromGitHub {
    owner = "SCP002";
    repo = "m3u_gen_acestream";
    rev = "v${version}";
    hash = "sha256-CXrNhSzst6Ecv0nU63lc2es8CLPGWrweimPTV88MwnY=";
  };

  nativeBuildInputs = [ go ];
  buildInputs = [ ];

  buildPhase = ''
    export GOCACHE=$(pwd)/.cache/go-build
    export GOMODCACHE=$(pwd)/.cache/go-mod
    cd src
    go mod download
    go build -o m3u_gen_acestream m3u_gen_acestream.go
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp src/m3u_gen_acestream $out/bin/
  '';

  meta = with lib; {
    description = "M3U playlist generator for Ace Stream";
    homepage = "https://github.com/SCP002/m3u_gen_acestream";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
  };
}