# Dock and Menu Bar Reintroduction Plan

## Goal

Reintroduce menu bar support first, then optional Dock hiding, without reintroducing the packaged-release startup hangs fixed in `v0.1.5`.

## Non-negotiable rules

1. Launch must always begin as a normal Dock app with a standard window scene.
2. No activation policy changes in `AppState.init()`.
3. No invalid state where both Dock and menu bar entry points are disabled.
4. Release builds installed in `/Applications` are the source of truth for validation.

## Scope split

### Milestone 1: menu bar support

- Add menu bar access back while keeping the Dock visible.
- Do not reintroduce Dock hiding in this milestone.
- Do not change the app's activation policy in this milestone.

### Milestone 2: Dock hiding

- Only begin after Milestone 1 ships and remains stable.
- Allow Dock hiding only when the menu bar extra is enabled.
- Prevent users from entering a no-entry-point configuration.

## Architecture

### 1. Separate intent from side effects

- Keep user preferences in `AppState`, but remove presentation side effects from it.
- `AppState` should store intent such as:
  - `wantsMenuBarExtra`
  - `wantsDockIcon`
- `AppState` should also normalize persisted values on launch.

### 2. Add a presentation coordinator

- Introduce a dedicated coordinator, for example `AppPresentationCoordinator`.
- The coordinator owns:
  - menu bar extra lifecycle
  - Dock activation policy changes
  - validation of allowed state combinations
  - re-opening the main window from the menu bar
- `GarbageTruckApp` should create and retain this coordinator.
- `AppState` should not call `NSApp.setActivationPolicy(...)` directly.

### 3. Avoid dynamic top-level scene churn

- Do not start by bringing back a dynamic `MenuBarExtra` SwiftUI scene.
- Prefer an AppKit-backed status item first so lifecycle is explicit and easier to reason about.
- Keep the existing `WindowGroup` and `Settings` scenes stable while presentation changes happen around them.

## Milestone 1 plan: menu bar first

### Code changes

1. Add `AppPresentationCoordinator` under `GarbageTruck/App/` or `GarbageTruck/Services/`.
2. Reintroduce one persisted setting in `AppState`:
   - `wantsMenuBarExtra`
3. Remove stale or unused presentation state that no longer participates in startup.
4. On app launch:
   - always show Dock
   - always launch the main window normally
   - after first window appears, let the coordinator install the menu bar extra if enabled
5. Add menu bar actions:
   - `Open Garbage Truck`
   - `Settings...`
   - `Quit Garbage Truck`
6. Keep main-window activation logic inside the coordinator.

### Settings UX

- Add back only one control first:
  - `Show in menu bar`
- Copy should make the behavior clear:
  - the app still appears in the Dock
  - the menu bar icon is an additional entry point

### Validation checklist

1. Fresh install from DMG to `/Applications`
2. First launch with menu bar disabled
3. Enable menu bar, quit, relaunch
4. Open main window from the menu bar
5. Open settings from the menu bar
6. Reboot or log out/in and relaunch
7. Verify no launch hang in packaged notarized release

### Exit criteria

- Packaged release launches reliably with menu bar support enabled.
- No high-CPU startup loop.
- Main window and settings are reachable from both Dock and menu bar.

## Milestone 2 plan: Dock hiding second

### Preconditions

- Milestone 1 has shipped.
- No startup regressions reported for packaged releases.
- Menu bar open/settings/quit flows are stable.

### Code changes

1. Reintroduce `wantsDockIcon` in `AppState`.
2. Let the coordinator validate combinations before applying them.
3. Apply Dock visibility changes only after launch settles.
4. If the user turns Dock off:
   - require menu bar to be on first
   - if not on, either block the change or auto-enable menu bar before applying it
5. If the user turns menu bar off while Dock is also off:
   - block the action, or
   - automatically restore Dock visibility first

### Settings UX

- Add back `Show in Dock` only after `Show in menu bar` is stable.
- Disable the control when it would create an invalid state.
- Explain why in-line instead of silently failing.

### Validation checklist

1. Launch with Dock on / menu bar off
2. Launch with Dock on / menu bar on
3. Launch with Dock off / menu bar on
4. Toggle Dock off, quit, relaunch
5. Toggle menu bar off while Dock off and verify protection logic
6. Verify app remains reopenable after force quit
7. Verify packaged release from `/Applications`

### Exit criteria

- No invalid hidden state is reachable.
- Packaged builds still launch cleanly.
- Users can always recover the app UI through at least one visible entry point.

## Cleanup before implementation

1. Remove the currently unused `showInDock` and `showInMenuBar` properties from `GarbageTruck/App/AppState.swift`.
2. Remove unused presentation-related keys if they are no longer needed.
3. Add tests around preference normalization and state validation before reintroducing UI.

## Risks to watch

- Release-only behavior differences between Debug and notarized builds
- Scene restoration interacting with presentation changes
- Applying AppKit presentation changes before the first window is stable
- Persisted invalid preferences from older versions

## Recommendation

Implement Milestone 1 in a single focused branch and ship it before touching Dock hiding. Treat menu bar support and Dock hiding as separate features, not as one toggle pair.

## Follow-on Hidden Mode Work

The Pearcleaner-style helper plan for true hidden mode lives in `docs/helper-hidden-mode-checklist.md`.
