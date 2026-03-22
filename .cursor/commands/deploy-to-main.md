---
name: deploy-to-main
description: Commit and merge to main, deploy GitHub/Vercel, classify changes, and append deploy notes (exclude .env.local).
---

## Deploy to Main

Commit and merge all branches onto the `main` branch and deploy on GitHub and Vercel. 

Write a crisp description by classifying changes into New Features, Feature Enhancements, or Bug Fixes of what's being committed on GitHub.

Do not commit .env.local to git.

---

## After deploying to main

Add the new deployment to [docs/deploy-to-main-notes.md](docs/deploy-to-main-notes.md):

1. **Append a new entry at the end** with the next sequential number (e.g. if the last is #63, add #64). Do not renumber existing entries.
2. **Structure for each deployment:**
   - **Title** with complexity in brackets: `[Low]` (< 50 lines), `[Medium]` (50–200 lines & < 10 files), `[High]` (> 200 lines, or 50–200 lines & ≥ 10 files)
   - **Date & Time (IST)**
   - **Deployment notes** (bullet points from the commit message)
   - **3 files with largest changes** (by total lines changed)

3. **Compute complexity** using the combined heuristic:
   - Run: `git show HEAD --numstat` to get lines and file count
   - Low: < 50 lines
   - Medium: 50–200 lines AND < 10 files
   - High: > 200 lines, OR (50–200 lines AND ≥ 10 files)

