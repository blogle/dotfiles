final: prev: {

    cog = final.callPackage ./cog.nix {};

    obsidian = final.callPackage ./obsidian.nix {};

    st-clipboard = final.fetchurl {
        url = https://st.suckless.org/patches/clipboard/st-clipboard-0.8.3.diff;
        sha256 = "1h1nwilwws02h2lnxzmrzr69lyh6pwsym21hvalp9kmbacwy6p0g";
    };

}
