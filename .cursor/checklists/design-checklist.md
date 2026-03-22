# Design Review Checklist

## Frontend File Patterns

Files matching these patterns are considered "frontend" and trigger design review:
- `*.tsx`, `*.jsx`, `*.vue`, `*.svelte`
- `*.css`, `*.scss`, `*.less`, `*.styled.*`
- `*.html` (excluding test fixtures)
- `app/views/**/*`, `templates/**/*`
- `components/**/*`, `pages/**/*`

## HIGH Priority (fix before ship)

### Accessibility
- [ ] All interactive elements keyboard-accessible (Tab, Enter, Escape)
- [ ] `aria-label` on icon-only buttons
- [ ] `alt` text on meaningful images (empty alt on decorative)
- [ ] Color contrast ratio >= 4.5:1 for normal text, 3:1 for large
- [ ] No `outline: none` without a replacement focus indicator
- [ ] Touch targets >= 44x44px on mobile
- [ ] `font-size` >= 16px on mobile `<input>` (prevents iOS zoom)

### Interaction States
- [ ] Loading state for every async operation
- [ ] Error state with clear message AND recovery action
- [ ] Empty state that's designed (not just "No results")
- [ ] Disabled state visually distinct and non-interactive
- [ ] Hover and focus states on interactive elements

### Responsive
- [ ] Layout tested at 375px (mobile), 768px (tablet), 1280px (desktop)
- [ ] No horizontal scroll at any viewport
- [ ] Text readable without zooming on mobile
- [ ] Interactive elements reachable with thumb on mobile

## MEDIUM Priority (should fix)

### Typography
- [ ] Consistent type scale (not ad-hoc font sizes)
- [ ] Line height 1.4-1.6 for body text
- [ ] Maximum ~75 characters per line for readability
- [ ] Headings use semantic hierarchy (h1 > h2 > h3)

### Color & Contrast
- [ ] Uses project's color palette (from DESIGN.md or CSS variables)
- [ ] Color is not the only indicator of state (also use icons, text, borders)
- [ ] Dark/light mode consistency (if supported)

### Spacing & Layout
- [ ] Consistent spacing rhythm (multiples of base unit)
- [ ] Adequate whitespace between sections
- [ ] Alignment follows a visual grid

### Animation
- [ ] Loading indicators for operations > 300ms
- [ ] Page transitions are smooth (no jarring jumps)
- [ ] Respects `prefers-reduced-motion` media query
- [ ] Animations serve a purpose (not decorative noise)

## LOW Priority (nice to have)

### AI Slop Detection
Signs that UI was generated without design intent:
- Default system fonts with no personality
- Purple/gradient-heavy palette without reason
- Centered card stacks with no layout variation
- Generic placeholder content
- Inconsistent border radius, shadow, or spacing
- Every section looks like every other section

### Delight Opportunities
- Meaningful micro-interactions on key actions
- Thoughtful empty states that guide the user
- Celebration moments for completed actions
- Contextual help or tooltips for complex features

## Output Format

For each finding:
```
[HIGH/MEDIUM/LOW] file:line — Problem description
  Current: [what exists now]
  Should be: [what a 10 looks like]
  Fix: [specific recommendation]
  Effort: S/M/L
```
