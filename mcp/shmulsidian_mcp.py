#!/usr/bin/env python3
"""shmulsidian vault MCP server.

Same binary serves the global (personal vault) and group (per-project) cases.
The provider adapters register it under different names; this process distinguishes
them via --project-name.
"""

from __future__ import annotations

import argparse
import os
import sys


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(prog="shmulsidian-mcp")
    p.add_argument(
        "--vault-path",
        default=os.environ.get("PERSONAL_VAULT_PATH"),
        help="Path to the Obsidian vault root. Defaults to $PERSONAL_VAULT_PATH.",
    )
    p.add_argument(
        "--project-name",
        default=None,
        help="When set, scopes the MCP to a group/project vault (registered as <name>-shmulsidian-mcp).",
    )
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if not args.vault_path:
        print("shmulsidian-mcp: --vault-path or $PERSONAL_VAULT_PATH required", file=sys.stderr)
        return 2

    scope = f"project={args.project_name}" if args.project_name else "scope=global"
    print(
        f"shmulsidian-mcp stub — vault={args.vault_path} {scope}\n"
        "TODO(v1.0): implement MCP server (doc creation, semantic + keyword search).",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
