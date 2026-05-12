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
    in {
      apps = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          vaultMcp = shmulsidian.packages.${system}.vault-mcp;

          vault-import = pkgs.writeShellApplication {
            name = "vault-import";
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
            name = "vault-export";
            runtimeInputs = [ pkgs.rsync pkgs.coreutils ];
            text = ''
              set -euo pipefail
              : "''${PERSONAL_VAULT_PATH:?PERSONAL_VAULT_PATH not set}"
              GROUP_VAULT="$(pwd)"
              echo "export $GROUP_VAULT → $PERSONAL_VAULT_PATH"
              # TODO: sync group vault content (project + notes) back into personal vault
              exit 1
            '';
          };

          # `nix run .#init -- <project-name> [--providers claude-code,codex,copilot]`
          # Registers the Python vault MCP locally under "<project>-shmulsidian-mcp"
          # and links the global commands into project-local provider directories.
          project-init = pkgs.writeShellApplication {
            name = "project-init";
            runtimeInputs = [ pkgs.coreutils pkgs.jq ];
            text = ''
              set -euo pipefail

              PROJECT="''${1:-}"; shift || true
              if [[ -z "$PROJECT" ]]; then
                echo "usage: project-init <project-name> [--providers claude-code,codex,copilot]" >&2
                exit 2
              fi

              PROVIDERS="claude-code"
              while [[ $# -gt 0 ]]; do
                case "$1" in
                  --providers) PROVIDERS="$2"; shift 2 ;;
                  *) echo "unknown arg: $1" >&2; exit 2 ;;
                esac
              done

              MCP_NAME="''${PROJECT}-shmulsidian-mcp"
              MCP_BIN="${vaultMcp}/bin/shmulsidian-mcp"
              VAULT_PATH="$(pwd)"

              echo "wiring $MCP_NAME → $MCP_BIN (providers: $PROVIDERS)"

              IFS=',' read -ra PROVIDER_LIST <<< "$PROVIDERS"
              for provider in "''${PROVIDER_LIST[@]}"; do
                case "$provider" in
                  claude-code)
                    mkdir -p .claude
                    settings=".claude/settings.json"
                    [[ -f "$settings" ]] || echo '{}' > "$settings"
                    tmp="$(mktemp)"
                    jq --arg name "$MCP_NAME" --arg bin "$MCP_BIN" \
                       --arg proj "$PROJECT" --arg vault "$VAULT_PATH" \
                       '.mcpServers[$name] = {command:$bin, args:["--project-name",$proj,"--vault-path",$vault]}' \
                       "$settings" > "$tmp" && mv "$tmp" "$settings"
                    ;;
                  codex)
                    mkdir -p .codex
                    cat > ".codex/mcp.$MCP_NAME.toml" <<EOF
                    [mcp_servers.$MCP_NAME]
                    command = "$MCP_BIN"
                    args = ["--project-name", "$PROJECT", "--vault-path", "$VAULT_PATH"]
                    EOF
                    ;;
                  copilot)
                    mkdir -p .vscode
                    settings=".vscode/settings.json"
                    [[ -f "$settings" ]] || echo '{}' > "$settings"
                    tmp="$(mktemp)"
                    jq --arg name "$MCP_NAME" --arg bin "$MCP_BIN" \
                       --arg proj "$PROJECT" --arg vault "$VAULT_PATH" \
                       '.["github.copilot.chat.mcp.servers"][$name] = {command:$bin, args:["--project-name",$proj,"--vault-path",$vault]}' \
                       "$settings" > "$tmp" && mv "$tmp" "$settings"
                    ;;
                  *) echo "unknown provider: $provider" >&2; exit 2 ;;
                esac
                echo "  ✓ $provider"
              done

              echo "done — $MCP_NAME registered locally"
            '';
          };
        in {
          vault-import = { type = "app"; program = "${vault-import}/bin/vault-import"; };
          vault-export = { type = "app"; program = "${vault-export}/bin/vault-export"; };
          init         = { type = "app"; program = "${project-init}/bin/project-init"; };
        }
      );
    };
}
