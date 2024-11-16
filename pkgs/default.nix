final: prev: {

    cbt = final.callPackage ./cbt.nix {};
    #obsidian = final.callPackage ./obsidian.nix {};

    openfoam = let 
      openfoam = final.callPackage ./openfoam-com/generic.nix {
        version = "2406";
        inherit openfoam;
      };
    in openfoam;

    st-clipboard = final.fetchurl {
        url = https://st.suckless.org/patches/clipboard/st-clipboard-0.8.3.diff;
        sha256 = "1h1nwilwws02h2lnxzmrzr69lyh6pwsym21hvalp9kmbacwy6p0g";
    };

}
