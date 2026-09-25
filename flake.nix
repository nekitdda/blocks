{
  description = "YouMuz - a Yandex Music client";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      version = "2.5.2";
      # URL: https://github.com/DarkPlayOff/YouMuz/releases/download/v${version}/youmuz-linux-x64-${version}.tar.gz
      # Bump `version` and re-run `nix flake lock --update-input nixpkgs` + `nix store prefetch-file <url>`
      # to get the new sha256.
      srcHash = "sha256-vuozwtQsRJdCmg3WIiZn/Gt7GnvQwYbGToWzhunbAwM=";
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };

          youmuz = pkgs.stdenv.mkDerivation {
            pname = "youmuz";
            inherit version;

            src = pkgs.fetchurl {
              url = "https://github.com/DarkPlayOff/YouMuz/releases/download/v${version}/youmuz-linux-x64-${version}.tar.gz";
              sha256 = srcHash;
            };

            # Flutter bundles contain several top-level directories (data, lib, ...).
            sourceRoot = ".";

            postUnpack = ''
              addAutoPatchelfSearchPath "${pkgs.jdk}/lib/openjdk/lib/server"
            '';

            dontConfigure = true;
            dontBuild = true;

            nativeBuildInputs = [
              pkgs.autoPatchelfHook
              pkgs.wrapGAppsHook3
            ];

            buildInputs = [
              pkgs.alsa-lib
              pkgs.dbus
              pkgs.gdk-pixbuf
              pkgs.glib-networking
              pkgs.gsettings-desktop-schemas
              pkgs.gtk3
              pkgs.jdk
              pkgs.keybinder3
              pkgs.libayatana-appindicator
              pkgs.libayatana-indicator
              pkgs.libsecret
              pkgs.libsoup_3
              pkgs.shared-mime-info
              pkgs.webkitgtk_4_1
              pkgs.stdenv.cc.cc.lib
            ];

            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin $out/share/applications $out/share/icons/hicolor/scalable/apps
              cp -r . $out/bin/
              install -Dm644 ${./packaging/linux/io.github.darkplayoff.youmuz.desktop} $out/share/applications/io.github.darkplayoff.youmuz.desktop
              install -Dm644 ${./src/assets/icons/logo.svg} $out/share/icons/hicolor/scalable/apps/io.github.darkplayoff.youmuz.svg
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "YouMuz - a Yandex Music client";
              homepage = "https://github.com/DarkPlayOff/YouMuz";
              license = licenses.gpl3Plus;
              mainProgram = "youmuz";
              platforms = [ "x86_64-linux" ];
            };
          };
        in
        {
          youmuz = youmuz;
          default = youmuz;
        });

      apps = forAllSystems (system:
        let
          youmuz = self.packages.${system}.youmuz;
        in
        {
          default = {
            type = "app";
            program = "${youmuz}/bin/youmuz";
          };
        });
    };
}
