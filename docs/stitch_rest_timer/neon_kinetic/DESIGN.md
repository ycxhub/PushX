# Design System Specification: Neon Kinetic (Pushup Performance Edition)

## 1. Overview & Creative North Star
**Creative North Star: "The Obsidian Laboratory"**
This design system moves beyond "fitness tracking" into the realm of high-performance calibration. It treats the human body as a precision machine. The aesthetic is "Neon Kinetic"—a high-contrast, dark-mode-first interface that pairs the cold, technical precision of Apple’s native San Francisco typography with the electric energy of `#00E5FF` (Electric Blue).

To break the "standard app" feel, we employ **Kinetic Asymmetry**. Layouts should not feel like static grids; they should feel like data in motion. We use extreme typographic scales—massive display numbers for rep counts contrasted against tiny, razor-sharp micro-labels—to create an editorial feel that is both authoritative and aggressive.

---

## 2. Colors: The Charcoal & Electric Palette
The palette is rooted in `surface` (#0e0e0e), creating a "void" where only the most vital pushup metrics survive.

*   **Primary Kinetic:** `primary` (#81ecff) and `primary_container` (#00e3fd) are reserved for "Active State" energy—the moment of the push.
*   **The "No-Line" Rule:** Sectioning must never use 1px solid borders. Boundaries are defined by shifting from `surface` to `surface_container_low` (#131313) or `surface_container` (#1a1a1a). If a section ends, it fades; it doesn't "stop."
*   **Surface Hierarchy:** Use `surface_container_highest` (#262626) for interactive cards and `surface_container_lowest` (#000000) for inset "well" areas like training logs.
*   **Glass & Gradient Rule:** For primary CTAs (e.g., "Start Set"), use a subtle linear gradient from `primary` to `secondary_dim`. For floating navigation, use `surface_bright` at 60% opacity with a `24px` backdrop blur to create a "Frosted Obsidian" effect.

---

## 3. Typography: The San Francisco High-Contrast Scale
We have transitioned to **San Francisco (System UI)** to lean into a "Pro Tools" aesthetic. It is crisp, neutral, and high-performance.

*   **Display (The Metrics):** `display-lg` (3.5rem) is used exclusively for live rep counts and "Time Under Tension." It should be Bold or Heavy to anchor the screen.
*   **Headline (The Focus):** `headline-md` (1.75rem) defines the pushup variation (e.g., *Diamond*, *Plyometric*, *Weighted*).
*   **Label (The Technicals):** `label-sm` (0.6875rem) is used for technical data like "Elbow Angle" or "Scapular Protraction." These should be Uppercase with `0.05rem` letter spacing for an architectural feel.
*   **Body:** `body-md` (0.875rem) is for coaching cues. Keep sentences short and instructional.

---

## 4. Elevation & Depth: Tonal Layering
Traditional shadows are prohibited. Depth is achieved through light, not shadow.

*   **The Layering Principle:** Stack `surface_container_low` as the base, `surface_container` for the module, and `surface_container_high` for the interactive element within that module.
*   **Ambient Glow:** Instead of a drop shadow, "active" elements (like a currently active set) may use an `8%` opacity outer glow using the `primary` (#81ecff) color with a `32px` blur.
*   **The "Ghost Border" Fallback:** If a tactile edge is needed for accessibility, use the `outline_variant` (#484847) at **15% opacity**. It should feel like a faint reflection on a glass edge, not a drawn line.

---

## 5. Components: Pushup-Specific UI

### Buttons (Kinetic Triggers)
*   **Primary:** High-contrast `primary` background with `on_primary` text. No rounded corners beyond `md` (0.375rem) to maintain a sharp, aggressive look.
*   **Tertiary:** Text-only with `primary` color, used for secondary actions like "View Form Video."

### Progress Rings & Gauges
*   **The Power Arc:** Use the `secondary` (#10d5ff) token for progress bars. For "Failure Point" indicators, transition the stroke to `error` (#ff716c) using a sharp gradient.

### Lists & Cards (The Training Log)
*   **Strict No-Divider Policy:** Never use horizontal lines. Separate training sessions using `12` (3rem) vertical spacing or a shift from `surface` to `surface_container_low`.
*   **Content:** Each card must focus on pushup metrics: *Volume, Intensity (kg), Tempo (seconds).*

### Input Fields (Calibration)
*   **States:** Resting state uses `surface_variant`. Focus state glows with a `primary` "Ghost Border."
*   **Helper Text:** Always technical. Instead of "Enter weight," use "Additional Load (kg)."

---

## 6. Do’s and Don'ts

### Do:
*   **Use Pushup Terminology:** Use "Full Lockout," "Chest-to-Floor," "Explosive Phase," and "Eccentric Control."
*   **Maintain Asymmetry:** Align display typography to the left and labels to the right to create visual tension.
*   **Embrace the Dark:** Keep 90% of the UI in the `surface` to `surface_container` range to make the `primary` electric blue pop with "kinetic" energy.

### Don't:
*   **No General Fitness:** Never reference "calories," "steps," or "squats." This is a specialized instrument for pushup mastery.
*   **No "Soft" Shapes:** Avoid `full` (9999px) roundedness for buttons. We want precision, not "friendliness." Use `md` (0.375rem) or `lg` (0.5rem) maximum.
*   **No Standard Dividers:** If you feel the need to "separate" two items, use white space (Scale `6` or `8`) instead of a line.

---

## 7. Spacing & Rhythm
Use a strict **4px baseline grid**.
*   **Container Padding:** Scale `5` (1.25rem) for mobile edges.
*   **Vertical Rhythm:** Scale `10` (2.5rem) between major training blocks.
*   **Micro-spacing:** Scale `1.5` (0.375rem) between a label and its metric.