from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(prog="shmulsidian-mcp")
    p.add_argument(
        "--vault-path",
        default=os.environ.get("PERSONAL_VAULT_PATH"),
        help="Absolute path to the Obsidian vault root. Defaults to $PERSONAL_VAULT_PATH.",
    )
    p.add_argument(
        "--project-name",
        default=None,
        help="Optional group/project scope. Surfaces in MCP server identity.",
    )
    p.add_argument(
        "--transport",
        choices=("stdio", "sse"),
        default="stdio",
        help="MCP transport. stdio for local AI tools; sse for HTTP clients.",
    )
    p.add_argument("--host", default="127.0.0.1", help="SSE bind host.")
    p.add_argument("--port", type=int, default=8787, help="SSE bind port.")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if not args.vault_path:
        print("shmulsidian-mcp: --vault-path or $PERSONAL_VAULT_PATH required", file=sys.stderr)
        return 2

    vault = Path(args.vault_path).expanduser().resolve()
    if not vault.is_dir():
        print(f"shmulsidian-mcp: vault not a directory: {vault}", file=sys.stderr)
        return 2

    from .server import run_server

    return run_server(
        vault=vault,
        project_name=args.project_name,
        transport=args.transport,
        host=args.host,
        port=args.port,
    )
