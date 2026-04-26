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

Because DotZap is licensed under GPLv3 (see [LICENSE](LICENSE)), you're free to modify
and redistribute your own builds — as long as the source for those builds is made
available under the same license.

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

## Auto-updates

DotZap auto-updates via [Sparkle](https://sparkle-project.org). Once an update is
published, you get a non-blocking prompt within 24 hours.

- **Manual check** — right-click the menu bar icon → **About** tab → **Check for
  Updates…**. Skips the daily timer.
- **Disable auto-checks** — toggle off **Automatically check for updates** in the
  same tab. Manual checks still work.
- **Verifying integrity** — every update is EdDSA-signed. The public key is
  embedded in the app at build time; updates that don't verify are rejected.
- **Browse releases** — [github.com/Foiler25/DotZap/releases](https://github.com/Foiler25/DotZap/releases).

## Release process (maintainers)

Each release: bump version → build DMG → write notes → publish.

```bash
# 1. Bump the version in DotZap.xcodeproj/project.pbxproj.
#    Edit MARKETING_VERSION in BOTH the Debug and Release target configs.
#    Use semver (e.g. 1.0.0 → 1.0.1).

# 2. Build the signed DMG. Writes .release-metadata as the handoff file.
./build-dmg.sh

# 3. Smoke-test the DMG (drag-install, launch, About tab shows new version).

# 4. Generate the release notes draft. Writes .release-notes-draft.md.
./release-github.sh

# 5. Have Claude turn the draft into RELEASE_NOTES.md (user-facing prose
#    grouped under New / Fixed / Changed; commits since the previous tag).

# 6. Publish: tags v$VERSION, pushes, creates the GitHub Release with the
#    DMG attached, appends an <item> to appcast.xml, commits + pushes.
./release-github.sh --publish
```

The two scripts pass state via `.release-metadata` (build commit, SHA-256, DMG
size, Sparkle signature line). That file is gitignored and removed by Phase 2 on
success.

## One-time setup (per maintainer machine)

```bash
# Required CLI tools
brew install create-dmg gh
gh auth login                                    # one-time GitHub auth

# Sparkle EdDSA keys
# The private key for DotZap lives in the macOS Keychain under the
# 'dotzap' account. To move to a new machine, copy keyfile.txt into the
# repo root (gitignored) — build-dmg.sh prefers it over the keychain.
# To regenerate keys from scratch (only do this if you've lost the
# existing key — it'll invalidate every published release for old users):
xcodebuild -project DotZap.xcodeproj -scheme DotZap -resolvePackageDependencies
GENERATE_KEYS="$(ls -1 ~/Library/Developer/Xcode/DerivedData/DotZap-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys | head -1)"
"$GENERATE_KEYS" --account dotzap                # generates new keypair
"$GENERATE_KEYS" --account dotzap -x keyfile.txt # exports private key locally
"$GENERATE_KEYS" --account dotzap -p             # prints public key
```

After regenerating, paste the printed public key into `build-dmg.sh`
(`SPARKLE_PUBLIC_EDKEY=`) and rebuild. **Keep `keyfile.txt` offline** — back it up
to a password manager. Losing it means losing the ability to ship signed updates
with the existing keypair; leaking it means an attacker can forge updates for
existing installs.

## License

DotZap is licensed under the [GNU General Public License v3.0](LICENSE).
