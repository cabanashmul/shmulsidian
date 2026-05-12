from __future__ import annotations

import asyncio
from pathlib import Path

from mcp.server.fastmcp import FastMCP

from .index import VaultIndex
from .notes import create_note as fs_create_note
from .notes import iter_notes
from .notes import list_notes as fs_list_notes
from .notes import read_note as fs_read_note


def build_app(vault: Path, project_name: str | None) -> FastMCP:
    name = f"{project_name}-shmulsidian-mcp" if project_name else "shmulsidian-mcp"
    app = FastMCP(name)

    db_path = vault / ".shmulsidian" / "index.sqlite"
    index = VaultIndex(vault=vault, db_path=db_path)

    def _sync_index() -> dict:
        refs = [(n.path, n.mtime) for n in iter_notes(vault)]
        return index.reindex(refs)

    # Warm the index on startup. First call also lazily downloads the
    # fastembed model into the user's cache.
    _sync_index()

    @app.tool()
    def list_notes(folder: str | None = None, limit: int = 200) -> list[dict]:
        """List notes in the vault, optionally filtered to a folder. Newest first."""
        return fs_list_notes(vault, folder=folder, limit=limit)

    @app.tool()
    def read_note(path: str) -> dict:
        """Read a single note by its vault-relative path."""
        return fs_read_note(vault, path)

    @app.tool()
    def create_note(title: str, body: str, folder: str = "00_Inbox",
                    tags: list[str] | None = None) -> dict:
        """Create a new markdown note with frontmatter and refresh the index."""
        result = fs_create_note(vault, title=title, body=body, folder=folder, tags=tags)
        _sync_index()
        return result

    @app.tool()
    def search_notes_keyword(query: str, k: int = 10) -> list[dict]:
        """FTS5 keyword search. Returns chunks with relevance scores."""
        _sync_index()
        return [h.__dict__ for h in index.search_keyword(query, k)]

    @app.tool()
    def search_notes_semantic(query: str, k: int = 10) -> list[dict]:
        """Embedding-based semantic search. Returns chunks with similarity scores."""
        _sync_index()
        return [h.__dict__ for h in index.search_semantic(query, k)]

    @app.tool()
    def search_notes(query: str, k: int = 10) -> list[dict]:
        """Hybrid search: 70% semantic + 30% keyword."""
        _sync_index()
        return [h.__dict__ for h in index.search_hybrid(query, k, sem_weight=0.7)]

    return app


def run_server(vault: Path, project_name: str | None, transport: str,
               host: str, port: int) -> int:
    app = build_app(vault, project_name)
    if transport == "stdio":
        app.run(transport="stdio")
    elif transport == "sse":
        # FastMCP's run() supports "sse" but binds on its own host/port via env;
        # use the lower-level API so we can pass host/port explicitly.
        import uvicorn
        uvicorn.run(app.sse_app(), host=host, port=port, log_level="info")
    else:
        raise ValueError(f"unknown transport: {transport}")
    return 0
