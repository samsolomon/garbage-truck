# CLAUDE.md

## Build & Test

```bash
xcodebuild -scheme GarbageTruck -destination 'platform=macOS' build
xcodebuild -scheme GarbageTruck -destination 'platform=macOS' test
```

## Design Principles

- **No external dependencies.** This project uses only Apple frameworks. Don't add SPM packages without discussion.
- **Not sandboxed on purpose.** The app needs broad `~/Library` access to scan for leftover files. Don't re-enable sandboxing.
