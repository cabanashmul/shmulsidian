# Wiring

Manages the connection between this vault and external project repos.
Keeps `repos.toml` up to date, writes `CLAUDE.md` / `AGENTS.md` pointers,
and wires the shmulsidian MCP server into each registered repo using
provider-aware in-repo config files.

## Vault paths

- **This vault**: detect from the current working directory (the vault root where this command runs).
- **repos.toml**: `<vault-root>/.shmulsidian/repos.toml`

---

## Sub-commands

### `add <repo-path>`

1. Resolve `<repo-path>` to an absolute path.
2. Check the path exists and is a git repo (`git -C <path> rev-parse --git-dir`).
3. Read `.shmulsidian/repos.toml` (create it if absent).
4. Check whether an entry with this path already exists. If yes, confirm with the user before overwriting.
5. Prompt for a short `name` (default: directory basename) and optional `description`.
6. Append the entry to repos.toml:

```toml
[[repo]]
name = "my-project"
path = "/absolute/path/to/repo"
description = "Optional description"
vault = "<vault-root>"
```

7. Call the **write-agent-files** routine for this repo.
8. Call the **write-mcp-config** routine for this repo.
9. Call the **write-env-config** routine for this repo.
10. Report everything written.

---

### `remove <name>`

1. Read `.shmulsidian/repos.toml`. Find entry by name; report and stop if not found.
2. Show the entry and ask the user to confirm deletion.
3. Remove the `[[repo]]` block from repos.toml.
4. Offer (but do not force) to remove the vault section from `CLAUDE.md` / `AGENTS.md`.
5. Remind the user to remove any project-specific entry from `~/.claude.json` manually (it is not committed).

---

### `status`

1. Read `.shmulsidian/repos.toml`. If absent, report "No repos registered."
2. For each `[[repo]]` entry check:
   - Path exists on disk
   - `CLAUDE.md` has a vault section
   - `AGENTS.md` has a vault section
   - MCP wired globally (remind user that `~/.claude.json` / `~/.codex/config.toml` hold personal entries)
   - Env configured (`.envrc` exports `SHMULSIDIAN_VAULT`, or flake devShell sets it)
3. Print a summary table with a ✓/✗ per column.

---

### `sync`

1. Read `.shmulsidian/repos.toml`.
2. For each registered repo, run **write-agent-files**, **write-mcp-config**, and **write-env-config**.
3. Report which files were written or already up to date.

---

## write-agent-files routine

Given a repo path and vault root, write or update `CLAUDE.md` and `AGENTS.md` in the repo.

### `CLAUDE.md` — create or patch vault section

If absent, create with only the section below.
If present, replace existing `## Vault` section or append if none exists.

```markdown
## Vault

Notes, decisions, and AI memory for this project are stored in the vault at
`$SHMULSIDIAN_VAULT` (set by `.envrc` or the flake devShell).

When capturing insights, decisions, or permanent notes during a session in this
repo, write them to the vault — not to this repo. Specifically:
- Permanent notes → `$SHMULSIDIAN_VAULT/01_Zettelkasten/`
- Project workspace → `$SHMULSIDIAN_VAULT/02_Projects/<repo-name>/`
- Raw captures    → `$SHMULSIDIAN_VAULT/00_Inbox/`
- AI memory       → `$SHMULSIDIAN_VAULT/memory/`

Do not commit vault files from within this repo's git history.
```

### `AGENTS.md` — create or patch vault section

Same logic, equivalent content for Codex and other agents.

```markdown
## Vault

Notes, decisions, and AI memory for this project live at `$SHMULSIDIAN_VAULT`
(set by `.envrc` or the flake devShell).

When the user asks you to capture or remember something:
- Permanent notes → `$SHMULSIDIAN_VAULT/01_Zettelkasten/`
- Project workspace → `$SHMULSIDIAN_VAULT/02_Projects/<repo-name>/`
- Raw inbox        → `$SHMULSIDIAN_VAULT/00_Inbox/`

Do not store notes inside this repo. Do not commit vault files here.
```

---

## write-mcp-config routine

Two MCP entries exist — they are distinct and go to different places:

| Entry | What it is | Where it lives |
|---|---|---|
| `shmulsidian` | Personal vault (`~/shmulsidian`) | `~/.claude.json` — home-manager territory, never touched here |
| `<repo-name>` | This group vault linked to the repo | In-repo `.mcp.json` — written by this routine, gitignored |

`.mcp.json` is Claude Code v2+'s project-level MCP file (`.claude/settings.json` no longer
carries `mcpServers`). It contains a personal absolute path so it must be gitignored.
Developers who clone the repo run `/wiring add` once to regenerate it for their machine.

### Provider: claude-code

Write or merge `.mcp.json` at the repo root. Use the repos.toml `name` as the server name.
If an entry with the same name already exists, confirm before overwriting.

```json
{
  "mcpServers": {
    "<repo-name>-vault": {
      "command": "shmulsidian-mcp",
      "args": ["--vault-path", "<vault-root>", "--project-name", "<repo-name>"],
      "env": {},
      "type": "stdio"
    }
  }
}
```

Also ensure `.mcp.json` is in the repo's `.gitignore` (append if missing).

### Provider: codex (`.codex/` directory exists in the repo)

Append to `~/.codex/config.toml` (codex has no per-project config file).
Inform the user what was added.

---

## write-env-config routine

The MCP server needs `SHMULSIDIAN_VAULT` in the environment when the agent starts.
Detect how the repo manages its environment and add the variable accordingly.

### direnv (`.envrc` exists or no env system detected)

Append to `.envrc` if not already present (check for existing `SHMULSIDIAN_VAULT` line first):

```bash
export SHMULSIDIAN_VAULT="<vault-root>"   # set by /wiring add
```

If `.envrc` did not previously exist, create it with this line and inform the user to run
`direnv allow` after.

### flake devShell (`flake.nix` exists and contains `devShell` or `devShells`)

Inform the user that automatic patching of `flake.nix` is not done (too many shapes).
Instead, show the snippet they should add to their `shellHook`:

```nix
shellHook = ''
  export SHMULSIDIAN_VAULT="<vault-root>"
'';
```

If both `.envrc` and `flake.nix` exist, default to `.envrc` (it takes effect without
`nix develop`) and show the flake snippet as an optional note.

---

## Argument parsing

- No argument or unknown sub-command → print usage summary and stop.
- `$ARGUMENTS` contains everything after `/wiring`.
- First token is the sub-command; remainder is the sub-command's argument.

## Safety rules

- Never overwrite `CLAUDE.md`, `AGENTS.md`, or `settings.json` wholesale — only patch the relevant section.
- Never write to `~/.claude/` or `~/.codex/` — those are home-manager territory.
- Never commit anything — show what was written and let the user commit.
- Never modify files outside the registered repo and this vault.
