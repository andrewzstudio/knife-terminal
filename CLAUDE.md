# Knife Terminal: Andrew's fork

This is Andrew's own version of Knife Terminal, the terminal he works in all day. He isn't a programmer. He describes what he wants, and Claude changes the code, ships it and installs it. Explain changes in terms of what he'll see, not in code terms.

## Where things are

- Fork: github.com/andrewzstudio/knife-terminal. The branch is `andrew`, which is also the fork's default.
- `upstream` is Eddie's fork, eddieinfinitemachine/knife-terminal. Eddie's releases come from `claude/kind-archimedes-lx7tg5`; his `main` is an old 1.2.30 base, so don't merge it.
- Eddie's fork is CW&T's Knife (cheewee2000/knife-terminal) plus his sidebar work.
- `gh` is at `~/.local/bin/gh`, logged in as `andrewzstudio`.
- This Mac has no Xcode. Builds run on GitHub.

## How a change ships

1. Edit the code on `andrew`. The Mac app is in `apple/macOS/` and the sidebar is mostly in `ContentView.swift`, `Support.swift` and `SidebarFolders.swift`.
2. Bump `MARKETING_VERSION` in `apple/project.yml`, for example from `1.4.33` to `1.4.34`. A release is only made for a version that has no release yet.
3. Commit with `[release]` in the message and `git push origin andrew`.
4. `.github/workflows/fork-release.yml` builds an ad-hoc-signed app on a GitHub macOS runner. It runs the KnifeKit tests, compiles the iOS app, smoke-tests the Mac app, and publishes the release `v<version>-andrew`. Watch it with `gh run watch <id> -R andrewzstudio/knife-terminal --exit-status`. It takes about 15 to 20 minutes.
5. If the build fails, read the log with `gh run view <id> --log-failed`, fix the problem, and push again.
6. Install with `scripts/install-release.sh v<version>-andrew`. The script downloads and verifies the build and backs up the current app to `~/.knife/backup/`. It then quits Knife, swaps the app and reopens it.
   - Quitting Knife ends the Claude session running in it, so tell Andrew before running the script.
   - Tabs and sessions restore themselves after the restart.
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
