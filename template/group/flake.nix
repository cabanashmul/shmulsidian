{
  description = "shmulsidian group vault — per-project knowledge base wired to a personal vault";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    shmulsidian.url = "github:cabanashmul/shmulsidian";
    shmulsidian.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, shmulsidian }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Rename this after `nix flake init` — e.g. "galapsy" → exposes `galapsy-init` app.
      projectName = "CHANGE_ME";

      noPersonalVaultGuard = ''
        if [[ -z "''${PERSONAL_VAULT_PATH:-}" ]]; then
          echo "no personal vault — set PERSONAL_VAULT_PATH or enable programs.shmulsidian" >&2
          exit 1
        fi
      '';
    in {
      apps = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          vaultMcp = shmulsidian.packages.${system}.vault-mcp;
          commandsSrc = "${shmulsidian}/.claude/commands";

          # vault-import / vault-export operate on whatever vault the user is
          # standing in — no project prefix. Both require a personal vault.
          vault-import = pkgs.writeShellApplication {
            name = "vault-import";
            runtimeInputs = [ pkgs.rsync pkgs.coreutils ];
            text = ''
              set -euo pipefail
              ${noPersonalVaultGuard}

              MODE=""; FILTER=""
              while [[ $# -gt 0 ]]; do
                case "$1" in
                  --tag)     MODE="tag";     FILTER="$2"; shift 2 ;;
                  --project) MODE="project"; FILTER="$2"; shift 2 ;;
                  *) echo "usage: vault-import (--tag <name> | --project <name>)" >&2; exit 2 ;;
                esac
              done
              [[ -z "$MODE" ]] && { echo "must pass --tag or --project" >&2; exit 2; }

              echo "import [$MODE=$FILTER] from $PERSONAL_VAULT_PATH → $(pwd)"
              # TODO: implement tag/project filtering and rsync into current vault
              exit 1
            '';
          };

          vault-export = pkgs.writeShellApplication {
            name = "vault-export";
            runtimeInputs = [ pkgs.rsync pkgs.coreutils ];
            text = ''
              set -euo pipefail
              ${noPersonalVaultGuard}

              echo "export $(pwd) → $PERSONAL_VAULT_PATH"
              # TODO: sync current vault content back into personal vault
              exit 1
            '';
          };

          # `nix run .#init -- <relative-path-to-related-repo> [--providers …]`
          # Run from inside the group vault. Installs MCP + commands into the
          # target repo so its AI tool can query this group vault.
          project-init = pkgs.writeShellApplication {
            name = "${projectName}-init";
            runtimeInputs = [ pkgs.coreutils pkgs.jq ];
            text = ''
              set -euo pipefail

              TARGET="''${1:-}"; shift || true
              if [[ -z "$TARGET" ]]; then
                echo "usage: ${projectName}-init <related-repo-path> [--providers claude-code,codex,copilot]" >&2
                exit 2
              fi
              [[ -d "$TARGET" ]] || { echo "target not a directory: $TARGET" >&2; exit 2; }

              PROVIDERS="claude-code"
              while [[ $# -gt 0 ]]; do
                case "$1" in
                  --providers) PROVIDERS="$2"; shift 2 ;;
                  *) echo "unknown arg: $1" >&2; exit 2 ;;
                esac
              done

              MCP_NAME="${projectName}-shmulsidian-mcp"
              MCP_BIN="${vaultMcp}/bin/shmulsidian-mcp"
              GROUP_VAULT="$(pwd)"
              TARGET_ABS="$(cd "$TARGET" && pwd)"

              echo "wire $MCP_NAME → $TARGET_ABS (vault: $GROUP_VAULT, providers: $PROVIDERS)"

              IFS=',' read -ra PROVIDER_LIST <<< "$PROVIDERS"
              for provider in "''${PROVIDER_LIST[@]}"; do
                case "$provider" in
                  claude-code)
                    mkdir -p "$TARGET_ABS/.claude"
                    settings="$TARGET_ABS/.claude/settings.json"
                    [[ -f "$settings" ]] || echo '{}' > "$settings"
                    tmp="$(mktemp)"
                    jq --arg name "$MCP_NAME" --arg bin "$MCP_BIN" \
                       --arg proj "${projectName}" --arg vault "$GROUP_VAULT" \
                       '.mcpServers[$name] = {command:$bin, args:["--project-name",$proj,"--vault-path",$vault]}' \
                       "$settings" > "$tmp" && mv "$tmp" "$settings"
                    cp -rL "${commandsSrc}" "$TARGET_ABS/.claude/commands"
                    ;;
                  codex)
                    mkdir -p "$TARGET_ABS/.codex"
                    cat > "$TARGET_ABS/.codex/mcp.$MCP_NAME.toml" <<EOF
                    [mcp_servers.$MCP_NAME]
                    command = "$MCP_BIN"
                    args = ["--project-name", "${projectName}", "--vault-path", "$GROUP_VAULT"]
                    EOF
                    cp -rL "${commandsSrc}" "$TARGET_ABS/.codex/prompts"
                    ;;
                  copilot)
                    mkdir -p "$TARGET_ABS/.vscode"
                    settings="$TARGET_ABS/.vscode/settings.json"
                    [[ -f "$settings" ]] || echo '{}' > "$settings"
                    tmp="$(mktemp)"
                    jq --arg name "$MCP_NAME" --arg bin "$MCP_BIN" \
                       --arg proj "${projectName}" --arg vault "$GROUP_VAULT" \
                       '.["github.copilot.chat.mcp.servers"][$name] = {command:$bin, args:["--project-name",$proj,"--vault-path",$vault]}' \
                       "$settings" > "$tmp" && mv "$tmp" "$settings"
                    ;;
                  *) echo "unknown provider: $provider" >&2; exit 2 ;;
                esac
                echo "  ✓ $provider"
              done

              echo "done — $TARGET_ABS can now query the $projectName vault via $MCP_NAME"
            '';
          };
        in {
          vault-import = { type = "app"; program = "${vault-import}/bin/vault-import"; };
          vault-export = { type = "app"; program = "${vault-export}/bin/vault-export"; };
          init         = { type = "app"; program = "${project-init}/bin/${projectName}-init"; };
        }
      );
    };
}
