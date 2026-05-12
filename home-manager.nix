{ shmulsidian }:

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.shmulsidian;

  supportedProviders = [ "claude-code" "codex" "copilot" ];

  shmulsidianRoot = shmulsidian;
  vaultMcp = shmulsidian.packages.${pkgs.stdenv.hostPlatform.system}.vault-mcp;

  providerModule = name: import (./modules/providers + "/${name}.nix") {
    inherit lib pkgs config shmulsidianRoot vaultMcp;
    mcpEnabled = cfg.mcp.enable;
  };

  providerImports = map providerModule cfg.providers;
in {
  options.programs.shmulsidian = {
    enable = lib.mkEnableOption "shmulsidian vault utilities, MCP, and slash commands";

    personalVaultPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/shmulsidian";
      description = ''
        Absolute path to the user's personal shmulsidian vault. Exported as
        $PERSONAL_VAULT_PATH for downstream tools and consumed by the vault MCP.
      '';
    };

    providers = lib.mkOption {
      type = lib.types.listOf (lib.types.enum supportedProviders);
      default = [ "claude-code" ];
      example = [ "claude-code" "codex" "copilot" ];
      description = ''
        AI providers to wire MCP and slash commands for. Each provider has its
        own adapter in modules/providers/<name>.nix — add a new file to extend.
      '';
    };

    mcp.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the single vault MCP server and wire it into every enabled provider.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge ([
    {
      home.packages = [
        shmulsidian.packages.${pkgs.stdenv.hostPlatform.system}.default
      ] ++ lib.optional cfg.mcp.enable vaultMcp;

      home.sessionVariables.PERSONAL_VAULT_PATH = cfg.personalVaultPath;
    }
  ] ++ providerImports));
}
