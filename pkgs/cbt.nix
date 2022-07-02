{ buildGoModule, fetchurl }:

buildGoModule rec {
  pname = "cbt";
  version = "v0.12.0";
  src = fetchurl {
    url = "https://github.com/googleapis/cloud-bigtable-cbt-cli/archive/refs/tags/v.0.12.0.tar.gz";
    #sha256 = "l7qiIvpuQLCgTKEz6bV75lhVKIulUPtC8ZH+8Ew+wlfe";
    sha256 = "sha256-iE+XbrC1ftAiMLFttGIryx67Eo9XUPd8vOkmJZ8GVV4=";
  };

  vendorSha256 = "sha256-kwvEfvHs6XF84bB3Ss1307OjId0nh/0Imih1fRFdY0M=";
  subPackages = [ "." ];
}
