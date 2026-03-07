{
  description = "OpenAI Codex Desktop for Linux";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      mkElectronRuntimeDeps =
        p: with p; [
          alsa-lib
          at-spi2-core
          atk
          cairo
          cups
          dbus
          expat
          gdk-pixbuf
          glib
          gtk3
          nss
          nspr
          pango
          pciutils
          stdenv.cc.cc
          systemd
          libnotify
          pipewire
          libsecret
          libpulseaudio
          libdrm
          mesa
          libgbm
          libxkbcommon
          libGL
          vulkan-loader
          libx11
          libxcb
          libxcomposite
          libxdamage
          libxext
          libxfixes
          libxrandr
          libxkbfile
          libxshmfence
        ];

      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # Package derivations — x86_64-linux only
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      lib = pkgs.lib;
      electronRuntimeDeps = mkElectronRuntimeDeps pkgs;
      runtimeLibPath = lib.makeLibraryPath electronRuntimeDeps;

      electron-40-bin = pkgs.stdenv.mkDerivation rec {
        pname = "electron-40-bin";
        version = "40.0.0";

        src = pkgs.fetchurl {
          url = "https://github.com/electron/electron/releases/download/v${version}/electron-v${version}-linux-x64.zip";
          hash = "sha256-KsIt9CpDaM3ZP/n58lx/BLkVcUOjo6BtTwGuDbtOb9U=";
        };

        passthru.headers = pkgs.fetchzip {
          url = "https://artifacts.electronjs.org/headers/dist/v${version}/node-v${version}-headers.tar.gz";
          hash = "sha256-1ATol7BLKZMFzNYYwYpmAYmm44qZaY9lI+eHOMZcV3I=";
        };

        nativeBuildInputs = with pkgs; [ unzip ];

        sourceRoot = ".";
        dontPatchELF = true;
        dontConfigure = true;
        dontBuild = true;

        installPhase = ''
          runHook preInstall

          mkdir -p $out/lib/electron
          cp -r ./* $out/lib/electron/
          chmod -R u+w $out/lib/electron

          local interp="$(< $NIX_CC/nix-support/dynamic-linker)"
          local rpath="${runtimeLibPath}:$out/lib/electron"

          patchelf --set-interpreter "$interp" --set-rpath "$rpath" \
            $out/lib/electron/electron

          [ -f $out/lib/electron/chrome_crashpad_handler ] && \
            patchelf --set-interpreter "$interp" --set-rpath "$rpath" \
              $out/lib/electron/chrome_crashpad_handler || true

          for f in $out/lib/electron/libEGL.so $out/lib/electron/libGLESv2.so; do
            [ -f "$f" ] && patchelf --set-rpath "$rpath" "$f" || true
          done

          if [ -f $out/lib/electron/libvulkan.so.1 ]; then
            rm -f $out/lib/electron/libvulkan.so.1
            ln -s ${pkgs.vulkan-loader}/lib/libvulkan.so.1 \
              $out/lib/electron/libvulkan.so.1
          fi

          runHook postInstall
        '';
      };

      codexDmg = pkgs.fetchurl {
        url = "https://persistent.oaistatic.com/codex-app-prod/Codex.dmg";
        hash = "sha256-4oKdhkRmwUbvnexeguuwfv+oRHhR3WYbUwewB9rpLDc=";
      };

      codex-desktop = pkgs.stdenv.mkDerivation {
        pname = "codex-desktop";
        version = "0.1.0";

        src = ./native-build;

        npmDeps = pkgs.fetchNpmDeps {
          src = ./native-build;
          hash = "sha256-CnQmLBK4MfNtwz6WMsNEh9bAmybL1ujTlKg3EK33984=";
        };

        makeCacheWritable = true;

        nativeBuildInputs = with pkgs; [
          nodejs_22
          python3
          npmHooks.npmConfigHook
          _7zz
          libicns
          makeWrapper
          copyDesktopItems
        ];

        npmInstallFlags = [ "--ignore-scripts" ];
        npmRebuildFlags = [ "--ignore-scripts" ];

        buildInputs = electronRuntimeDeps;

        postConfigure = ''
          export PATH="$PWD/node_modules/.bin:$PATH"
          export npm_config_nodedir=${electron-40-bin.headers}
          electron-rebuild -v ${electron-40-bin.version} --force
        '';

        buildPhase = ''
          runHook preBuild

          7zz x -y ${codexDmg} -o$TMPDIR/dmg-extract
          app_dir=$(find $TMPDIR/dmg-extract -maxdepth 3 -name "*.app" -type d | head -1)

          resources="$app_dir/Contents/Resources"
          asar extract "$resources/app.asar" $TMPDIR/app-extracted
          if [ -d "$resources/app.asar.unpacked" ]; then
            cp -r "$resources/app.asar.unpacked/"* $TMPDIR/app-extracted/ || true
          fi

          rm -rf $TMPDIR/app-extracted/node_modules/sparkle-darwin
          find $TMPDIR/app-extracted -name "sparkle.node" -delete

          rm -rf $TMPDIR/app-extracted/node_modules/better-sqlite3
          rm -rf $TMPDIR/app-extracted/node_modules/node-pty
          cp -r node_modules/better-sqlite3 $TMPDIR/app-extracted/node_modules/
          cp -r node_modules/node-pty $TMPDIR/app-extracted/node_modules/

          asar pack $TMPDIR/app-extracted $TMPDIR/app.asar \
            --unpack "{*.node,*.so,*.dylib}"

          icns2png -x "$app_dir/Contents/Resources/AppIcon.icns" -o $TMPDIR

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p $out/share/codex/resources $out/share/codex/webview
          mkdir -p $out/share/icons/hicolor/512x512/apps
          mkdir -p $out/bin

          cp $TMPDIR/app.asar $out/share/codex/resources/
          [ -d $TMPDIR/app.asar.unpacked ] && \
            cp -r $TMPDIR/app.asar.unpacked $out/share/codex/resources/

          if [ -d $TMPDIR/app-extracted/webview ]; then
            cp -r $TMPDIR/app-extracted/webview/* $out/share/codex/webview/
          fi

          icon=$(ls -S $TMPDIR/AppIcon_*x*.png 2>/dev/null | head -1)
          [ -n "$icon" ] && \
            cp "$icon" $out/share/icons/hicolor/512x512/apps/codex-desktop.png

          cat > $out/bin/codex-desktop << 'LAUNCHER'
#!/usr/bin/env bash
pkill -f "http.server 5175" 2>/dev/null || true
sleep 0.2
cd @webviewDir@
@python3@ -m http.server 5175 >/dev/null 2>&1 &
trap 'kill $! 2>/dev/null' EXIT
export CODEX_CLI_PATH="''${CODEX_CLI_PATH:-$(command -v codex 2>/dev/null)}"
[ -z "$CODEX_CLI_PATH" ] && { echo "Error: codex CLI not found" >&2; exit 1; }
exec @electron@ --no-sandbox @appAsar@ "$@"
LAUNCHER
          chmod +x $out/bin/codex-desktop
          substituteInPlace $out/bin/codex-desktop \
            --replace-fail "@webviewDir@" "$out/share/codex/webview" \
            --replace-fail "@python3@" "${pkgs.python3}/bin/python3" \
            --replace-fail "@electron@" "${electron-40-bin}/lib/electron/electron" \
            --replace-fail "@appAsar@" "$out/share/codex/resources/app.asar"

          runHook postInstall
        '';

        desktopItems = [
          (pkgs.makeDesktopItem {
            name = "codex-desktop";
            desktopName = "Codex";
            exec = "codex-desktop %U";
            icon = "codex-desktop";
            categories = [ "Development" ];
            startupWMClass = "Codex";
          })
        ];
      };
    in
    {
      packages.x86_64-linux.default = codex-desktop;

      devShells = forAllSystems (
        system:
        let
          devPkgs = nixpkgs.legacyPackages.${system};
          devElectronDeps = mkElectronRuntimeDeps devPkgs;
        in
        {
          default = devPkgs.mkShell {
            packages = with devPkgs; [
              nodejs_20
              python3
              _7zz
              curl
              unzip
              gnumake
              gcc
              patchelf
            ];

            buildInputs = devElectronDeps;

            ELECTRON_LIB_PATH = devPkgs.lib.makeLibraryPath devElectronDeps;

            shellHook = ''
              export NIX_DYNAMIC_LINKER="$(< ${devPkgs.stdenv.cc}/nix-support/dynamic-linker)"
            '';
          };
        }
      );
    };
}
