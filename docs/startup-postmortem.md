# Startup Hang Postmortem

## What happened

Early packaged releases could hang on launch with a spinning beach ball, high CPU, and rapidly growing memory.

## Root causes

1. `GarbageTruck/App/AppState.swift` did too much work during launch.
   - App discovery immediately kicked off a global leftover-file index build.
   - It also precomputed per-app leftover sizes across the whole app list.
   - That made first launch CPU-heavy before the UI became responsive.

2. `GarbageTruck/Views/MainView.swift` applied hidden window toolbar styling that triggered a release-build SwiftUI/AppKit appearance loop.
   - This did not show up clearly in the initial code review because the packaged app behaved differently from local debug runs.

3. App startup scenes were too dynamic for a first release.
   - The app combined a regular window scene, persisted Dock and menu bar visibility settings, activation policy changes, and a `MenuBarExtra` scene.
   - In practice that made release startup brittle and much harder to reason about.

## What fixed it

1. Removed launch-time global indexing and eager leftover-size computation.
2. Removed the hidden toolbar background customization.
3. Simplified startup scenes to a normal app window plus settings.
4. Deferred expensive cleanup work to per-app scans.

## What we learned

- Keep launch work to the minimum needed to render the first window.
- Treat packaged release behavior as its own test surface; local debug builds are not enough.
- Avoid mixing window scene, menu bar scene, and activation policy changes until the basic launch path is stable.
- Prefer explicit, on-demand scanning over global eager precomputation.

## Safer menu bar reintroduction plan

1. Reintroduce menu bar support as a separate milestone after startup remains stable for multiple releases.
2. Keep the main app a regular Dock app by default.
3. Add a menu bar extra only when a single explicit setting enables it.
4. Do not switch `NSApp` activation policy during `AppState` initialization.
5. Do not allow an invalid hidden state where both Dock and menu bar entry points are disabled.
6. Move menu bar state handling behind a dedicated coordinator that owns:
   - insertion/removal of the menu bar extra
   - Dock visibility changes
   - validation of allowed combinations
7. Add a regression checklist for packaged builds:
   - first launch from `/Applications`
   - relaunch with saved preferences
   - launch from DMG-mounted app
   - launch with menu bar enabled
   - launch with Dock hidden and menu bar enabled
