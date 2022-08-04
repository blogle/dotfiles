final: prev: {

    cog = final.callPackage ./cog.nix {};

    nvidia-docker = final.mkNvidiaContainerPkg {
      name = "nvidia-docker";
      containerRuntimePath = "${final.docker}/libexec/docker/runc";
      configTemplate = builtins.toFile "config.toml" ''
		disable-require = false
		#swarm-resource = "DOCKER_RESOURCE_GPU"

		[nvidia-container-cli]
		#root = "/run/nvidia/driver"
		#path = "/usr/bin/nvidia-container-cli"
		environment = []
		debug = "/var/log/nvidia-container-runtime-hook.log"
		ldcache = "/tmp/ld.so.cache"
		load-kmods = true
		no-cgroups = true
		user = "root:root"
		ldconfig = "@@glibcbin@/bin/ldconfig"
      '';
        additionalPaths = [ (final.callPackage "${final.path}/pkgs/applications/virtualization/nvidia-docker" { }) ];
    };

    obsidian = final.callPackage ./obsidian.nix {};

    st-clipboard = final.fetchurl {
        url = https://st.suckless.org/patches/clipboard/st-clipboard-0.8.3.diff;
        sha256 = "1h1nwilwws02h2lnxzmrzr69lyh6pwsym21hvalp9kmbacwy6p0g";
    };

}
