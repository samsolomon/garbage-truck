# Helper-Based Hidden Mode Checklist

## Goal

Support `Dock off + menu bar off` by using a Pearcleaner-style background helper and explicit routing into the main app.

## Phase 1: Main App Routing

- [ ] Add a `garbagetruck://` URL scheme in `GarbageTruck/Info.plist`
- [ ] Define explicit routes for:
  - [ ] `garbagetruck://show-list`
  - [ ] `garbagetruck://show-app?path=...`
  - [ ] `garbagetruck://show-app?bundleID=...&name=...` fallback when the app bundle is already gone
- [ ] Parse routes centrally in `GarbageTruck/App/AppDelegate.swift`
- [ ] Add route entry points in `GarbageTruck/App/AppState.swift`
  - [ ] `handleShowListRoute()`
  - [ ] `handleShowAppRoute(appURL:)`
- [ ] Make manual launch route to the list view
- [ ] Make delete-triggered route go to the detail view for the deleted app
- [ ] Validate route handling in a normal packaged app before adding any helper

## Phase 2: Sentinel Helper Target

- [ ] Add a new helper target, e.g. `GarbageTruckSentinel`
- [ ] Keep the helper UI-less and minimal
- [ ] Watch the Trash or deletion source for `.app` removals
- [ ] Ignore `GarbageTruck.app` itself
- [ ] When a deletion is detected, open:
  - [ ] `garbagetruck://show-app?path=...`
  - [ ] fall back to `garbagetruck://show-app?bundleID=...&name=...` if only cached app identity remains
- [ ] Confirm the helper can launch the main app if it is not already running

## Phase 3: Presentation Integration

- [ ] Keep the main app as the single owner of list/detail window state
- [ ] Use `AppPresentationCoordinator` only for showing windows and presentation state
- [ ] Remove hidden-mode assumptions from main-app monitoring logic
- [ ] Decide whether the main app should still run its own `DirectoryMonitor` when the helper exists

## Phase 4: Hidden Mode Enablement

- [ ] Allow `Dock off + menu bar off` in settings once helper routing is proven
- [ ] Preserve current `Dock on` and `menu bar on` modes for users who want them
- [ ] When the app is launched manually from `/Applications` or Spotlight:
  - [ ] show the list view
- [ ] When Smart Delete triggers:
  - [ ] show the deleted app's detail view

## Phase 5: Packaging and Release Validation

- [ ] Validate notarized build from `/Applications`
- [ ] Validate helper starts correctly on login / app launch
- [ ] Validate hidden main app can still be surfaced through routes
- [ ] Validate Smart Delete route from helper into main app
- [ ] Validate manual launch still opens list view when app is already running hidden

## Phase 6: Cleanup

- [ ] Remove temporary hidden-mode reopen experiments that are no longer needed
- [ ] Decide whether `DirectoryMonitor` remains for foreground refresh only
- [ ] Add regression tests around route parsing and route-to-state transitions
