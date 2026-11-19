# Google Play listing — ChitPlay

## App details

| Field | Value |
|---|---|
| App name | ChitPlay: Chit Party Games (was "Chittilata - Telugu Chit Games" until 2.6.0) |
| Package | `com.chandra.chittilata` |
| Default language | English (en-US in Play Console). English first; Telugu is an in-app option (movie list), not a separate listing |
| Category (suggested) | **Games → Card**. Alternatives: Games → Word, Games → Board |
| Tags (suggested) | Card game, Party game, Multiplayer, Family |
| Contains ads | No |
| In-app purchases | No |

## Descriptions

Paste these as-is. They're plain text because Play Console shows markdown literally.

- Short description (74/80): [`play/short-description.txt`](play/short-description.txt)
- Full description (3483/4000): [`play/full-description.txt`](play/full-description.txt)
- Release notes for the current version: [`play/release-notes.txt`](play/release-notes.txt)

## Graphics

| Asset | File | Notes |
|---|---|---|
| App icon 512×512 | `docs/store/icon-512.png` | 32-bit PNG. Source: `tool/brand/icon.html` (crown on paper chits, no script) |
| Feature graphic 1024×500 | `docs/store/feature-graphic.png` | Source: `tool/brand/feature.html` (also the invite-link preview and the GitHub social preview) |
| Phone screenshots for Play (1080×1920) | `docs/store/play/screenshots/01…08-*.png` | The 8 to upload: raw captures with a headline, made by `tool/brand/make_store_screenshots.sh` |
| Raw screenshots | `docs/store/screenshots/*.png` | Real captures on the production backend with bot players. Movie Chits ones (01, 03–06, 13) are 1080×2400 from 2.6.0 with English movies (the script hides their status bar); King & Queen ones (07–12) are 1080×2160 |
| Promo video | `docs/media/chittilata-how-to-play.mp4` | Play needs a YouTube URL, so upload the file to YouTube first |

## Content rating questionnaire (IARC) — expected answers

- Violence, sexual content, profanity, drugs, gambling: **None**. The game has no real-money stakes and no simulated gambling; points have no value.
- User interaction: players see the **display names** and avatar emojis others choose, and send **preset** emojis, phrases and nudges. In rooms of friends, seated players can also type **short messages** (80 characters, filtered for abusive words on every phone). Quick-match tables with strangers are preset-only. Players can **mute** or **report** anyone from the chat, and hide typed messages in Settings. No user-generated media, no location sharing.
- Expected rating: **Everyone / PEGI 3 / IARC 3+**. Note "Users interact" in the questionnaire.

## Target audience

Suggested target age group: **13+**. A family game can appeal to children, but declaring under-13s brings Families Policy requirements (for example, no anonymous Crashlytics without review). Decide this deliberately before submitting.

## Pre-launch notes

- Movie titles are used only as words in a guessing/collection game, with no posters, logos or clips. Review with your own legal judgement before publishing.
- The listing must not claim features the app doesn't have. Everything listed above is implemented.
