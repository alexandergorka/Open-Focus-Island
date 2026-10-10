# Open Focus Island

Open Focus Island is a native macOS focus timer with a compact top-of-screen control and a menu-bar entry.

## Current features

- Start a focus or break session, with an optional task name.
- Expand the compact island to pause, resume, finish, or skip to a break.
- Smoothly expand and collapse the island in 280 ms, with a shared surface that changes size and corner rounding while the contents fade. macOS **Reduce motion** uses immediate transitions.
- Change focus, short-break, and long-break durations in settings.
- Open settings in the menu-bar popover using **Show settings** / **Hide settings** (German: **Einstellungen anzeigen** / **Einstellungen ausblenden**). The full heading row is clickable. The floating timer controls contain only session actions.
- Switch **Notch mode** on or off in settings. The choice is saved immediately; disabling it uses the floating display on every screen. Enabling it reconnects the panel to a supported notch.
- The compact notch status uses the measured notch width, a shallow strip with rounded bottom corners, and a visible countdown. Click the status or countdown to open the timer view; drag the status dot to detach the panel.
- Choose **English** or **Deutsch** under **Language** in settings. The choice is saved immediately and applied without a relaunch. Notifications, error messages, and history dates follow the selected language; a pending end-of-session notification is rescheduled in the new language, while an error message already shown keeps its text until it is next updated. System dialogs, such as the notification permission request, and system error texts follow the macOS system language.
- Open a separate, resizable **History** window using the history icon to the right of **Quit** in the menu-bar popover. It shows naturally completed focus sessions, updates live, and reuses the same window when opened again. Manual finishes and breaks are not included.
- Keep settings, the current session, and history locally in UserDefaults.
- Reconcile remaining time from session timestamps after sleep, app suspension, or relaunch. A focus session that expired while the app was closed is recorded on the next launch.
- Opt in to a local macOS notification at the end of a session. The app asks for notification permission only after you enable the setting.
- Enable optional completion sounds: F1 for focus and B5 for either break. Live completions play once within five seconds of the deadline. With notifications enabled, the system notification sound takes precedence; restore and older completions stay quiet.
- Place the island on the screen with the foreground app's topmost normal window. If that window cannot be determined, the app falls back to the main screen. The current MVP does not offer a monitor picker.

Default durations are 25 minutes for focus, 5 minutes for a short break, and 15 minutes for a long break. Notifications and app completion sounds are off by default. English is the default language, including for existing installations without a saved language.

After four fully elapsed focus sessions, the app recommends a long break. Every new session starts with a user action. Running sessions continue across relaunch; paused sessions remain paused.

The compact, timer and controls views share one animated background. Contents are measured at their final size to avoid resize feedback during animation; the transparent native window stays large enough to show the outgoing surface until collapse completes. Quick reversals replace the previous resize target, and dragging or changing displays cancels it. Timer ticks and dragging stay immediate.

The menu-bar popover grows and shrinks with its settings form. Oversized floating timer controls remain scrollable within the available screen area. Dragging from the status dot preserves the position on the same display and resets it when the active app moves to another display. Notched displays have connected compact-status, timer and controls views; the status distinguishes running, the last minute, paused and completed sessions.

The UI split preserves the panel animations and completion sounds. The integrated suite passes 183 tests; its local release passes signature, bundle and audio checks. Tests cover real AppKit/SwiftUI hosting windows, settings interactions and persistence, history lifecycle/live updates, rendered interpolation, rapid reversals and reduced motion. The restarted main app confirms the simplified controls, collapse and Escape. Earlier native QA covered notch expansion, drag detachment, display switching and sound completion. The new system popover and history focus still require final native verification; physical display unplugging, VoiceOver and actual sleep/wake remain unverified. F1/B5 assets, backward-compatible settings and completion playback are independently reviewed. Both sounds and their manifest are included before signing and audited from the final app bundle. Perceived audibility and subjective sound quality remain unverified. Apple Focus automation is deferred in `TODO.md`.

## Requirements

- macOS 14 or later
- Swift 6 toolchain (Xcode command-line tools or Xcode)

## Build, test, and run locally

```sh
swift build
swift test
./scripts/build-app.sh
./scripts/check-app-bundle.sh
open ".build/Open Focus Island.app"
```

`build-app.sh` creates an app bundle for the current machine in `.build/Open Focus Island.app`. The script builds the release executable, includes the app icon and selected completion sounds with their manifest, sets bundle version `0.1.0` / build `1`, and applies an ad-hoc local signature. `check-app-bundle.sh` checks the bundle structure, plist values, icon format, signature, and the bundled sounds’ hashes, decoded audio and technical limits.

The ad-hoc signature is for local use. This project has not been signed with an Apple Developer ID or notarized for distribution. No public release or Homebrew Cask is provided. Licensed under the [MIT License](LICENSE).

## Product direction

The app is an original implementation and uses its own name, icon, layout, copy, and code. It does not include accounts, telemetry, network access, cloud sync, music controls, dictation, translation, calendar, weather, system HUDs, AI progress, app blocking, or device sync.
