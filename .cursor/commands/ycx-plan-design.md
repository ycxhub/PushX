# /ycx-plan-design — Senior Designer Mode (Report Only)

Rate each design dimension 0-10, explain what a 10 looks like, then produce recommendations. This is a report — no code changes.

## Context Gate

This command requires UI/UX scope. Check:
```bash
git diff --name-only 2>/dev/null | grep -E '\.(tsx|jsx|vue|svelte|html|css|scss)$' | head -5
```

**If no frontend files found:** "No frontend files in the current diff. Design review is not applicable to backend-only changes." STOP.

## Step 1: Gather Context

1. Check for `DESIGN.md` or `design-system.md` in repo root. If found, use as the source of truth — patterns blessed in DESIGN.md are not flagged.
2. Read each changed frontend file (full file, not just diff).
3. If the project has a component library or design tokens, read those too.

## Step 2: Design Audit (10 Dimensions)

Rate each dimension 0-10. For scores below 8, explain what a 10 looks like.

### 1. Information Hierarchy
What does the user see first, second, third? Is the visual priority correct?

### 2. Interaction States
For every interactive element, are ALL states covered?
```
ELEMENT | LOADING | EMPTY | ERROR | SUCCESS | DISABLED | HOVER | FOCUS
```

### 3. Empty States
Are empty states designed (not just "No results found")? Empty states are features.

### 4. Error States
Do errors explain what happened AND what to do next? Can users recover?

### 5. Responsive Design
Does it work at mobile (375px), tablet (768px), desktop (1280px)? Is mobile an afterthought?

### 6. Accessibility
- Keyboard navigation for all interactive elements
- Screen reader labels (aria-label, alt text)
- Color contrast (4.5:1 minimum for text)
- Touch targets (44x44px minimum on mobile)
- Focus indicators visible

### 7. Typography & Spacing
Consistent type scale? Adequate line height (1.4-1.6 for body)? Consistent spacing rhythm?

### 8. Color & Contrast
Consistent palette? Meaningful use of color (not decorative only)? Sufficient contrast?

### 9. Animation & Transitions
Loading indicators? Page transitions? Micro-interactions on buttons/inputs? Nothing jarring?

### 10. AI Slop Detection
Does the design feel intentional or generically AI-generated? Signs of slop:
- Default system fonts with no personality
- Purple-on-white or gradient-heavy without reason
- Centered card stacks with no layout variation
- Generic stock-photo aesthetic
- "Lorem ipsum" or placeholder text left in

## Step 3: Score Summary

```
DESIGN AUDIT
═══════════════════════════════
Dimension            Score   Notes
Information Hierarchy  8/10  Good
Interaction States     5/10  Missing loading + error states
Empty States           3/10  Generic "no data" everywhere
Error States           6/10  Shows errors but no recovery path
Responsive             7/10  Desktop-first, mobile passable
Accessibility          4/10  No keyboard nav, missing aria
Typography             8/10  Consistent scale
Color                  7/10  Good palette, some contrast issues
Animation              5/10  No loading indicators
AI Slop                9/10  Intentional design choices
═══════════════════════════════
OVERALL: 6.2/10
```

## Step 4: Recommendations

For each dimension scoring below 7, provide:
1. **The specific problem** (with file:line reference)
2. **What a 10 looks like** (concrete description)
3. **Effort to fix** (S/M/L with both human and AI-assisted estimates)

## Step 5: Next Steps

Recommend `/ycx-review` for code quality, or switch to Agent mode to implement the design fixes.

## Important Rules

- This is REPORT ONLY — do not change code
- One question at a time for judgment calls
- Anchor every finding in specific files and lines
- If DESIGN.md exists, calibrate against it — don't flag blessed patterns
