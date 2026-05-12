from __future__ import annotations

import sqlite3
import struct
from dataclasses import dataclass
from pathlib import Path

import sqlite_vec

CHUNK_SIZE = 800       # chars per chunk before semantic embedding
CHUNK_OVERLAP = 120
EMBED_MODEL = "BAAI/bge-small-en-v1.5"   # fastembed default; ~130MB, 384-dim
EMBED_DIM = 384


@dataclass(slots=True)
class SearchHit:
    path: str
    chunk: str
    score: float


class VaultIndex:
    """SQLite-backed index: FTS5 for keyword, sqlite-vec for semantic."""

    def __init__(self, vault: Path, db_path: Path):
        self.vault = vault
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(self.db_path)
        self.conn.enable_load_extension(True)
        sqlite_vec.load(self.conn)
        self.conn.enable_load_extension(False)
        self._migrate()
        self._embedder = None  # lazy

    # ---- schema ----------------------------------------------------------
    def _migrate(self) -> None:
        c = self.conn
        c.executescript(f"""
            CREATE TABLE IF NOT EXISTS notes (
                path  TEXT PRIMARY KEY,
                mtime REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS chunks (
                id    INTEGER PRIMARY KEY AUTOINCREMENT,
                path  TEXT NOT NULL,
                idx   INTEGER NOT NULL,
                text  TEXT NOT NULL,
                FOREIGN KEY (path) REFERENCES notes(path) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS chunks_path_idx ON chunks(path);
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts
                USING fts5(text, content='chunks', content_rowid='id');
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks_vec
                USING vec0(embedding float[{EMBED_DIM}]);
        """)
        c.commit()

    # ---- embedder (lazy) -------------------------------------------------
    def _embed(self, texts: list[str]) -> list[list[float]]:
        if self._embedder is None:
            from fastembed import TextEmbedding
            self._embedder = TextEmbedding(model_name=EMBED_MODEL)
        return [list(v) for v in self._embedder.embed(texts)]

    @staticmethod
    def _pack(vec: list[float]) -> bytes:
        return struct.pack(f"{len(vec)}f", *vec)

    # ---- indexing --------------------------------------------------------
    def reindex(self, refs: list[tuple[str, float]]) -> dict:
        """refs = [(vault_relative_path, mtime), ...].

        Adds new/changed notes, removes deleted ones. Returns counters.
        """
        c = self.conn
        current = {p: m for p, m in refs}
        existing = dict(c.execute("SELECT path, mtime FROM notes").fetchall())

        to_remove = [p for p in existing if p not in current]
        to_upsert = [p for p, m in current.items() if existing.get(p) != m]

        for path in to_remove:
            self._delete_note(path)

        added = 0
        for path in to_upsert:
            self._delete_note(path)        # idempotent reset
            self._index_note(path, current[path])
            added += 1
        c.commit()
        return {"indexed": added, "removed": len(to_remove), "total": len(current)}

    def _delete_note(self, path: str) -> None:
        c = self.conn
        rows = c.execute("SELECT id FROM chunks WHERE path = ?", (path,)).fetchall()
        ids = [r[0] for r in rows]
        if ids:
            qmarks = ",".join("?" * len(ids))
            c.execute(f"DELETE FROM chunks_fts WHERE rowid IN ({qmarks})", ids)
            c.execute(f"DELETE FROM chunks_vec WHERE rowid IN ({qmarks})", ids)
            c.execute(f"DELETE FROM chunks WHERE id IN ({qmarks})", ids)
        c.execute("DELETE FROM notes WHERE path = ?", (path,))

    def _index_note(self, path: str, mtime: float) -> None:
        c = self.conn
        full = (self.vault / path).read_text(encoding="utf-8", errors="replace")
        chunks = _chunk(full)
        if not chunks:
            return
        vectors = self._embed(chunks)
        c.execute("INSERT INTO notes(path, mtime) VALUES (?, ?)", (path, mtime))
        for idx, (text, vec) in enumerate(zip(chunks, vectors)):
            cur = c.execute(
                "INSERT INTO chunks(path, idx, text) VALUES (?, ?, ?)",
                (path, idx, text),
            )
            rowid = cur.lastrowid
            c.execute("INSERT INTO chunks_fts(rowid, text) VALUES (?, ?)", (rowid, text))
            c.execute(
                "INSERT INTO chunks_vec(rowid, embedding) VALUES (?, ?)",
                (rowid, self._pack(vec)),
            )

    # ---- search ----------------------------------------------------------
    def search_keyword(self, query: str, k: int = 10) -> list[SearchHit]:
        rows = self.conn.execute(
            """
            SELECT c.path, c.text, bm25(chunks_fts) AS score
              FROM chunks_fts
              JOIN chunks c ON c.id = chunks_fts.rowid
             WHERE chunks_fts MATCH ?
             ORDER BY score
             LIMIT ?
            """,
            (query, k),
        ).fetchall()
        # bm25 returns negative-magnitude where smaller is better; normalize.
        return [SearchHit(path=p, chunk=t, score=-s) for p, t, s in rows]

    def search_semantic(self, query: str, k: int = 10) -> list[SearchHit]:
        qvec = self._embed([query])[0]
        rows = self.conn.execute(
            """
            SELECT c.path, c.text, v.distance
              FROM chunks_vec v
              JOIN chunks c ON c.id = v.rowid
             WHERE v.embedding MATCH ?
               AND k = ?
             ORDER BY v.distance
            """,
            (self._pack(qvec), k),
        ).fetchall()
        # distance ∈ [0, 2]; convert to similarity ∈ [0, 1].
        return [SearchHit(path=p, chunk=t, score=max(0.0, 1.0 - d / 2.0)) for p, t, d in rows]

    def search_hybrid(self, query: str, k: int = 10, sem_weight: float = 0.7) -> list[SearchHit]:
        kw_weight = 1.0 - sem_weight
        sem = {(h.path, h.chunk): h.score for h in self.search_semantic(query, k * 2)}
        kw = {(h.path, h.chunk): h.score for h in self.search_keyword(query, k * 2)}

        def norm(d: dict) -> dict:
            if not d:
                return {}
            top = max(d.values()) or 1.0
            return {k: v / top for k, v in d.items()}

        sem_n, kw_n = norm(sem), norm(kw)
        keys = set(sem_n) | set(kw_n)
        scored = [
            SearchHit(path=p, chunk=t,
                      score=sem_weight * sem_n.get((p, t), 0.0) + kw_weight * kw_n.get((p, t), 0.0))
            for (p, t) in keys
        ]
        scored.sort(key=lambda h: h.score, reverse=True)
        return scored[:k]


def _chunk(text: str) -> list[str]:
    text = text.strip()
    if not text:
        return []
    out, i = [], 0
    while i < len(text):
        out.append(text[i : i + CHUNK_SIZE])
        i += CHUNK_SIZE - CHUNK_OVERLAP
    return out
