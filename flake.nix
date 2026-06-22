# To update Phosphor:
#   1. Change `version` below to the new tag (e.g. "1.8.0")
#   2. Set `hash` to "" (empty string) and run `nix build .#phosphor`
#   3. Copy the hash Nix prints ("got: sha256-...") into `hash` below
#   4. Commit and push.
#
# `nix flake update` handles nixpkgs + flake-utils; Phosphor is
# manually pinned so you control when the visual engine changes.
{
  description = "Phosphor — real-time particle and shader engine for live performance";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        phosphor = pkgs.stdenv.mkDerivation rec {
          pname = "phosphor";
          version = "1.7.1";

          src = pkgs.fetchurl {
            url = "https://github.com/kevinraymond/phosphor/releases/download/v${version}/phosphor-v${version}-x86_64-unknown-linux-gnu.tar.gz";
            hash = "sha256-atEIzykuo+osoaafIFXFfmMy3ywM1/LrDjiu8iBiG/Q=";
          };

          nativeBuildInputs = [
            pkgs.makeWrapper
            pkgs.autoPatchelfHook
          ];

          buildInputs = [
            pkgs.openssl          # libssl.so.3, libcrypto.so.3
            pkgs.alsa-lib         # libasound.so.2 (cpal audio capture)
            pkgs.vulkan-loader    # libvulkan.so (wgpu rendering)
            pkgs.libx11           # winit windowing
            pkgs.libxcursor
            pkgs.libxrandr
            pkgs.libxi
            pkgs.libxkbcommon     # wayland keyboard
            pkgs.wayland          # wayland client
            pkgs.mesa             # libEGL, libGL (fallback/software)
          ];

          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin $out/share/phosphor
            cp -r * $out/share/phosphor/

            # Assets must be resolvable beside the binary (phosphor's
            # assets_dir() tries exe-relative path first for installed
            # binaries: `<exe_dir>/assets/effects/`).
            ln -s $out/share/phosphor/assets $out/bin/assets

            # Wrap the binary — autoPatchelfHook fixes ELF NEEDED libs,
            # but winit dlopen()s Wayland at runtime, so we extend the
            # library path for those.
            makeWrapper $out/share/phosphor/phosphor $out/bin/phosphor \
              --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath [
                pkgs.wayland
                pkgs.libxkbcommon
                pkgs.mesa
                pkgs.vulkan-loader
              ]}

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Cross-platform real-time particle and shader engine for live performance";
            homepage = "https://github.com/kevinraymond/phosphor";
            license = with licenses; [ asl20 mit ];
            platforms = [ "x86_64-linux" ];
            mainProgram = "phosphor";
          };
        };
      in
      {
        packages = {
          inherit phosphor;
          default = phosphor;
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ phosphor ];
          packages = with pkgs; [
            phosphor        # the visual engine itself
            nil             # Nix language server
            nixpkgs-fmt     # Nix formatter
            ffmpeg          # Video layer support (optional, runtime)
            v4l-utils       # Webcam support (optional, runtime)
          ];

          shellHook = ''
            # Phosphor's assets_dir() checks CWD first. Set up a project-local
            # assets/ that mirrors built-in assets (symlinked from Nix store)
            # and has a writable effects/ + shaders/ for custom work.
            PROJECT_DIR=''${PRJ_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}
            if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR/effects" ]; then
              ASSETS="$PROJECT_DIR/assets"
              NIX_ASSETS="${phosphor}/share/phosphor/assets"
              if [ ! -d "$ASSETS" ]; then
                mkdir -p "$ASSETS/effects" "$ASSETS/shaders"
                for dir in fonts presets icon images web; do
                  ln -sfn "$NIX_ASSETS/$dir" "$ASSETS/$dir" 2>/dev/null
                done
                # Symlink individual shader files from Nix store
                for f in "$NIX_ASSETS/shaders/"*; do
                  ln -sfn "$f" "$ASSETS/shaders/$(basename "$f")" 2>/dev/null
                done
                # Copy built-in .pfx effects
                cp "$NIX_ASSETS/effects/"*.pfx "$ASSETS/effects/" 2>/dev/null
                # Copy project custom effects
                cp "$PROJECT_DIR/effects/"*.wgsl "$ASSETS/shaders/" 2>/dev/null
                cp "$PROJECT_DIR/effects/"*.pfx "$ASSETS/effects/" 2>/dev/null
                if [ -f "$NIX_ASSETS/phosphor-teaser.gif" ]; then
                  ln -sfn "$NIX_ASSETS/phosphor-teaser.gif" "$ASSETS/phosphor-teaser.gif" 2>/dev/null
                fi
                echo "🎨 Phosphor assets set up from Nix store"
              fi
            fi
            echo "🎨 Phosphor devshell — v${phosphor.version}"
            echo "   phosphor          run the visual engine"
            echo "   Config dir:       ~/.config/phosphor/"
            echo "   Custom effects:   effects/ (versioned in repo → auto-linked to assets/)"
            echo "   Presets:          ~/.config/phosphor/presets/"
            echo "   Scenes:           ~/.config/phosphor/scenes/"
          '';
        };

        formatter = pkgs.nixpkgs-fmt;
      });
}
