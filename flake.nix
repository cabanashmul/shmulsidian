{
  description = "shmulsidian — Obsidian vault template, utilities, vault MCP, and Home Manager module";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in {
      # One-shot scaffolds — `nix flake init -t github:shmul95/shmulsidian[#group]`.
      templates = {
        default  = self.templates.personal;
        personal = {
          path = ./template/personal;
          description = "shmulsidian personal vault (PARA + Zettelkasten + MEMORY.md)";
        };
        group = {
          path = ./template/group;
          description = "shmulsidian group/project vault wired to a personal vault";
        };
      };

      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          wrapScript = { name, src, deps ? [] }:
            pkgs.stdenvNoCC.mkDerivation {
              pname = "shmulsidian-${name}";
              version = "0.1.0";
              inherit src;
              nativeBuildInputs = [ pkgs.makeWrapper ];
              dontUnpack = true;
              installPhase = ''
                mkdir -p $out/bin
                cp $src $out/bin/shmulsidian-${name}
                chmod +x $out/bin/shmulsidian-${name}
              '' + pkgs.lib.optionalString (deps != []) ''
                wrapProgram $out/bin/shmulsidian-${name} \
                  --prefix PATH : ${pkgs.lib.makeBinPath deps}
              '';
            };

          scripts = [
            { name = "firecrawl-scrape";        src = ./.scripts/firecrawl-scrape.sh;        deps = [ pkgs.curl pkgs.jq ]; }
            { name = "firecrawl-batch";         src = ./.scripts/firecrawl-batch.sh;         deps = [ pkgs.curl pkgs.jq ]; }
            { name = "transcript-extract";      src = ./.scripts/transcript-extract.sh;      deps = [ pkgs.yt-dlp pkgs.jq ]; }
            { name = "update-attachment-links"; src = ./.scripts/update-attachment-links.js; deps = [ pkgs.nodejs ]; }
            { name = "fix-renamed-links";       src = ./.scripts/fix-renamed-links.js;       deps = [ pkgs.nodejs ]; }
          ];

          # `nix run github:shmul95/shmulsidian#setup` — usable directly or wrapped
          # by a downstream flake (e.g. cabanashmul#setup).
          setup = pkgs.writeShellApplication {
            name = "shmulsidian-setup";
            runtimeInputs = [ pkgs.nix ];
            text = ''
              set -euo pipefail
              TEMPLATE="''${1:-personal}"
              case "$TEMPLATE" in personal|group) ;; *)
                echo "usage: shmulsidian-setup [personal|group]" >&2; exit 2 ;;
              esac
              nix flake init -t "github:shmul95/shmulsidian#$TEMPLATE"
            '';
          };
        in {
          default = pkgs.symlinkJoin {
            name = "shmulsidian-scripts";
            paths = map wrapScript scripts;
          };

          # TODO(v1.0): real vault MCP server (doc creation, semantic + keyword
          # embedding search). This stub keeps the wiring testable end-to-end.
          vault-mcp = pkgs.writeShellApplication {
            name = "shmulsidian-mcp";
            text = ''
              echo "shmulsidian-mcp stub — implement vault MCP here" >&2
              exit 1
            '';
          };

          inherit setup;
        }
      );

      homeManagerModules.default = import ./home-manager.nix { shmulsidian = self; };
    };
}
