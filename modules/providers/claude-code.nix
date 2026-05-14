# Provider adapter: claude-code (Anthropic CLI).
#
# Writes:
#   ~/.claude/commands/<name>.md   (slash commands, via home.file symlink)
#   ~/.claude/settings.json        (mcpServers key, via home.activation merge)
#
# Claude Code reads MCP servers exclusively from the `mcpServers` key in
# settings.json — the ~/.claude/mcp-servers/ directory is NOT auto-discovered.
# We use a home.activation script that does a safe JSON merge so Claude Code
# can still write other keys to that file without conflicts.
{ lib, pkgs, config, shmulsidianRoot, vaultMcp, mcpEnabled }:

let
  mcpEntry = builtins.toJSON {
    command = "${vaultMcp}/bin/shmulsidian-mcp";
    args = [ ];
    env.PERSONAL_VAULT_PATH = config.programs.shmulsidian.personalVaultPath;
  };

  mergeScript = pkgs.writeShellScript "claude-code-merge-mcp" ''
    set -euo pipefail
    SETTINGS="$HOME/.claude/settings.json"

    # Bootstrap if missing or empty
    if [ ! -s "$SETTINGS" ]; then
      echo '{}' > "$SETTINGS"
    fi

    # Merge: add/replace only the shmulsidian key under mcpServers
    ${pkgs.jq}/bin/jq --argjson entry '${mcpEntry}' \
      '.mcpServers.shmulsidian = $entry' \
      "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  '';
in
{
  home.file.".claude/commands".source = "${shmulsidianRoot}/.claude/commands";

  home.activation.claudeCodeMcpWire = lib.mkIf mcpEnabled (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${mergeScript}
    ''
  );
}
