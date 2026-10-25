# Releasing Slapped

Everything runs from a browser. You never need a Mac.

## 1. Update the database (2 min, do this first)
1. Supabase dashboard → your project → **SQL Editor** → **New query**.
2. Paste all of [`supabase/migrations/0002_social_moderation.sql`](../supabase/migrations/0002_social_moderation.sql) and click **Run**.
   This adds comments, activity, badges, blocking, reporting and account deletion. It's safe to run again.

## 2. Email codes (3 min)
The app verifies emails and resets passwords with a 6-digit code instead of a link.
In Supabase: **Authentication → Emails → Templates** (older dashboards: **Auth → Email Templates**).

- **Confirm signup**: replace the body with:
  `<h2>Welcome to Slapped</h2><p>Your code is <strong>{{ .Token }}</strong></p>`
- **Reset Password**: replace the body with:
  `<h2>Reset your Slapped password</h2><p>Your code is <strong>{{ .Token }}</strong></p>`

Then **Authentication → Sign In / Providers → Email**: make sure **Confirm email** is **on** for launch.

**Before launch:** Supabase's built-in email sender only sends a few emails per hour. Add your own SMTP under **Authentication → Emails → SMTP Settings**. [Resend](https://resend.com) has a free tier that's enough to start.

## 3. Apple Developer account
1. Join the [Apple Developer Program](https://developer.apple.com/programs/enroll/) ($99/year). Approval can take a day or two.
2. Note your **Team ID**: [developer.apple.com/account](https://developer.apple.com/account) → Membership details.

## 4. Create the app in App Store Connect
1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**.
2. Platform iOS, name **Slapped** (if it's taken, try "Slapped: Sticker Hunt"), language English.
3. **Bundle ID**: if `com.uglyerror.slapped` isn't in the list, open [Identifiers](https://developer.apple.com/account/resources/identifiers/list) in another tab, click **+** → App IDs → App, enter Bundle ID `com.uglyerror.slapped` with description "Slapped", then refresh.
4. SKU: `slapped`.

## 5. API key for GitHub (lets GitHub sign and upload for you)
1. App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys** → **+**.
2. Name `GitHub`, access **Admin**. Admin is needed so GitHub can create signing certificates.
3. Download the `.p8` file (you only get one chance), and note the **Key ID** and the **Issuer ID** shown above the table.
4. GitHub repo → **Settings → Secrets and variables → Actions → New repository secret**, and add:

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Your Team ID (10 characters) |
| `ASC_KEY_ID` | The Key ID |
| `ASC_ISSUER_ID` | The Issuer ID |
| `ASC_PRIVATE_KEY` | Open the `.p8` in Notepad and paste **everything**, including the BEGIN/END lines |

## 6. Upload a build
GitHub repo → **Actions** → **Release to TestFlight** → **Run workflow**. About 10 minutes later the build appears in App Store Connect → your app → **TestFlight**. Apple then needs 10–30 minutes to process it.

- **TestFlight**: add yourself and friends as testers. No more 7-day expiry or Sideloadly.
- Every run uploads a new build number automatically. To change the version shown in the App Store (1.0.0), edit `MARKETING_VERSION` in `project.yml`.

## 7. App Store listing
In App Store Connect → your app → **Distribution**:

**Subtitle:** Find, scan & trade street stickers

**Description:**
> Slapped turns the stickers on lamp posts, signs and skateparks into a game. Spot one, scan it, and Slapped cuts it out and pins it to the map where you found it. Every sticker can only be logged once per spot, so be the first.
>
> • Scan: instant sticker cut-outs with your camera
> • Map: see every sticker found near you and around the world
> • Explore: trending finds, stickers near you and top hunters
> • Trade: offer your stickers for other people's. Popular and well-traded stickers earn more clout
> • Feed: follow friends, give props and comment on finds
> • Badges: earn badges as you hunt, trade and explore

**Keywords:** stickers,sticker,street art,slaps,collect,trade,scavenger hunt,map,explore,graffiti

**Support URL:** `https://github.com/UglyError/slapped/issues`
**Privacy Policy URL:** `https://github.com/UglyError/slapped/blob/main/docs/privacy.md`
**Category:** Social Networking (secondary: Lifestyle). **Age rating:** answer the questionnaire honestly. User-generated content usually leads to 12+ or higher.

**Screenshots:** you need at least 3 from a 6.9" or 6.7" iPhone (Pro Max or Plus). Install from TestFlight, then take screenshots of the Feed, the Map, a sticker page and the Trade screen.

**App Privacy** (questionnaire): Data collected and linked to the user, not used for tracking, for App Functionality:
Contact Info → Email Address · Location → Precise Location · User Content → Photos, Other User Content · Identifiers → User ID.

**App Review Information:**
- Create a demo account in the app and put its email and password here. Reviewers must be able to sign in. Log a couple of stickers on it first.
- Notes:
  > Slapped is a social app for logging real-world stickers. Moderation: every sticker, comment and user has Report and Block in its "…" menu; content reported by 3 users is hidden automatically and we review reports in Supabase within 24 hours. Users accept the Terms (zero tolerance for objectionable content) at sign-up. Accounts can be deleted in Profile → Settings → Delete account.

Then **Add for Review** → **Submit**.

## 8. After launch: moderation (required by Apple)
Check reports at least daily: Supabase → **Table Editor → reports**. To remove content, delete the row in `stickers` or `comments`. To ban someone, delete them under **Authentication → Users**.

## Development builds (sideloading) still work
Every push to `main` runs **Build iOS app** and produces an unsigned `Slapped-ipa` you can install with Sideloadly, as before.
