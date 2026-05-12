{ shmulistan }:

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.shmulistan;
  supportedProviders = [ "claude-code" "codex" ];

  mcpConfigDir = "${config.xdg.configHome}/shmulistan/mcp";

  # Per-provider machine-wide MCP config describing how to talk to the vault.
  # Provider tooling reads/imports these from $XDG_CONFIG_HOME/shmulistan/mcp/.
  mcpConfigFor = provider: {
    name = "shmulistan";
    vaultPath = cfg.personalVaultPath;
    provider = provider;
  };
in {
  options.programs.shmulistan = {
    enable = lib.mkEnableOption "shmulistan vault utilities and MCP wiring";

    personalVaultPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/shmulistan";
      description = ''
        Absolute path to the user's shmulistan Obsidian vault.
        Exported as $PERSONAL_VAULT_PATH for downstream tools.
      '';
    };

    mcp.providers = lib.mkOption {
      type = lib.types.listOf (lib.types.enum supportedProviders);
      default = [ "claude-code" ];
      example = [ "claude-code" "codex" ];
      description = ''
        AI providers to wire vault-aware MCP config for. One config file is written
        per enabled provider under $XDG_CONFIG_HOME/shmulistan/mcp/<provider>.json.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      shmulistan.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];

    home.sessionVariables.PERSONAL_VAULT_PATH = cfg.personalVaultPath;

    xdg.configFile = lib.listToAttrs (map (provider: {
      name = "shmulistan/mcp/${provider}.json";
      value.text = builtins.toJSON (mcpConfigFor provider);
    }) cfg.mcp.providers);
  };
}
