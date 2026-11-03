# Release checklist

## One-time setup

- [x] Firebase project `chittilata-game` (Blaze), Firestore in `asia-south1`, anonymous Auth enabled
- [x] Cloud Functions, Firestore rules and indexes, and Hosting deployed (`firebase deploy --only functions,firestore:rules,firestore:indexes,hosting`)
- [x] Release keystore generated at `~/.android/chittilata/chittilata-release.jks`; `android/key.properties` (git-ignored) points at it
- [ ] **Back up the keystore and `android/key.properties` somewhere safe (password manager).** If they are lost, you can never update the app on Play.
- [ ] Add GitHub Actions secrets so tagged releases can be signed in CI:
  - `ANDROID_KEYSTORE_BASE64` (`base64 -i ~/.android/chittilata/chittilata-release.jks | pbcopy`)
  - `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`chittilata`), `ANDROID_KEY_PASSWORD` (values in `android/key.properties`)
  - Optional: `FIREBASE_SERVICE_ACCOUNT_JSON`, a service account with *Firebase App Distribution Admin* and *Firebase Crashlytics* roles
- [ ] In Google Cloud Console → APIs & Services → Credentials, restrict the Android API key to package `com.chandra.chittilata` and the release SHA-256 `AD:5B:D1:6C:1D:78:BC:90:9B:7A:55:33:10:BD:A8:4B:FF:1D:E8:42:C7:28:52:6A:EF:B6:4A:16:95:EC:94:5A`
- [ ] Consider enabling Firebase App Check (Play Integrity) and enforcing it on callables
- [ ] If you raise `maxInstances` or CPU, check the regional Cloud Run CPU quota first. Deploys fail with "Quota exceeded for total allowable CPU per project per region" otherwise.
- [ ] Add testers to the App Distribution group `family-testers`

## Every release

1. Bump `version:` in `pubspec.yaml` (e.g. `1.0.1+2`; the build number must increase).
2. `flutter analyze && flutter test`
3. `cd functions && npm test && npm run test:emulator` (needs Java 21: `export JAVA_HOME=/opt/homebrew/opt/openjdk@21`)
4. If the backend changed, deploy what changed: `firebase deploy --only functions,firestore:rules,firestore:indexes` (add `hosting` if `hosting/` changed)
5. Build:
   ```bash
   flutter build apk --release --obfuscate --split-debug-info=build/symbols
   flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
   ```
6. Upload Dart symbols so Crashlytics can de-obfuscate:
   ```bash
   firebase crashlytics:symbols:upload --app=1:158543185837:android:f9a1aad186465883e50324 build/symbols
   ```
7. Smoke test on a device with bots, for both modes:
   - `cd functions && node scripts/bots.mjs --code <ROOMCODE> --count 3` (Movie Chits)
   - `node scripts/bots.mjs --mode kq --code <ROOMCODE> --count 3` (King & Queen)
8. Beta: `firebase appdistribution:distribute build/app/outputs/flutter-apk/app-release.apk --app 1:158543185837:android:f9a1aad186465883e50324 --groups family-testers --release-notes "…"`
9. GitHub: tag `vX.Y.Z` and push. The release workflow attaches signed APKs. Or attach manually with `gh release create`.
10. Play Console: upload `build/app/outputs/bundle/release/app-release.aab` to Internal testing first.
11. Once the new build is live on Play, tell older installs about it: in the Firebase console → Firestore → `config/app`, set `latestBuild` to the new build number (an optional "New version available" card). Only builds 6 (2.2.0) and later read this.

## Forcing an update

Use this when an old version is broken or incompatible with the server, after the new version is available on Play:

1. Firebase console → Firestore → collection `config`, document `app` (create it the first time).
2. Set number fields `minBuild` (builds below it are blocked with "Update required") and `latestBuild` (builds below it get an optional update card). Optional string fields: `message` (shown on the update page, e.g. "New: emoji chat!") and `updateUrl` (opened instead of the Play Store, e.g. the GitHub releases page for testers).
3. It takes effect immediately on open apps. To undo, lower `minBuild` again.

The app checks the installed build number (the `+N` in `pubspec.yaml`), not the version name.

## Play Console submission (when ready)

The full walkthrough, with every answer filled in, is in [store/PLAY_SUBMISSION.md](store/PLAY_SUBMISSION.md).

- [x] Contact email added to `docs/PRIVACY_POLICY.md`
- [ ] Merge to `main` so the policy is live at https://github.com/ChandraChaan/chittilata/blob/main/docs/PRIVACY_POLICY.md
- [ ] Store listing text and graphics from `docs/store/`
- [ ] Data Safety form from `docs/store/DATA_SAFETY.md`
- [ ] Content rating questionnaire (see `docs/store/LISTING.md`)
- [ ] Target audience and content (13+ recommended)
- [ ] Enroll in Play App Signing (upload key = the keystore above), then add the Play **app signing** SHA-1/SHA-256 to Firebase and to the API key restriction
- [ ] Internal testing → Closed testing (12+ testers for 14 days for new personal accounts) → Production
