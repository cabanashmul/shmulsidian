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
- The personal vault MCP server (`shmulsidian`) wired into `~/.claude.json` (user-level, visible in every project).
- Slash commands available vault-locally when you open the vault in Claude Code — commands are **never** installed globally.

## Group vaults

For per-project knowledge bases, create a vault git repo then wire it to each project repo using the `/wiring` command (runs inside the vault, not the project):

```bash
# Inside the group vault (e.g. universe-vault/)
/wiring add ../my-project-repo
```

This writes three things into the project repo:

| File | What it does |
|---|---|
| `.mcp.json` | Project-level MCP entry (`<repo>-vault` server name) — gitignored, each developer regenerates it |
| `.envrc` | Exports `SHMULSIDIAN_VAULT` so agents know where the vault is |
| `CLAUDE.md` / `AGENTS.md` | Vault section pointing agents at the right folders |

The MCP server name uses a `-vault` suffix (e.g. `universe-vault`) so it never collides with a future project-specific MCP for the same repo.

Other `/wiring` sub-commands:

```bash
/wiring status   # check which files are in place for each registered repo
/wiring sync     # re-write agent files + MCP config for all registered repos
/wiring remove <name>  # unregister a repo
```

`.shmulsidian/` (registry + search index, contains absolute local paths) is always gitignored — each developer runs `/wiring add` once after cloning.

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
