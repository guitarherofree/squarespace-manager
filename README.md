# Squarespace Manager

A personal macOS app for previewing, tracking and (in later versions) visually editing a Squarespace website. Not affiliated with Squarespace.

## Install

1. Open the [latest release](https://github.com/guitarherofree/squarespace-manager/releases/latest) and download `SquarespaceManager-<version>.zip`.
2. Open the zip and drag **Squarespace Manager** into Applications.
3. Open it. The first time, macOS says it can't check the app for malicious software, because it isn't signed with an Apple Developer ID. Go to **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to Squarespace Manager, and confirm.

After that, the app updates itself. It checks GitHub daily; you can also choose **Check for Updates…** in the app menu.

## What it does today (0.1)

- Connects to a site by address and detects the Squarespace version (7.0 or 7.1) and template.
- Live preview at desktop, tablet and mobile widths.
- Snapshots of every page's content, markup and the site's CSS, saved in `~/Library/Application Support/Squarespace Manager`, with a list of what changed since the previous snapshot.

## Plan

The design and its limits are written up in the project's feasibility and architecture doc. In short: style and code changes are edited and published from the app; native content (text, images, blocks) is drafted in the app and finished in Squarespace's own editor, because Squarespace has no API for writing content.

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
- `Packages/SiteKit/` – site reading, detection, snapshots and diffs, with unit tests (`swift test --package-path Packages/SiteKit`).
- `project.yml` – the Xcode project, generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`xcodegen generate`).
- `.github/workflows/ci.yml` – builds and tests every push.
- `.github/workflows/release.yml` – on a `v*` tag, builds a universal app, signs the zip for [Sparkle](https://sparkle-project.org) and publishes a release with `appcast.xml`.

### Update signing

Updates are verified by Sparkle with an Ed25519 key. The public half is `SUPublicEDKey` in `project.yml`; the private half is the repository secret `SPARKLE_ED_PRIVATE_KEY`. If that secret is ever lost, installed copies can't verify new updates and need one manual download of a build with a new key.
