# Moss

Moss is a native macOS desktop-pet starter app. He wanders randomly around the screen, turns inward when he reaches a screen edge, plays the preserved reminder animation when clicked, and conjures a softly floating small checklist. Clicking the small checklist expands it into a real interactive task panel.

## Run

Requirements: macOS 14 or later and Xcode 16 or a compatible Swift 6 toolchain.

```sh
swift run
```

To build a double-clickable local app bundle:

```sh
./scripts/package_app.sh
open dist/Moss.app
```

To build the optimized universal release bundle for both Apple silicon and
Intel Macs:

```sh
./scripts/package_release.sh
open dist/release/Moss.app
```

The release build also writes `dist/release/Moss.dSYM` for crash diagnosis.

## Versioning and bundle metadata

App identity and version values are centralized in `Config/AppMetadata.sh`.
Update `MOSS_MARKETING_VERSION` for a user-visible release and increment
`MOSS_BUILD_NUMBER` for every distributed build. Both development and universal
release bundles use the same metadata and app icon.

## Controls

- Click Moss quickly to play the reminder animation.
- Once the small checklist appears, click Moss or the checklist to expand the full task panel. If untouched, it disappears after 2.7 seconds and Moss resumes walking.
- Press and drag Moss to pick him up by his cloak, move him, and drop him with a soft squash.
- Click the small conjured checklist to open the interactive list.
- Drag Moss to reposition him.
- Right-click Moss to replay the reminder or quit.

## Project layout

- `assets/concepts/` contains the locked visual references.
- `Sources/Moss/Resources/moss-reminder.png` is the transparent reminder sprite sheet.
- `Sources/Moss/Resources/moss-walk.png` is the four-frame transparent side-walk cycle, flipped at runtime for leftward travel.
- `Sources/Moss/Resources/moss-walk-up.png` is the matching rear-view cycle used for primarily upward movement.
- `Sources/Moss/Resources/moss-walk-down.png` is the matching front-view cycle used for straight downward movement.
- `Sources/Moss/Resources/moss-land.png` is the dedicated release-and-landing animation used after dragging.
- `Sources/Moss/Resources/moss-happy.png` is the raised-hands delighted idle loop.
- `Sources/Moss/Resources/moss-sleep.png` is the curled sleeping/breathing idle loop.
- `Sources/Moss/Resources/moss-wake.png` is the click-to-nudge sleepy wake-up sequence.
- `PetView.swift` handles sprite animation and interaction.
- `PetWindowController.swift` handles the floating transparent desktop window and wandering behavior.
- `TaskPanelWindowController.swift` provides the expanding interactive task panel.

The starter now uses a dedicated four-frame walk cycle. A later production pass can add equally aligned sleep and delighted animation strips without changing the window or task-panel architecture.
