# shmulsidian

Claude Code + Obsidian vault scaffold, vault MCP, and Home Manager module — all behind one flake.

```bash
mkdir my-vault && cd my-vault
nix flake init -t github:cabanashmul/shmulsidian          # personal vault scaffold
# or
nix run github:cabanashmul/shmulsidian#setup -- personal  # same thing, scriptable
```

The scaffold is **one-shot** — you own the files afterwards. Open the directory in Obsidian.

## Home Manager wiring

```nix
{
  inputs.shmulsidian.url = "github:cabanashmul/shmulsidian";

  outputs = { self, nixpkgs, home-manager, shmulsidian, ... }: {
    homeConfigurations.you = home-manager.lib.homeManagerConfiguration {
      modules = [
        shmulsidian.homeManagerModules.default
        {
          programs.shmulsidian = {
            enable = true;
            personalVaultPath = "/home/you/my-vault";
            providers = [ "claude-code" "codex" "copilot" ];
            mcp.enable = true;  # default
          };
        }
      ];
    };
  };
}
```

You get:

- `$PERSONAL_VAULT_PATH` exported to your shell.
- `shmulsidian-*` CLI utilities on `$PATH`.
- The vault MCP server (`shmulsidian-mcp`) wired into every enabled provider.
- Slash commands installed at the right per-provider location (claude-code: `~/.claude/commands`, codex: `~/.codex/prompts`, copilot: fragment under `$XDG_CONFIG_HOME/shmulsidian/providers/`).

## Group vaults

For per-project knowledge bases:

```bash
cd my-project-repo
nix flake init -t github:cabanashmul/shmulsidian#group
nix run .#init            # registers <project>-shmulsidian-mcp locally
nix run .#vault-import -- --tag <name>     # pull notes from personal vault
nix run .#vault-export                     # sync project notes back
```

Group MCP/commands register **project-locally** under `<project>-shmulsidian-*` so they don't collide with the global `shmulsidian-mcp` from the HM module.

## Updates

| Layer                                | Update channel                                                   |
| ------------------------------------ | ---------------------------------------------------------------- |
| Starter content (`template/*`)       | One-shot. Existing users keep what they have.                    |
| MCP, commands, scripts, HM module    | `nix flake update shmulsidian && home-manager switch`.           |

## Adding a provider

Drop `modules/providers/<name>.nix` exposing `home.file` / `xdg.configFile` entries for that tool's MCP + prompt locations. Add `<name>` to `supportedProviders` in `home-manager.nix`. Done — no surgery elsewhere.

## Roadmap

- **v1.0** — personal + group templates, vault MCP wiring, claude-code/codex/copilot adapters.
- **v1.1+** — real vault MCP impl (semantic + keyword search, doc creation); vault HTTP browser daemon with SSH allowlist (likely via HM user-mode systemd or Docker — `services.shmulsidian` deferred).

## License

MIT — see `LICENSE`.
