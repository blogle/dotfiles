{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "tunnel-client";
  version = "0.0.14";

  src = fetchFromGitHub {
    owner = "openai";
    repo = "tunnel-client";
    rev = "v${version}";
    hash = "sha256-RU5g+bx1Hjqxz0fYeznJpA0V+xun97PizHjT0Y843G0=";
  };

  postPatch = ''
    substituteInPlace go.mod --replace-fail 'go 1.27.0' 'go 1.26.0'
    rm -rf vendor
  '';

  vendorHash = "sha256-UxNE6pfnUx5oSxGMNNRVKgyTECQvDlmutq4yWV5bRQI=";
  subPackages = [ "cmd/client" ];

  env.CGO_ENABLED = 0;

  postInstall = ''
    mv "$out/bin/client" "$out/bin/tunnel-client"
  '';

  meta = {
    description = "Official OpenAI client for Secure MCP Tunnel";
    homepage = "https://github.com/openai/tunnel-client";
    license = lib.licenses.asl20;
    mainProgram = "tunnel-client";
  };
}
