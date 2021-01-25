{ config, pkgs, ... }:

{
    nix = {

      binaryCaches = [
        "s3://sc-nix-store?endpoint=storage.googleapis.com&scheme=https"
      ];
      binaryCachePublicKeys = [
        "standard-gcs-nix-store-1:3XzQAbVHz1oBbZR9MCxt1TVrQcHGKBaRPSiOchJRVYA="
      ];

	  distributedBuilds = true;
      buildMachines = [
		{
		  hostName = "aarch64.nixos.community";
		  maxJobs = 64;
		  sshKey = "/root/.ssh/aarch-build-box";
		  sshUser = "blogle";
		  system = "aarch64-linux";
		  supportedFeatures = [ "big-parallel" ];
		}
      ];

      extraOptions = ''
        builders-use-substitutes = true
      '';
    };

    programs.ssh.knownHosts."aarch64.nixos.community".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMUTz5i9u5H2FHNAmZJyoJfIGyUm/HfGhfwnc142L3ds";

}
