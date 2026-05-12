---
tags: [review, workflow]
---

# Weekly Review

## Schedule
Run this review once a week to keep your knowledge base healthy.

## Checklist

### Inbox Processing
- [ ] Review all items in `00_Inbox/`
- [ ] Move or delete each item (goal: under 20 items)
- [ ] Tag anything needing more work with `#needs-processing`

### Zettelkasten Maintenance
- [ ] Review recently created notes for quality
- [ ] Add missing links between related notes
- [ ] Check for orphan notes (no incoming links)
- [ ] Look for clusters that could become a project or article

### Projects
- [ ] Update status of active projects in `02_Projects/`
- [ ] Archive any completed projects to `04_Archive/`
- [ ] Check deadlines and priorities

### References
- [ ] Process any unread reference materials
- [ ] Extract key ideas into Zettelkasten notes
- [ ] Clean up web clippings

### Git
- [ ] Commit and push all changes
- [ ] Review recent commit history

## Quick Commands
```bash
pnpm vault:stats          # See vault overview
pnpm attachments:orphans  # Find unreferenced attachments
```
