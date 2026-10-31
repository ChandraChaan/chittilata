# Submitting Chittilata to Google Play

A click-by-click walkthrough of Play Console, with every answer filled in. Copy-paste text lives in [`play/`](play/); the reasoning behind the policy answers is in [LISTING.md](LISTING.md) and [DATA_SAFETY.md](DATA_SAFETY.md).

## What to upload

| Play Console field | File | Spec |
|---|---|---|
| App bundle | `build/app/outputs/bundle/release/app-release.aab` (build it with `flutter build appbundle --release --obfuscate --split-debug-info=build/symbols`) | Signed with the upload key, targets API 36 |
| App icon | [`icon-512.png`](icon-512.png) | 512×512, 32-bit PNG |
| Feature graphic | [`feature-graphic.png`](feature-graphic.png) | 1024×500, 24-bit PNG |
| Phone screenshots (8) | [`play/screenshots/01…08-*.png`](play/screenshots/) | 1080×1920. Upload in numbered order. Regenerate with `tool/brand/make_store_screenshots.sh` |
| Promo video (optional) | `docs/media/chittilata-how-to-play.mp4` | Play only takes a YouTube URL. Upload it to YouTube as *Unlisted* first |

Tablet screenshots are optional. Leave them out unless you want the app featured on tablets.

## Before you start

1. **Google Play developer account.** Sign up at <https://play.google.com/console/signup>. A *Personal* account costs a one-time US$25 and needs a government ID and a verified Android phone. Verification can take a few days.
2. **Contact email:** `dumpalachandu@gmail.com`. It is already in the privacy policy. Use the same address for the developer account and for the store listing's contact details.
3. **Privacy policy URL.** The repo is public, so once the email is in and merged this works: `https://github.com/ChandraChaan/chittilata/blob/main/docs/PRIVACY_POLICY.md`.
4. **Back up the upload keystore** (`~/.android/chittilata/chittilata-release.jks` plus `android/key.properties`). If you lose it you'll need a Play upload-key reset, which takes days.

## 1. Create the app

**Home → Create app**

| Field | Value |
|---|---|
| App name | `Chittilata - Telugu Chit Games` (30/30). Use plain `Chittilata` if you prefer |
| Default language | English (India) – en-IN |
| App or game | **Game** |
| Free or paid | **Free**. You can't change a free app to paid later |
| Declarations | Tick *Developer Program Policies* and *US export laws* |

## 2. Set up your app (Dashboard → "Set up your app")

### App access
**All functionality is available without any access restrictions.** There is no login: the app signs players in anonymously.

### Ads
**No, my app does not contain ads.**

### Content rating
Start the questionnaire. Category: **All other app types** (it's a game, but not one of the listed gambling or simulation types).
- Violence, fear, sexuality, language, controlled substances: **No** to all.
- Gambling / simulated gambling: **No**. Points have no value and nothing can be bought.
- *Does the app allow users to interact or exchange content?* **Yes** (players see each other's chosen display names in a private room and can send preset quick-chat emojis and phrases). No free-text chat, no media, no location.
- *Does the app share the user's current location?* **No**. *Digital purchases?* **No**.

Expected result: **Everyone / PEGI 3 / IARC 3+**, with a "Users Interact" notice.

### Target audience and content
- Age groups: **13–15, 16–17, 18 and over**. Don't tick under-13 groups: that brings in the Families policy, which affects Crashlytics.
- *Could your app unintentionally appeal to children?* **No.** Plain text, no cartoon characters, and the privacy policy says the app is not for under-13s.

### News app
**No.**

### Data safety
| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all user data encrypted in transit? | **Yes** |
| Which account creation methods does your app support? | **My app does not allow users to create an account.** The anonymous Firebase ID is created automatically, without any user input |
| Data deletion URL (optional) | Privacy policy URL from "Before you start" |

Data types, all **Collected: Yes · Shared: No · Processed ephemerally: No**:

| Category → type | Required/optional | Purposes |
|---|---|---|
| Personal info → **Name** | Required | App functionality |
| Personal info → **User IDs** | Required | App functionality |
| App activity → **Other user-generated content / Other actions** (game moves) | Required | App functionality |
| Messages → **Other in-app messages** (preset quick-chat emojis, phrases and nudges) | Optional | App functionality |
| App info and performance → **Crash logs** | Required | Analytics |
| App info and performance → **Diagnostics** | Required | Analytics |
| Device or other IDs → **Device or other IDs** | Required | Analytics |

### Government apps / Financial features / Health
**No / My app doesn't provide any financial features / No health features.**

### Advertising ID
**No.** Crashlytics doesn't use it, and the release manifest doesn't declare `com.google.android.gms.permission.AD_ID`.

### Privacy policy
Paste the privacy policy URL.

## 3. Store listing

**Grow users → Store presence → Main store listing**

| Field | Paste from |
|---|---|
| App name | `Chittilata - Telugu Chit Games` |
| Short description (80) | [`play/short-description.txt`](play/short-description.txt) |
| Full description (4000) | [`play/full-description.txt`](play/full-description.txt). Plain text, because Play shows `**markdown**` literally |
| App icon, feature graphic, phone screenshots | See [What to upload](#what-to-upload) |
| Video | YouTube URL, optional |

**Store settings** (same menu):
- App category: **Game → Card**
- Tags (up to 5): Card, Party, Multiplayer, Casual, Family / Board-style. Pick what the tag picker offers.
- Contact details: email (required), website `https://github.com/ChandraChaan/chittilata` (optional).

## 4. Upload the build: internal testing first

**Test and release → Testing → Internal testing → Create new release**

1. **Play App Signing:** accept *Use Google-generated key* (the default). Your keystore becomes the *upload key*.
2. Upload `app-release.aab`. Release name: `2.0.0 (3)`. Release notes: [`play/release-notes.txt`](play/release-notes.txt).
3. Save → Review release → Start rollout. Add yourself and a few family emails as internal testers and install it from the opt-in link.

**Do this right after the first upload:** go to **Test and release → Setup → App integrity → App signing** and copy the **App signing key certificate SHA-256 and SHA-1**. Play re-signs every install with that key, not with your upload key. Add both fingerprints to:
- Firebase console → Project settings → Android app `com.chandra.chittilata` → *Add fingerprint*.
- Google Cloud Console → APIs & Services → Credentials → the Android API key restriction, if you restricted it to the upload SHA-256. If you skip this, installs from Play can't reach Firebase.

Then upload the Dart symbols so Crashlytics can read crashes from the obfuscated build:
```bash
firebase crashlytics:symbols:upload --app=1:158543185837:android:f9a1aad186465883e50324 build/symbols
```

## 5. Closed testing: required for new personal accounts

Personal accounts created after 13 Nov 2023 must run a **closed test with at least 12 testers opted in for 14 continuous days** before they can apply for production.

1. **Testing → Closed testing → Create track** (or use the default *Alpha*). Add an email list of at least 12 Gmail addresses. Aim for about 15, because some people never opt in.
2. Create a release with the same AAB (*Promote release* from internal testing).
3. Choose countries (India at minimum), then send testers the opt-in link. Each tester must open it, tap *Become a tester*, and install from Play.
4. Keep the track running for 14 days. Don't pause it. Uploading new builds during the test is fine.
5. Ask testers to actually play rounds together. Google asks about engagement in the next step.

## 6. Apply for production

**Dashboard → Apply for production** (unlocked after day 14). Answer the questionnaire honestly, in your own words, covering how you recruited testers, what feedback you got and what you changed. Approval usually takes up to 7 days.

Then: **Production → Create new release → Add from library** (pick the tested AAB) → **Countries/regions** → **Send for review**. The first review typically takes a few days. You'll get an email when it's live.

## Every later update

1. Bump `version:` in `pubspec.yaml`. The `+N` build number must go up every time.
2. Follow [RELEASE_CHECKLIST.md](../RELEASE_CHECKLIST.md) for builds and tests.
3. Upload the new AAB to a testing track, then promote it to production.

## Common rejection reasons to check first

- **Privacy policy URL** returns 404 or doesn't name the app. Open the URL in a private browser window before submitting.
- **Data safety mismatch:** the form must match the privacy policy. Both say: name, anonymous ID, game data, crash logs; no ads, no location.
- **Movie titles:** they're used as plain words in a game, with no posters or logos. Keep it that way: no film artwork in screenshots or the icon.
- **Metadata:** don't add other games' names or "best/#1" claims to the title or short description.
