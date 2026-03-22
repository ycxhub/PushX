---
name: pull-from-main
description: Clean working tree, pull origin/main, npm install, db types, build; notes on merge conflicts and Supabase migration repair.
---

# Pull from Main

Sync TTS Battles with the Speech Arena GitHub repo (origin/main). Run these steps in order:

0. **Ensure working tree is clean**
   ```bash
   git status
   ```
   If you have uncommitted changes, either commit them or stash before pulling:
   ```bash
   git stash
   ```

1. **Pull latest code**
   ```bash
   git pull origin main
   ```

2. **Install dependencies** (in case package.json or package-lock.json changed)
   ```bash
   npm install
   ```

3. **Regenerate database types** (if migrations or schema changed)
   ```bash
   npm run db:types
   ```

4. **Build** (verify the project compiles)
   ```bash
   npm run build
   ```

If `git pull` reports merge conflicts, stop and resolve them before continuing.

**Supabase migration repair:** If `supabase db push` was run and migrations fail with "relation already exists", mark each affected migration as applied:
   ```bash
   npx supabase migration repair --status applied <timestamp>
   ```
   Replace `<timestamp>` with the migration filename prefix (e.g. `20240101120000` from `20240101120000_create_users.sql`). Then re-run `npm run db:types`.

