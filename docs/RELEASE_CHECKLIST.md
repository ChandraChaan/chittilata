# Release checklist

## One-time setup

- [x] Firebase project `chittilata-game` (Blaze), Firestore in `asia-south1`, anonymous Auth enabled
- [x] Cloud Functions and Firestore rules deployed (`firebase deploy --only functions,firestore:rules`)
- [x] Release keystore generated at `~/.android/chittilata/chittilata-release.jks`; `android/key.properties` (git-ignored) points at it
- [ ] **Back up the keystore and `android/key.properties` somewhere safe (password manager).** If they are lost, you can never update the app on Play.
- [ ] Add GitHub Actions secrets so tagged releases can be signed in CI:
  - `ANDROID_KEYSTORE_BASE64` (`base64 -i ~/.android/chittilata/chittilata-release.jks | pbcopy`)
  - `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`chittilata`), `ANDROID_KEY_PASSWORD` (values in `android/key.properties`)
  - Optional: `FIREBASE_SERVICE_ACCOUNT_JSON`, a service account with *Firebase App Distribution Admin* and *Firebase Crashlytics* roles
- [ ] Fix GitHub Actions billing for the account. CI jobs are currently refused with "recent account payments have failed or your spending limit needs to be increased".
- [ ] In Google Cloud Console → APIs & Services → Credentials, restrict the Android API key to package `com.chandra.chittilata` and the release SHA-256 `AD:5B:D1:6C:1D:78:BC:90:9B:7A:55:33:10:BD:A8:4B:FF:1D:E8:42:C7:28:52:6A:EF:B6:4A:16:95:EC:94:5A`
- [ ] Consider enabling Firebase App Check (Play Integrity) and enforcing it on callables
- [ ] Add testers to the App Distribution group `family-testers`

## Every release

1. Bump `version:` in `pubspec.yaml` (e.g. `1.0.1+2`; the build number must increase).
2. `flutter analyze && flutter test`
3. `cd functions && npm test && npm run test:emulator` (needs Java 21: `export JAVA_HOME=/opt/homebrew/opt/openjdk@21`)
4. If functions or rules changed: `firebase deploy --only functions,firestore:rules`
5. Build:
   ```bash
   flutter build apk --release --obfuscate --split-debug-info=build/symbols
   flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
   ```
6. Upload Dart symbols so Crashlytics can de-obfuscate:
   ```bash
   firebase crashlytics:symbols:upload --app=1:158543185837:android:f9a1aad186465883e50324 build/symbols
   ```
7. Smoke test on a device with bots: `cd functions && node scripts/bots.mjs --code <ROOMCODE> --count 3`
8. Beta: `firebase appdistribution:distribute build/app/outputs/flutter-apk/app-release.apk --app 1:158543185837:android:f9a1aad186465883e50324 --groups family-testers --release-notes "…"`
9. GitHub: tag `vX.Y.Z` and push. The release workflow attaches signed APKs. Or attach manually with `gh release create`.
10. Play Console: upload `build/app/outputs/bundle/release/app-release.aab` to Internal testing first.

## Play Console submission (when ready)

- [ ] Publish `docs/PRIVACY_POLICY.md` at a public URL and add a contact email
- [ ] Store listing text and graphics from `docs/store/`
- [ ] Data Safety form from `docs/store/DATA_SAFETY.md`
- [ ] Content rating questionnaire (see `docs/store/LISTING.md`)
- [ ] Target audience and content (13+ recommended)
- [ ] Enroll in Play App Signing (upload key = the keystore above)
- [ ] Internal testing → Closed testing (12+ testers for 14 days for new personal accounts) → Production
