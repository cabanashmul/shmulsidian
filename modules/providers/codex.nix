# Provider adapter: codex (OpenAI Codex CLI).
#
# Codex reads MCP servers exclusively from ~/.codex/config.toml under
# [mcp_servers.<name>]. Separate .toml files are NOT auto-included.
# We use a home.activation script that safely merges the shmulsidian entry
# into config.toml using tomlq (from yq), leaving other keys untouched.
#
# Slash-command equivalents live in ~/.codex/prompts/ (same md files as
# claude-code commands — shared source).
{ lib, pkgs, config, shmulsidianRoot, vaultMcp, mcpEnabled }:

let
  mcpCommand = "${vaultMcp}/bin/shmulsidian-mcp";
  vaultPath = config.programs.shmulsidian.personalVaultPath;

  mergeScript = pkgs.writeShellScript "codex-merge-mcp" ''
    set -euo pipefail
    CONFIG="$HOME/.codex/config.toml"
    mkdir -p "$HOME/.codex"

    # Bootstrap if missing
    [ -f "$CONFIG" ] || touch "$CONFIG"

    # Use Python (always available in nixpkgs) to merge the TOML entry.
    # tomlkit preserves comments and key order; fall back to raw append if absent.
    ${pkgs.python3}/bin/python3 - "$CONFIG" <<'PYEOF'
import sys, pathlib

config_path = pathlib.Path(sys.argv[1])
text = config_path.read_text() if config_path.exists() else ""

try:
    import tomlkit
    doc = tomlkit.parse(text)
    if "mcp_servers" not in doc:
        doc["mcp_servers"] = tomlkit.table()
    entry = tomlkit.table()
    entry.add("command", "${mcpCommand}")
    entry.add("args", tomlkit.array())
    env_tbl = tomlkit.table()
    env_tbl.add("PERSONAL_VAULT_PATH", "${vaultPath}")
    entry.add("env", env_tbl)
    doc["mcp_servers"]["shmulsidian"] = entry
    config_path.write_text(tomlkit.dumps(doc))
except ImportError:
    # Fallback: raw append (idempotent via header check)
    marker = "[mcp_servers.shmulsidian]"
    if marker not in text:
        with open(config_path, "a") as f:
            f.write(f'''
[mcp_servers.shmulsidian]
command = "${mcpCommand}"
args = []

[mcp_servers.shmulsidian.env]
PERSONAL_VAULT_PATH = "${vaultPath}"
''')
PYEOF
  '';
in {
  home.file.".codex/prompts".source = "${shmulsidianRoot}/.claude/commands";

  home.activation.codexMcpWire = lib.mkIf mcpEnabled (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${mergeScript}
    ''
  );
}
