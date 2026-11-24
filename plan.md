# Arrowflow — implementation and design plan

## Product and implementation approach

Arrowflow is a single-player, offline arrow-path puzzle game delivered through the initialized Godot Web project. The 2D board is the authoritative game state. Players tap/click an arrow; it leaves only when every grid cell between its head and the board edge is free of live arrows and any fixed blocker. Levels are generated deterministically from the level number (or UTC date for the daily challenge), then validated by simulating a complete removal order before display. The reverse-placement generator guarantees a constructive solution; an independent solver validates it and a safe fallback prevents a deadlocked layout. A static blocker is only placed where no required ray intersects it. Difficulty scales board side, arrow count, and blocker density across 100 levels.

The project is initialized as a 2D Godot Web game. The gameplay, persistence, rendering, input and screen flow will therefore be implemented in organized GDScript modules and exported to the browser; the requested web behavior (including responsive/touch input) remains the goal, and the authored Web loading shell uses HTML, CSS and JavaScript. This is not a pure HTML/CSS/JavaScript core implementation.

The initial project uses no server, database, accounts, remote APIs or copyrighted game assets. Progress/settings/daily completion persist locally through Godot's `user://` storage (IndexedDB in a Web build). The existing `GameAudio` and browser BGM adapter will be reused for licensed-template music and cues; only relevant cue methods are used. The template's game-specific presentation and gameplay are replaced, while unused source assets and starter references are retained.

## Project structure

- `project.godot`: set the game identity, startup/splash colors, responsive Web-friendly viewport and custom favicon.
- `scenes/main.tscn`: sole launch scene, re-bound to Arrowflow's main controller.
- `scripts/arrowflow/main.gd`: screen routing (home, level select, puzzle, pause, victory), UI construction, input orchestration, score/stars, animation completion and audio settings.
- `scripts/arrowflow/level_catalog.gd`: deterministic 100-level definitions, seeded arrow/obstacle generation, solvability checks, next-move search and daily seed.
- `scripts/arrowflow/puzzle_board.gd`: responsive square-board vector renderer, touch/mouse picking, blocked/selected/hint feedback, and arrow-exit animation.
- `scripts/arrowflow/progress_store.gd`: bounded local save for unlocked level, level stars/best scores, settings, and date-keyed daily result.
- `tests/test_arrowflow.gd`: bounded engine-side checks for level generation, solution validation, move blocking, removal, progression bounds and persistence encoding.
- `ui/web/godot.html`, `ui/web/loader-fonts.css`, and `ui/web/loader-fonts.json`: authored, title-consistent loading shell, progress/error/retry behavior, responsive styling and embedded game favicon. Rebuild generated `ui/web/shell.html` through the existing tool; do not edit it directly.
- `assets/share/favicon.png` and `game-sharing.json`: compact, original Arrowflow icon and accurate title/description metadata. No separate cover art is needed for the playable loop; share artwork follows the saved production rules.
- `README.md`: concise project run/export instructions and player controls.
- `TODO.md`: independently deliverable outcome groups and the complete source acceptance clauses.

No new runtime dependencies or online services are required. The existing Godot Web export preset and project tooling remain the serving/export mechanism; the playable export is `dist/index.html` plus the generated adjacent Web assets.

## Design

Three distinct style directions sampled from the low-probability tails: **Sunlit vector arcade** (0.08, chosen), **Ink-and-paper puzzle atelier** (0.05), and **Midnight signal neon** (0.07). The selected direction is expanded below.

- **Design Movement:** contemporary playful vector arcade—like a compact tabletop puzzle cabinet, with editorial spacing and tactile controls rather than copied game branding.
- **Core Principles:** readable paths at a glance; color plus direction/shape carries meaning; keep the board dominant and uncluttered; acknowledge every action with restrained visual/audio feedback.
- **Color Philosophy:** warm chalk/ivory backgrounds create calm, deep blue-ink text keeps contrast high, and citrus lime, coral, sky and marigold distinguish pieces without making color the only cue. Blockers remain dark and visibly separate from movable pieces.
- **Layout Paradigm:** a flexible vertical play frame, with compact level/progress information above a centered square board and three generous utility controls below. Home and level select use a centered responsive card; on narrow viewports the board claims the available width and supporting controls stack or compress.
- **Signature Elements:** rounded arrow lozenges with a custom geometric arrow glyph; thin dotted exit-lane marks that subtly brighten on hint; small starburst reward marks at completion.
- **Interaction Philosophy:** a move is a direct tap, not a drag. Clear arrows glide outward; blocked taps nudge once and explain why. Hint identifies one currently safe arrow, undo restores the exact previous board, and restart restores the authored/generated initial state.
- **Animation:** quick ease-out arrow exits (about 0.2–0.3 seconds), a short lateral nudge for blocked moves, a modest pulsing hint, and a brief star reveal at victory. Keep all feedback bounded and never delay input or obscure lane logic.
- **Typography System:** use the project's bundled Nunito UI family for readable labels and controls, with the bundled bold UI face for the Arrowflow wordmark and short headings. Numbers remain tabular/readable; all copy is live text.
- **Brand Essence:** a bright, thoughtful path-clearing puzzle for short focused sessions; personality: **clear, lively, rewarding**.
- **Brand Voice:** concise, friendly prompts—“Clear a path. Find your flow.” and “This lane is blocked—try another arrow.”
- **Wordmark & Logo:** live-text “ARROWFLOW” beside a four-direction tile mark drawn from original vector arrows; no rasterized text or borrowed logo.
- **Signature Brand Color:** **Flow Lime `#C8EF68`**, reserved for primary actions and successful path highlights.
