# Arrowflow

Arrowflow is a single-player arrow-path puzzle game. Tap or click an arrow to send it straight in the direction it points; the move succeeds only if every cell between it and the edge is clear. Clear every arrow to finish a puzzle. The game includes 100 seeded, solvable levels, level selection, local unlocks and best rewards, undo, hints, restart, a UTC-date daily puzzle, pause, and independent music and sound-effect controls.

## Play controls

- **Mouse or touch:** tap an arrow. A clear arrow slides off the board; a blocked one stays in place and displays a short explanation.
- **H:** highlight a currently movable arrow and its clear lane.
- **Z:** undo the last completed move.
- **R:** restart the current level or daily challenge.
- **Esc:** pause.

Use the **Hint**, **Undo**, and **Restart** buttons below the board on touch devices. Music and sound effects can be toggled from the home screen or pause menu. Progress, best scores, stars, audio preferences, and recent daily completions are stored locally with Godot `user://` storage; no account or server is used.

## Run with Godot

This is the initialized **Godot 2D/Web** project. Open `project.godot` in Godot 4.7 or newer, let the editor import resources, then press **F6** to run the current scene or **F5** to run the project. From a terminal, run `godot --path .` from this directory (replace `godot` with the path to your Godot executable if it is not on `PATH`).

For a browser build, install the matching Godot Web export templates, then run:

```sh
mkdir -p dist
godot --headless --path . --export-release "Web" dist/index.html
python3 -m http.server 8000 --directory dist
```

Open `http://localhost:8000` in a modern browser. The export uses the Godot Web runtime with threads disabled; serve it over HTTP rather than opening `index.html` as a `file://` URL.

## Project modules

- `scripts/arrowflow/level_catalog.gd` — seeded level and daily-puzzle generation, move validation, blocked-arrow detection, and solvability checks.
- `scripts/arrowflow/puzzle_board.gd` — responsive square-board drawing, touch/mouse input, hint/block feedback, and exit animation.
- `scripts/arrowflow/progress_store.gd` — local progression, rewards, settings, and bounded daily history.
- `scripts/arrowflow/main.gd` — home, level selection, puzzle, pause, victory, scoring, and audio controls.
- `tests/test_arrowflow.gd` — bounded engine-side checks for the 100 levels, move logic, daily determinism, and local persistence.

The project was initialized as a Godot game; its gameplay is implemented in GDScript, not as a pure HTML/CSS/JavaScript game. The custom Web loading shell is authored in HTML/CSS/JavaScript.
