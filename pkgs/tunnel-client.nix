{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "tunnel-client";
  version = "0.0.10";

  src = fetchFromGitHub {
    owner = "openai";
    repo = "tunnel-client";
    rev = "v${version}";
    hash = "sha256-MYu+ERBGfpZZnrKUFd643K4GyRMoqGpnaKv0TqQxRcQ=";
  };

  vendorHash = "sha256-6T12SRmoXe28XLBPgh3/rppjvi4Xeqi89znXcByHfWY=";
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
