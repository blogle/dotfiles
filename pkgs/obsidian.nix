{ appimageTools, fetchurl, gnome3, hicolor-icon-theme, wrapGAppsHook }:

let version = "0.6.4";
in appimageTools.wrapType2 {
  name = "obsidian";
  src = fetchurl {
    url = "https://github.com/obsidianmd/obsidian-releases/releases/download/v${version}/Obsidian-${version}.AppImage";
    sha256 = "14yawv9k1j4lly9c5hricvzn9inzx23q38vsymgwwy6qhkpkrjcb";
  };

  extraPkgs = pkgs: [ hicolor-icon-theme wrapGAppsHook ];

  profile = let
    gtk = gnome3.gtk3;
    gdesktop-schemas = gnome3.gsettings-desktop-schemas;
  in ''
    export LC_ALL=C.UTF-8
    export XDG_DATA_DIRS=${gdesktop-schemas}/share/gsettings-schemas/${gdesktop-schemas.name}:${gtk}/share/gsettings-schemas/${gtk.name}:$XDG_DATA_DIRS
  '';
}
