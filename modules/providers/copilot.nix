# Provider adapter: GitHub Copilot (VS Code chat).
#
# Copilot MCP wiring is configured in the VS Code user settings. We write a
# fragment to $XDG_CONFIG_HOME/shmulsidian/providers/copilot.json that the user
# imports into their VS Code settings.json (or that a downstream HM module
# merges automatically — out of scope for v1.0.0).
{ lib, pkgs, config, shmulsidianRoot, vaultMcp, mcpEnabled }:

{
  xdg.configFile = lib.mkMerge [
    (lib.mkIf mcpEnabled {
      "shmulsidian/providers/copilot.json".text = builtins.toJSON {
        "github.copilot.chat.mcp.servers" = {
          shmulsidian = {
            command = "${vaultMcp}/bin/shmulsidian-mcp";
            env.PERSONAL_VAULT_PATH = config.programs.shmulsidian.personalVaultPath;
          };
        };
      };
    })
    {
      "shmulsidian/providers/copilot-prompts".source = "${shmulsidianRoot}/.claude/commands";
    }
  ];
}
