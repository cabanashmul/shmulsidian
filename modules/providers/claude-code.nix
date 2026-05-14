# Provider adapter: claude-code (Anthropic CLI).
#
# Writes:
#   ~/.claude/commands/<name>.md   (slash commands, via home.file symlink)
#   ~/.claude.json                 (mcpServers key, via home.activation merge)
#
# Claude Code stores user-level MCP servers in ~/.claude.json under
# .mcpServers.<name>. Per-project MCPs live under .projects.<path>.mcpServers.
# The ~/.claude/mcp-servers/ directory and ~/.claude/settings.json mcpServers
# are NOT used for MCP discovery.
# We use a home.activation script that jq-merges only the shmulsidian key so
# Claude Code can still manage the rest of ~/.claude.json freely.
{ lib, pkgs, config, shmulsidianRoot, vaultMcp, mcpEnabled }:

let
  mcpEntry = builtins.toJSON {
    command = "${vaultMcp}/bin/shmulsidian-mcp";
    args = [ ];
    env.PERSONAL_VAULT_PATH = config.programs.shmulsidian.personalVaultPath;
    type = "stdio";
  };

  mergeScript = pkgs.writeShellScript "claude-code-merge-mcp" ''
    set -euo pipefail
    DOTFILE="$HOME/.claude.json"

    # Bootstrap if missing or empty
    if [ ! -s "$DOTFILE" ]; then
      echo '{}' > "$DOTFILE"
    fi

    # Merge: add/replace only the shmulsidian key under mcpServers
    ${pkgs.jq}/bin/jq --argjson entry '${mcpEntry}' \
      '.mcpServers.shmulsidian = $entry' \
      "$DOTFILE" > "$DOTFILE.tmp" && mv "$DOTFILE.tmp" "$DOTFILE"
  '';
in
{
  # Installs global vault-agnostic commands (inbox-processor, thinking-partner, etc.).
  # Vault-local commands (wiring, etc.) must NOT be added here — they live only in
  # <vault>/.claude/commands/ and are never installed globally.
  home.file.".claude/commands".source = "${shmulsidianRoot}/.claude/commands";

  home.activation.claudeCodeMcpWire = lib.mkIf mcpEnabled (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${mergeScript}
    ''
  );
}
