<p align="center">
  <img src="Slapped/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="120" alt="Slapped app icon">
</p>

<h1 align="center">Slapped</h1>

<p align="center">
  <b>Find stickers in the wild. Scan them. Trade them.</b><br>
  Untappd, but for the stickers on lamp posts, signs and skateparks.
</p>

<p align="center">
  <a href="https://github.com/UglyError/slapped/actions/workflows/build-ios.yml"><img src="https://github.com/UglyError/slapped/actions/workflows/build-ios.yml/badge.svg" alt="Build"></a>
  <img src="https://img.shields.io/badge/iOS-17%2B-black" alt="iOS 17+">
  <img src="https://img.shields.io/badge/SwiftUI-FFC100?logo=swift&logoColor=black" alt="SwiftUI">
  <img src="https://img.shields.io/badge/Supabase-3ECF8E?logo=supabase&logoColor=white" alt="Supabase">
</p>

---

## How it works

1. **Spot** a sticker out in public.
2. **Scan** it. The app cuts it out of the background on your phone.
3. **Log** it with a name. It's pinned to the map where you found it. Each sticker can only be logged once per spot, so be first.
4. **Trade** it. Offer your stickers for other hunters' stickers. Popular, well-traded stickers are worth more **clout**.

## Features

| | |
| --- | --- |
| 📸 **Scan** | Camera → instant cut-out → name → GPS-tagged |
| 🗺️ **Map** | Every logged sticker as a pin, worldwide |
| 🧭 **Explore** | Trending, near you, fresh finds, top hunters, search |
| 🔁 **Trade** | Multi-sticker offers with a live clout balance |
| 📰 **Feed** | Friends / everyone, props, comments |
| 🔔 **Activity** | Props, comments, follows and trade offers |
| 🏅 **Badges** | 12 Untappd-style badges for hunting, trading and exploring |
| 🛡️ **Safety** | Report, block, auto-hide reported content, delete account |

## Install (testing)

Every push to `main` builds the app on GitHub. No Mac needed.

1. Open the [latest successful build](https://github.com/UglyError/slapped/actions/workflows/build-ios.yml?query=branch%3Amain+is%3Asuccess) → **Artifacts** → download **Slapped-ipa** and unzip it.
2. Install it with [Sideloadly](https://sideloadly.io) on Windows or Mac, using your Apple ID.
3. On the iPhone, turn on **Settings → Privacy & Security → Developer Mode** and trust your Apple ID under **General → VPN & Device Management**.

Free Apple IDs expire sideloaded apps after 7 days. Re-run Sideloadly to refresh.

## Release

App Store / TestFlight steps are in **[docs/RELEASE.md](docs/RELEASE.md)**. After the one-time setup, it's a single **Release to TestFlight** button in the Actions tab.

## Tech

- **App**: SwiftUI (iOS 17+), MapKit, Vision subject lifting, [supabase-swift](https://github.com/supabase/supabase-swift)
- **Backend**: Supabase. Postgres + PostGIS, Auth, Storage, with row-level security on every table. Important writes (logging stickers, trades, reports) run as server-side SQL functions.
- **Duplicate detection**: a perceptual hash of each sticker (checked at 4 rotations) plus a 30 m radius
- **Builds**: GitHub Actions on macOS runners, with [XcodeGen](https://github.com/yonaskolb/XcodeGen) generating the Xcode project

## Setting up your own backend

1. Create a project at [supabase.com](https://supabase.com).
2. **SQL Editor**: run [`0001_init.sql`](supabase/migrations/0001_init.sql), then [`0002_social_moderation.sql`](supabase/migrations/0002_social_moderation.sql).
3. **Authentication → URL Configuration**: set Site URL to `slapped://auth-callback` and add `slapped://**` to Redirect URLs.
4. Put your Project URL and anon key in `AppConfig` in [`SlappedApp.swift`](Slapped/App/SlappedApp.swift).

## Project layout

```
Slapped/
  App/            entry point, config, session state, tab bar
  Models/         data models
  Services/       Supabase API, sticker cut-out + hashing, location
  Views/          feed, explore, scan, map, profile, trades, comments, settings
supabase/migrations/   database schema, security rules, server functions
docs/             terms, privacy policy, release guide
.github/workflows/     build (every push) and TestFlight release (manual)
project.yml       XcodeGen project definition
```

## Legal

[Terms of Use](docs/terms.md) · [Privacy Policy](docs/privacy.md) · [Report a problem](https://github.com/UglyError/slapped/issues)
