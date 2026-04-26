# DotZap

A native macOS menu-bar utility that silently watches mounted volumes and auto-deletes
Apple/Windows metadata junk (`._*`, `.DS_Store`, `.Spotlight-V100`, `Thumbs.db`,
`desktop.ini`, …) the moment they appear. Menu bar only — no Dock icon, no main window.

## Build & Run

1. Open `DotZap.xcodeproj` in Xcode 15 or later.
2. Select the **DotZap** target → **Signing & Capabilities**:
   - Set your **Team** (any free Apple ID works).
   - Hardened Runtime is already enabled.
   - The bundle id is `com.Loofa.DotZap` — change if you publish under a different identifier.
3. Build & Run (⌘R).
4. The first build is signed with `Sign to Run Locally` (`-`) by default so it works
   without a team. Switch to `Automatic` signing once you've added your Team.

> **macOS 14 (Sonoma) or later** is required — the project deployment target is 14.0.

## Granting Full Disk Access

DotZap needs Full Disk Access to read every mounted volume.

1. Right-click the menu bar icon to open the settings panel.
2. The **Volumes** tab shows an orange banner if FDA is missing.
3. Click **Open Settings** → enable DotZap in
   **System Settings → Privacy & Security → Full Disk Access**.
4. Return to DotZap and click **Recheck**. The banner disappears once access is granted.

## Using DotZap

| Action | Result |
|---|---|
| **Left-click** menu icon | Pause / resume watching globally |
| **Right-click** (or ⌃-click) | Open / close the floating settings panel |
| Click outside the panel | Close it |
| Toggle a volume | Stop/start watching just that drive |
| Tap a volume row | Expand stats, whitelist editor, and Clean Now |
| Add a custom rule | **Rules** tab → **Add Rule** → name, pattern, match type |
| Clear activity log | **Activity** tab → **Clear** (resets lifetime stats too) |

### Built-in rules

Apple Double (`._*`), `.DS_Store`, `.Spotlight-V100`, `.Trashes`, `.fseventsd`,
`.TemporaryItems`, `__MACOSX`, `Thumbs.db`, `desktop.ini`. All toggleable; none deletable.

### Whitelist

Inside the expanded volume row you can add `fnmatch`-style glob patterns that DotZap
will *never* delete on that volume — useful if a creative app stores files matching
`._*` you actually want to keep.

## Troubleshooting

- **No menu bar icon after launch.** Check Activity Monitor for `DotZap`. If it's running
  but the icon doesn't show, the menu bar may be full — quit other status-bar apps and
  relaunch.
- **Files aren't being deleted.** Make sure Full Disk Access is granted (see above) and
  that the global toggle is on (left-click the icon — sparkle icon should be bright, not
  dimmed). For network volumes, FSEvents fires only after the user explicitly enables
  the volume.
- **Login at Login doesn't appear in System Settings.** macOS may take a few seconds to
  register the new app via `SMAppService`. Open
  `System Settings → General → Login Items & Extensions` and look for DotZap under
  *Open at Login*.
- **App won't launch on a fresh download.** Right-click the `.app` → **Open** the first
  time so Gatekeeper accepts the local signature.

## Project Layout

```
DotZap/
├── DotZapApp.swift           @main + NSApplicationDelegate (.accessory policy)
├── AppState.swift            @MainActor singleton, all state + persistence
├── Core/
│   ├── VolumeWatcher.swift   DiskArbitration mount/unmount handling
│   ├── FSEventsWatcher.swift Per-volume FSEventStream + cleanNow scan
│   ├── FileJanitor.swift     Whitelist-aware deletion
│   └── RuleEngine.swift      exact / prefix / glob matching
├── Models/                   Volume, CleanRule, DeletionEvent (Codable)
├── UI/                       StatusBarController, SettingsPanel, SwiftUI tabs
└── Services/
    └── LoginItemManager.swift  SMAppService.mainApp wrapper
```

## License

Personal / non-commercial use. No telemetry, no updater, no third-party dependencies.
