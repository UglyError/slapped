# Slapped

**Releasing to the App Store: see [docs/RELEASE.md](docs/RELEASE.md).**

Untappd for stickers. Find a sticker in the wild, scan it, and the app cuts it off the background. Name it, tag where you found it, and it goes into your collection. Then trade stickers with other hunters.

- **Scan**: camera or photo → on-device subject cutout (Vision) → name + notes → GPS + reverse-geocoded spot name → logged.
- **No double-logging**: each sticker gets a perceptual hash. The server rejects a scan if a near-identical sticker (any of 4 rotations) is already logged within 30 m. It checks before upload and again atomically when the sticker is created.
- **Feed**: Untappd-style check-in cards (Everyone / Friends), with props (likes).
- **Explore**: Trending this week, Near you (5 km), Fresh finds, Top hunters, and search across stickers, places and users.
- **Map**: every logged sticker as a pin; it loads whatever region you're looking at.
- **Profiles**: Collection (stickers you own) vs Finds (stickers you scanned), stats, follow.
- **Trading**: pick any of their stickers and any of yours, then send an offer. They accept or decline. Accepting swaps ownership atomically, records trade history, and auto-cancels other open offers that involve those stickers.
- **Social**: comments, an activity feed (props, comments, follows, trade offers) and Untappd-style badges.
- **Safety**: report stickers, comments and users (3 reports auto-hide), block users, in-app account deletion, and terms accepted at sign-up.
- **Clout (the sticker currency)**: each sticker is worth `10 + 2×props + 5×trades`. Popular and frequently traded stickers are worth more. The trade screen shows both sides' clout so you can judge whether a deal is fair, and your profile shows your total collection value.

## Stack

- **iOS**: SwiftUI, iOS 17+, MapKit, Vision (`VNGenerateForegroundInstanceMaskRequest`), [supabase-swift](https://github.com/supabase/supabase-swift)
- **Backend**: Supabase (Postgres + PostGIS, Auth, Storage). All writes that matter (creating stickers, trades) go through `security definer` SQL functions, and row-level security locks down everything else.

## Setup

### 1. Supabase
1. Create a project at [supabase.com](https://supabase.com).
2. Open **SQL Editor** and run `supabase/migrations/0001_init.sql`, then `0002_social_moderation.sql`, in that order. This creates the tables, policies, functions and the public `stickers` storage bucket.
3. Optional for testing: turn off **Authentication → Providers → Email → Confirm email** so sign-up logs you straight in.
4. Copy the **Project URL** and **anon public key** from **Project Settings → API**.

### 2a. iOS app without a Mac (GitHub builds it, you sideload from Windows)
1. Create a GitHub repository and upload this folder, including the hidden `.github` folder.
2. In the repo, go to **Settings → Secrets and variables → Actions** and add two secrets: `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
3. Open the **Actions** tab. The "Build iOS app" run starts on every push, or you can start it by hand with **Run workflow**. It takes about 5–10 minutes on GitHub's macOS machines.
4. When it's green, open the run and download the **Slapped-ipa** artifact. Unzip it to get `Slapped.ipa`.
5. On Windows, install iTunes and iCloud (the versions from apple.com, not the Microsoft Store), then [Sideloadly](https://sideloadly.io). Plug in your iPhone, drag `Slapped.ipa` into Sideloadly, sign in with your Apple ID and press Start.
6. On the iPhone, turn on **Settings → Privacy & Security → Developer Mode**, then trust your Apple ID under **Settings → General → VPN & Device Management**.

With a free Apple ID the app expires after 7 days. Re-run Sideloadly to refresh it. To share it with friends through TestFlight, you need the paid Apple Developer Program ($99/yr), but you still don't need a Mac.

If the build fails, download the **build-log** artifact and send the `error:` lines to Claude.

### 2b. iOS app on a Mac with Xcode 15+
```bash
brew install xcodegen
cd Slapped
xcodegen            # generates Slapped.xcodeproj from project.yml
open Slapped.xcodeproj
```
1. Put your URL and anon key into `AppConfig` at the top of `Slapped/App/SlappedApp.swift`.
2. Select your team under **Signing & Capabilities** (and change the bundle ID if you need to).
3. Run on a **real iPhone**. The Simulator has no camera, and Vision's subject lifting doesn't work there. On the Simulator the app falls back to the full photo, so everything else is still testable.

## Project layout
```
project.yml                     XcodeGen spec (Supabase SPM dependency, Info.plist permissions)
supabase/migrations/            Database schema, RLS, RPCs, storage bucket
Slapped/App/                    App entry, config, auth state, tab bar
Slapped/Models/                 Codable models for views/RPC results
Slapped/Services/API.swift      Every Supabase call in one place
Slapped/Services/StickerVision  Background removal + perceptual hashing
Slapped/Services/LocationManager
Slapped/Views/                  Feed, Explore, Scan, Map, Profile, Sticker detail, Trades
```

## Tuning
- Duplicate radius and match strictness are the `p_radius_m` (30 m) and `p_max_bits` (10/64) defaults in `is_duplicate_sticker`.
- The clout formula is the generated `value` column on `stickers`.

## Ideas for next steps
Badges (Untappd-style: "10 finds", "first in a city"), push notifications for trade offers (Supabase webhooks → APNs), comments, reporting/moderation, and an app icon (the asset catalog has an empty `AppIcon` slot).
