# shmulistan-template

A Nix-flake template for a Claude Code + Obsidian vault. Provides:

- A starter vault skeleton (PARA + Zettelkasten + MEMORY.md) via `nix flake init`.
- A Home Manager module that installs CLI utilities, exports `$PERSONAL_VAULT_PATH`, and writes machine-wide MCP config per AI provider.

## Scaffold a new vault

```bash
mkdir my-vault && cd my-vault
nix flake init -t github:shmul95/shmulistan-template
git init && git add -A && git commit -m "init from shmulistan-template"
```

The scaffold is a **one-shot copy** — you own the files afterwards. Open the directory as an Obsidian vault.

## Enable the Home Manager module

```nix
# flake.nix
{
  inputs.shmulistan-template.url = "github:shmul95/shmulistan-template";

  outputs = { self, nixpkgs, home-manager, shmulistan-template, ... }: {
    homeConfigurations.you = home-manager.lib.homeManagerConfiguration {
      modules = [
        shmulistan-template.homeManagerModules.default
        {
          programs.shmulistan = {
            enable = true;
            personalVaultPath = "/home/you/my-vault";
            mcp.providers = [ "claude-code" "codex" ];
          };
        }
      ];
    };
  };
}
```

What this gives you:

- `$PERSONAL_VAULT_PATH` exported to your shell (downstream tools key off this).
- `shmulistan-*` CLI utilities on `$PATH` (firecrawl-scrape, transcript-extract, …).
- Per-provider MCP config at `$XDG_CONFIG_HOME/shmulistan/mcp/<provider>.json` for each entry in `mcp.providers`.

## Updates

Two channels by design:

| What you're updating          | How users get it                                                                            |
| ----------------------------- | ------------------------------------------------------------------------------------------- |
| Starter content (`template/`) | One-shot. Existing users keep what they have; new users get the change on `nix flake init`. |
| Module / scripts / MCP wiring | Continuous. `nix flake update shmulistan-template && home-manager switch`.                  |

Put user-editable starter docs in `template/`. Put anything you want to keep current (new CLI script, new MCP server, new slash command) in the flake outputs / HM module.

## Supported MCP providers

`claude-code`, `codex`. Extend `supportedProviders` in `home-manager.nix` to add more.

## License

MIT — see `LICENSE`.
