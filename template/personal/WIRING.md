# Wiring a new vault to this one

This vault uses [shmulistan-template](https://github.com/shmul95/shmulistan-template) as its infrastructure backend (MCP server, setup apps, HM module). New vaults created from the template can be wired to this one in two ways: as a **personal vault** or as a **group member**.

## 1 — Track the template for infrastructure updates

Every vault that uses the infrastructure should track `shmulistan-template` as a git remote so it can pull infra updates independently of vault content:

```bash
git remote add template git@github.com:shmul95/shmulistan-template.git
git fetch template --no-tags
```

Pull a specific infrastructure fix:

```bash
git fetch template
git cherry-pick <commit>          # cherry-pick individual infra commits
# or: git merge template/main --allow-unrelated-histories  # full merge (careful)
```

## 2 — Set up a personal vault (new operator)

A new operator creates their vault by running the setup app from the template:

```bash
nix run github:shmul95/shmulistan-template#setup-personal -- --apply
```

This creates the PARA skeleton, writes `~/.config/shmulistan/publish-identity.toml`, and wires `shmulistan-mcp` into `~/.claude/settings.json`.

To also get this vault's utility scripts (`firecrawl-scrape`, `transcript-extract`, etc.) via Home Manager, point `shmulistan` input at this vault in their `cabanashmul`:

```nix
# flake.nix
inputs.shmulistan.url = "github:shmul95/shmulistan";
inputs.shmulistan.inputs.nixpkgs.follows = "nixpkgs";
```

```nix
# public/shmulistan.nix
flake.cabanashmul.homeModules.shmulistan = { ... }: {
  imports = [ inputs.shmulistan.homeManagerModules.default ];
  services.shmulistan.enable = true;
  # lib.mkOverlay re-exported from the template via this vault:
  # flake.cabanashmul.overlays = [ (inputs.shmulistan.lib.mkOverlay "x86_64-linux") ];
};
```

## 3 — Join the group vault (connect-mcp)

Once the group vault host is running (see [docs/security-model.md](https://github.com/shmul95/shmulistan-template/blob/main/docs/security-model.md)), a new operator joins by running:

```bash
nix run github:shmul95/shmulistan-template#connect-mcp \
  -- --vault ssh://<vault-user>@<host>/home/<vault-user>/vault.git
```

This fetches `.shmulistan/repos.toml` from the group vault and writes `.mcp.json` into each registered project repo.

## 4 — Register a new project repo in the group vault

The vault owner adds the new project to `repos.toml` in the group vault bare repo:

```toml
[[repo]]
name = "my-project"
path = "/home/dev/my-project"
description = "Main project repo"
```

After the vault owner pushes this, running `connect-mcp` again picks up the new entry.

## Relationship diagram

```
shmulistan-template (github:shmul95/shmulistan-template)
  ↓ git remote "template"
shmulistan (github:shmul95/shmulistan)          ← this repo
  ↓ flake input
cabanashmul (github:cabanashmul/cabanashmul)     ← HM starter
  ↓ home-manager switch
~/.claude/settings.json                          ← shmulistan-mcp wired
~/.config/shmulistan/publish-identity.toml
~/shmulistan/{00_Inbox,...,06_Metadata}/         ← PARA vault
```
