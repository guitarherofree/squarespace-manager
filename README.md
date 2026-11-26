# Website

A personal macOS app for previewing, tracking and (in later versions) visually editing freemanedwards.com, a Squarespace site. Not affiliated with Squarespace.

## Install (once)

1. Download `Website-<version>-mac-arm64.zip` from the [latest release](https://github.com/guitarherofree/squarespace-manager/releases/latest).
2. Open the zip and drag **Website** into Applications.
3. Open it. macOS says it can't check the app for malicious software, because it isn't signed with an Apple Developer ID. Go to **System Settings → Privacy & Security**, click **Open Anyway** next to Website, and confirm. You only do this once.

## Updates

Website updates itself from this repository's GitHub releases:

- It checks shortly after it opens and then once a day, and downloads new versions in the background.
- A bar at the top of the window says when a new version is ready. **Restart Now** installs it straight away; otherwise it installs when you quit.
- **Website › Check for Updates…** checks right away and shows the release notes.
- Settings › Updates turns automatic checks and downloads on or off and shows the log (`~/Library/Logs/Website/update.log`).
- Before installing, the app checks the download against the SHA-256 checksum GitHub publishes, confirms it is Website at the expected version, and verifies its code signature. The previous version is kept in `~/Library/Application Support/Website/Updates/Previous` in case you need to go back.

The repository is public, so no GitHub token is needed. If it ever becomes private, paste a read-only token in Settings › Updates.

## Releasing an update

1. Add a section at the top of `CHANGELOG.md`:
   ```md
   ## 0.3.0
   - What changed
   ```
2. Push to `main`.

The **Release** workflow builds the app on an Apple silicon Mac, signs it ad hoc, and publishes `Website-0.3.0-mac-arm64.zip` with that section as the release notes. Installed copies pick it up on their next check. You can also run the workflow by hand from the **Actions** tab, or push a `v0.3.0` tag.

## What it does today

- Connects to a site by address and detects the Squarespace version (7.0 or 7.1) and template.
- Live preview at desktop, tablet and mobile widths.
- Snapshots of every page's content, markup and the site's CSS, saved in `~/Library/Application Support/Website`, with a list of what changed since the previous snapshot.

| Milestone | Status |
| --- | --- |
| 1. Foundation: site connection, snapshots, updates | Done |
| 2. Inspector: element selection, layers, search | Next |
| 3. Style layer: drafts, previews, publishing, rollback | Planned |
| 4. Hand-off editing for content, outside-change detection | Planned |
| 5. AI assistant | Planned |
| 6. Site health dashboard | Planned |
| 7. Full test pass | Planned |

## How it's built

- `App/` – the SwiftUI app.
- `Packages/SiteKit/` – site reading, detection, snapshots and diffs.
- `Packages/GitHubReleaseUpdater/` – the in-app updater, shared in the same form by Freeman's other Swift apps.
- `branding/icon.svg` – the icon; `scripts/make_icons.sh` renders it into the app's icon set.
- `project.yml` – the Xcode project, generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen && xcodegen`).
- `.github/workflows/ci.yml` builds and tests every push; `release.yml` publishes releases.

Run the tests with `swift test --package-path Packages/SiteKit` and `swift test --package-path Packages/GitHubReleaseUpdater`.
