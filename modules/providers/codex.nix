# Provider adapter: codex (OpenAI Codex CLI).
#
# Codex reads MCP servers from ~/.codex/config.toml under [mcp_servers.<name>].
# Slash-command equivalents live in ~/.codex/prompts/.
{ lib, pkgs, config, shmulsidianRoot, vaultMcp, mcpEnabled }:

let
  mcpToml = ''
    [mcp_servers.shmulsidian]
    command = "${vaultMcp}/bin/shmulsidian-mcp"
    args = []

    [mcp_servers.shmulsidian.env]
    PERSONAL_VAULT_PATH = "${config.programs.shmulsidian.personalVaultPath}"
  '';
in {
  home.file = lib.mkMerge [
    (lib.mkIf mcpEnabled {
      ".codex/mcp.shmulsidian.toml".text = mcpToml;
    })
    {
      # Codex prompts are plain markdown — claude-code commands map 1:1.
      ".codex/prompts".source = "${shmulsidianRoot}/.claude/commands";
    }
  ];
}
