# Provider adapter: claude-code (Anthropic CLI).
#
# Reads slash commands from $shmulsidianRoot/.claude/commands and the vault MCP
# binary from $vaultMcp, and writes:
#   ~/.claude/commands/<name>.md           (slash commands)
#   ~/.claude/mcp-servers/shmulsidian.json (MCP entry)
{ lib, pkgs, config, shmulsidianRoot, vaultMcp, mcpEnabled }:

{
  home.file = lib.mkMerge [
    (lib.mkIf mcpEnabled {
      ".claude/mcp-servers/shmulsidian.json".text = builtins.toJSON {
        name = "shmulsidian";
        command = "${vaultMcp}/bin/shmulsidian-mcp";
        args = [ ];
        env.PERSONAL_VAULT_PATH = config.programs.shmulsidian.personalVaultPath;
      };
    })
    {
      ".claude/commands".source = "${shmulsidianRoot}/.claude/commands";
    }
  ];
}
