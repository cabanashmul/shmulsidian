from __future__ import annotations

import datetime as dt
import os
import re
from dataclasses import dataclass
from pathlib import Path

MD_SUFFIX = ".md"
SAFE_FILENAME = re.compile(r"[^A-Za-z0-9._\- ]+")


@dataclass(slots=True, frozen=True)
class NoteRef:
    path: str         # vault-relative, posix-style
    size: int
    mtime: float


def iter_notes(vault: Path) -> list[NoteRef]:
    out: list[NoteRef] = []
    for p in vault.rglob(f"*{MD_SUFFIX}"):
        if not p.is_file():
            continue
        # skip dotted dirs (.git, .obsidian, etc.) anywhere in the tree
        if any(part.startswith(".") for part in p.relative_to(vault).parts):
            continue
        st = p.stat()
        out.append(NoteRef(
            path=p.relative_to(vault).as_posix(),
            size=st.st_size,
            mtime=st.st_mtime,
        ))
    return out


def list_notes(vault: Path, folder: str | None = None, limit: int = 200) -> list[dict]:
    refs = iter_notes(vault)
    if folder:
        prefix = folder.rstrip("/") + "/"
        refs = [r for r in refs if r.path.startswith(prefix)]
    refs.sort(key=lambda r: r.mtime, reverse=True)
    return [{"path": r.path, "size": r.size, "mtime": r.mtime} for r in refs[:limit]]


def read_note(vault: Path, path: str) -> dict:
    p = _safe_join(vault, path)
    if not p.is_file():
        raise FileNotFoundError(f"note not found: {path}")
    content = p.read_text(encoding="utf-8")
    st = p.stat()
    return {"path": path, "content": content, "size": st.st_size, "mtime": st.st_mtime}


def create_note(
    vault: Path,
    title: str,
    body: str,
    folder: str = "00_Inbox",
    tags: list[str] | None = None,
) -> dict:
    folder_path = _safe_join(vault, folder)
    folder_path.mkdir(parents=True, exist_ok=True)

    stamp = dt.datetime.now().strftime("%Y%m%d%H%M%S")
    slug = SAFE_FILENAME.sub("", title).strip().replace(" ", "-").lower()[:60] or "note"
    fname = f"{stamp}-{slug}{MD_SUFFIX}"
    target = folder_path / fname
    if target.exists():
        target = folder_path / f"{stamp}-{slug}-{os.urandom(2).hex()}{MD_SUFFIX}"  # collision-proof

    frontmatter_lines = ["---", f"title: {title}", f"created: {dt.datetime.now().isoformat(timespec='seconds')}"]
    if tags:
        frontmatter_lines.append("tags: [" + ", ".join(tags) + "]")
    frontmatter_lines.append("---")
    target.write_text("\n".join(frontmatter_lines) + "\n\n" + body.rstrip() + "\n", encoding="utf-8")

    rel = target.relative_to(vault).as_posix()
    return {"path": rel, "size": target.stat().st_size}


def _safe_join(vault: Path, rel: str) -> Path:
    # Reject paths that escape the vault.
    candidate = (vault / rel).resolve()
    try:
        candidate.relative_to(vault.resolve())
    except ValueError:
        raise PermissionError(f"path escapes vault: {rel}")
    return candidate
