# /ycx-qa — QA Lead (Browser Testing)

Test the app in a real browser, find bugs, fix them, write regression tests.

## Context Gate

This command requires a **web application** with a URL to test. Before starting:

```bash
[ -f package.json ] && grep -qE '"(next|react|vue|svelte|angular|vite|webpack)"' package.json 2>/dev/null && echo "CONTEXT:web"
[ -f Gemfile ] && grep -q "rails" Gemfile 2>/dev/null && echo "CONTEXT:web"
ls *.xcodeproj Package.swift 2>/dev/null | head -1 && echo "CONTEXT:native"
```

**If CONTEXT:native:** "This project is a native app. Browser QA does not apply. For iOS/Android testing, use device testing protocols instead. Suggest: create a test protocol document at `docs/device-test-protocol.md`." STOP.

**If no URL provided:** Ask the user for the URL to test (localhost, staging, or production).

## Browser Setup

This workflow uses the `cursor-ide-browser` MCP. The browser commands are:
- `browser_navigate` — go to a URL
- `browser_snapshot` — get page structure and element refs
- `browser_click` — click an element
- `browser_fill` — clear and fill an input
- `browser_type` — type text into focused element
- `browser_screenshot` — take a screenshot
- `browser_console` — check console for errors
- `browser_tabs` — list/manage tabs

## QA Workflow

### Step 1: Navigate and Baseline

Navigate to the target URL. Take a snapshot to see the page structure.

Check console for errors immediately after page load.

### Step 2: Map User Flows

Identify the key user flows to test based on the recent diff:
```bash
git diff origin/main --name-only
```

Map changed files to user-facing flows. Prioritize flows that touch changed code.

### Step 3: Walk Each Flow

For each flow:

1. **Navigate** to the starting page
2. **Snapshot** to see interactive elements
3. **Interact** (fill forms, click buttons, navigate)
4. **Verify** expected outcome:
   - Check for console errors after each interaction
   - Verify expected elements are visible
   - Take screenshots as evidence
5. **Check edge cases:**
   - Empty form submission
   - Invalid input
   - Double-click on submit buttons
   - Back button behavior
   - Loading states

### Step 4: Bug Report

For each bug found:
```
BUG: [title]
Severity: CRITICAL / HIGH / MEDIUM / LOW
Steps to reproduce:
  1. Navigate to [URL]
  2. [action]
  3. [action]
Expected: [what should happen]
Actual: [what happens instead]
Console errors: [if any]
Screenshot: [reference]
```

### Step 5: Fix Bugs (if in fix mode)

For each bug:
1. Identify the root cause in code
2. Apply the minimal fix
3. Write a regression test
4. Re-test in browser to verify the fix works

Commit each fix atomically: `fix: [description of what was fixed]`

### Step 6: Report

```
QA REPORT
═══════════════════════════════
URL tested: [url]
Flows tested: [count]
Bugs found: [count] (X critical, Y high, Z medium)
Bugs fixed: [count]
Regression tests added: [count]
Console errors: [count]
Status: DONE | DONE_WITH_CONCERNS
═══════════════════════════════
```

## Responsive Testing (web projects)

If testing a web app, also check responsive layouts:

1. Navigate to the page
2. Test at mobile viewport (375x812)
3. Test at tablet viewport (768x1024)
4. Test at desktop viewport (1280x720)
5. Screenshot each and compare

## Important Rules

- Check console after EVERY interaction
- Screenshot before and after critical actions
- Never claim "looks fine" without evidence
- If browser tools are unavailable, state: "Browser MCP not configured. Run QA manually or configure cursor-ide-browser."
