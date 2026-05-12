{
  description = "shmulistan — Obsidian vault template, utilities, and Home Manager module";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in {
      # `nix flake init -t github:shmul95/shmulistan-template` scaffolds a fresh vault
      # from ./template (PARA dirs + READMEs + MEMORY.md). One-shot copy — user owns the result.
      templates.default = {
        path = ./template;
        description = "shmulistan personal vault starter (PARA + Zettelkasten + MEMORY.md)";
        welcomeText = ''
          Vault scaffold copied.

          Next:
            1. Enable the Home Manager module to get the CLI tools and MCP wiring.
            2. Open this directory as an Obsidian vault.
        '';
      };
      templates.shmulistan = self.templates.default;

      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          wrapScript = { name, src, deps ? [] }:
            pkgs.stdenvNoCC.mkDerivation {
              pname = "shmulistan-${name}";
              version = "0.1.0";
              inherit src;
              nativeBuildInputs = [ pkgs.makeWrapper ];
              dontUnpack = true;
              installPhase = ''
                mkdir -p $out/bin
                cp $src $out/bin/shmulistan-${name}
                chmod +x $out/bin/shmulistan-${name}
              '' + pkgs.lib.optionalString (deps != []) ''
                wrapProgram $out/bin/shmulistan-${name} \
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
        in {
          default = pkgs.symlinkJoin {
            name = "shmulistan-scripts";
            paths = map wrapScript scripts;
          };
        }
      );

      homeManagerModules.default = import ./home-manager.nix { shmulistan = self; };
    };
}
