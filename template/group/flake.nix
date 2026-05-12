{
  description = "shmulsidian group vault — per-project knowledge base wired to a personal vault";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    shmulsidian.url = "github:shmul95/shmulsidian";
    shmulsidian.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, shmulsidian }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      projectName = "CHANGE_ME";
    in {
      apps = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          vault-import = pkgs.writeShellApplication {
            name = "${projectName}-vault-import";
            runtimeInputs = [ pkgs.rsync pkgs.coreutils ];
            text = ''
              set -euo pipefail
              : "''${PERSONAL_VAULT_PATH:?PERSONAL_VAULT_PATH not set — enable programs.shmulsidian}"
              GROUP_VAULT="$(pwd)"

              MODE=""; FILTER=""
              while [[ $# -gt 0 ]]; do
                case "$1" in
                  --tag)     MODE="tag";     FILTER="$2"; shift 2 ;;
                  --project) MODE="project"; FILTER="$2"; shift 2 ;;
                  *) echo "usage: vault-import (--tag <name> | --project <name>)" >&2; exit 2 ;;
                esac
              done
              [[ -z "$MODE" ]] && { echo "must pass --tag or --project" >&2; exit 2; }

              echo "import [$MODE=$FILTER] from $PERSONAL_VAULT_PATH → $GROUP_VAULT"
              # TODO: implement tag/project filtering and rsync into group vault
              exit 1
            '';
          };

          vault-export = pkgs.writeShellApplication {
            name = "${projectName}-vault-export";
            runtimeInputs = [ pkgs.rsync pkgs.coreutils ];
            text = ''
              set -euo pipefail
              : "''${PERSONAL_VAULT_PATH:?PERSONAL_VAULT_PATH not set}"
              GROUP_VAULT="$(pwd)"
              echo "export $GROUP_VAULT → $PERSONAL_VAULT_PATH/02_Projects/${projectName}"
              # TODO: sync group vault content (project + notes) back into personal vault
              exit 1
            '';
          };

          project-init = pkgs.writeShellApplication {
            name = "${projectName}-init";
            runtimeInputs = [ pkgs.coreutils pkgs.jq ];
            text = ''
              set -euo pipefail
              # Wires the group vault's MCP + commands into the local project under
              # the name "${projectName}-shmulsidian-*" so they don't collide with
              # the global shmulsidian-mcp registered by programs.shmulsidian.
              mkdir -p .claude
              # TODO: write .claude/settings.json with mcpServers."${projectName}-shmulsidian-mcp"
              echo "initialised ${projectName} (stub)"
            '';
          };
        in {
          vault-import = { type = "app"; program = "${vault-import}/bin/${projectName}-vault-import"; };
          vault-export = { type = "app"; program = "${vault-export}/bin/${projectName}-vault-export"; };
          init         = { type = "app"; program = "${project-init}/bin/${projectName}-init"; };
        }
      );
    };
}
