# Knife Terminal: Andrew's fork

This is Andrew's own version of Knife Terminal, the terminal he works in all day. He isn't a programmer. He describes what he wants, and Claude changes the code, ships it and installs it. Explain changes in terms of what he'll see, not in code terms.

## Where things are

- Fork: github.com/andrewzstudio/knife-terminal. The branch is `andrew`, which is also the fork's default.
- `upstream` is Eddie's fork, eddieinfinitemachine/knife-terminal. Eddie's releases come from `claude/kind-archimedes-lx7tg5`; his `main` is an old 1.2.30 base, so don't merge it.
- Eddie's fork is CW&T's Knife (cheewee2000/knife-terminal) plus his sidebar work.
- `gh` is at `~/.local/bin/gh`, logged in as `andrewzstudio`.
- `_claude_build/` holds local build output and is git-excluded.

## How a change ships

Xcode 27 is installed on this Mac (since 2026-11-21), so build and install locally. It takes under a minute; GitHub takes 15 to 20.

1. Edit the code on `andrew`. The Mac app is in `apple/macOS/` and the sidebar is mostly in `ContentView.swift`, `Support.swift` and `SidebarFolders.swift`.
2. Bump `MARKETING_VERSION` in `apple/project.yml`, for example from `1.4.34` to `1.4.35`.
3. Build in `apple/`: `xcodegen generate` (at `~/.local/bin/xcodegen`), then
   `xcodebuild build -project KnifeTerminal.xcodeproj -scheme KnifeMac -configuration Release -derivedDataPath ../_claude_build/DerivedData -skipPackagePluginValidation CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS= ENABLE_HARDENED_RUNTIME=NO ONLY_ACTIVE_ARCH=NO KNIFE_FEED_URL="https://raw.githubusercontent.com/andrewzstudio/knife-terminal/andrew/appcast-andrew.xml"`
4. Install with `scripts/install-release.sh "_claude_build/DerivedData/Build/Products/Release/Knife Terminal.app"`. It backs up the current app to `~/.knife/backup/`, quits Knife, swaps the app and reopens it.
   - Quitting Knife ends the Claude session running in it, so tell Andrew before running the script.
   - Tabs and sessions restore themselves after the restart.
5. Commit and `git push origin andrew`. Andrew doesn't need the GitHub build: leave `[release]` out of the message unless he asks for a published release. With `[release]`, `.github/workflows/fork-release.yml` builds and publishes `v<version>-andrew` (watch with `gh run watch <id> -R andrewzstudio/knife-terminal --exit-status`), and `scripts/install-release.sh v<version>-andrew` installs that instead.
6. Batch requests into one build where you can, but don't restart a running build for a new request without asking.
7. To roll back, quit Knife, unzip a backup from `~/.knife/backup/` into `/Applications`, and run `xattr -dr com.apple.quarantine`.

## Constraints

- These builds have no iCloud entitlement, so the iPhone mirror, phone pushes and session invites are off.
- The update feed is the fork's empty `appcast-andrew.xml`, so neither a CW&T nor an Eddie release can replace this build.
- The bundle ID stays `com.cwandt.knifeterminal`, so settings, tabs and the sidebar carry over between builds. Keep it that way.
- To take in later work from Eddie or CW&T, merge their release branch or tag into `andrew`. Don't use their `main`.

## Andrew's sidebar today

- The sidebar layout is stored in the defaults key `knife.projectMeta` (domain `com.cwandt.knifeterminal`) as JSON. Its fields are `byPath`, `order`, `tree.folders` and `tree.place`.
- Everything sits under ★, so it doesn't reshuffle by recent use. The folders mirror his Desktop: `01 OPEN`, `02 TODO`, `03 AZS`, `04 UN` (with sub-levels), `DESKTOP` and `CLAUDE PROJECTS`.
- His wish: the organization should be his, not Eddie's. The fixed sections (review, starred, active, dormant, archived) are Eddie's, and he may want them renamed or removed.
- A project shows up as a shell when its path is a key in `~/.claude.json` under `projects`.
- His conventions:
  - Folder names are ALL CAPS.
  - `NN ` sets the order.
  - `*` means pinned or canonical.
  - `_` marks a system folder.
  - `z_` or `zz` sinks things to the bottom.
