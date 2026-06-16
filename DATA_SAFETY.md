# Nudge — Play Console Data Safety form (cheat-sheet)

**Last updated:** June 2026

This file mirrors the answers you need to enter in Google Play
Console → *App content → Data safety* for the Nudge app. The
answers are written so the form can be filled in quickly during
the Play Store review process; they are also useful as a
self-contained summary for any future App Store / Play Store
reviewer or auditor.

> TL;DR: the app does **not** collect or share any user data. Every
> "Is this data collected, shared, or required?" field is "No".
> The only data the app handles lives on the user's device.

---

## 1. Data the app handles

### Data the app *does* keep, locally, on the user's device

| Type | What | Why | Shared? | User can delete? |
|------|------|-----|---------|------------------|
| App functionality | Reminder **rules** the user creates (label, trigger type, threshold, comparison, alert type, quiet-hours window, last-fired timestamp, enabled flag). | Core feature. | No. | Yes, in *Settings → DATA & PRIVACY → Delete all data*, or by deleting a single rule on the home screen. |
| App functionality | **Profiles** the user creates (name, icon, creation time). | Lets the user group rules. | No. | Yes, in the Profiles screen or via Delete all data. |
| App functionality | **Export history** — a list of the last 20 backup files the user has shared, with file name, size, timestamp, and rule count. | Lets the user re-share or delete a previous backup. | No. | Yes, per-row, or via Delete all data. |
| App functionality | **Onboarding flag** — a single boolean tracking whether the welcome carousel has been shown. | Suppresses the carousel on subsequent launches. | No. | Resets when the app data is cleared. |

### Data the app *does not* keep or process

- No account or sign-in data — there is no sign-in.
- No contact information, name, email, address, or phone number.
- No location history. The app requests location permission only at
  the moment the user creates or edits a Wi-Fi rule, and only to
  read the current SSID; nothing is stored about the user's
  movements.
- No health, fitness, financial, or message data.
- No browsing or search history.
- No identifiers (advertising ID, IMEI, MAC address, etc.).
- No device telemetry (model, OS version, free storage, battery
  level, etc.) — the app reads the battery level at evaluation
  time and discards it; the OS version is implicit because the
  APK targets a min SDK.
- No audio, video, photo, or file contents (the import flow reads
  a user-picked `.json` file but the contents are parsed in-memory
  and never written to a separate location beyond the rule box).
- No clipboard, calendar, contacts, SMS, call log, sensor, or
  installed-app data.

## 2. Play Console answers (verbatim)

> **Does your app collect or share any of the required user data
> types?**
> No.

> **Is all of the user data collected by your app encrypted in
> transit?**
> Not applicable — the app does not transmit user data.

> **Do you provide a way for users to request that their data is
> deleted?**
> Yes — *Settings → DATA & PRIVACY → Delete all data*, and the
> platform's *Clear app data* setting.

> **Data safety form summary (one-line per row):**
>
> - Location → collected: **No**; shared: **No**.
> - Personal info → collected: **No**; shared: **No**.
> - Financial info → collected: **No**; shared: **No**.
> - Health & fitness → collected: **No**; shared: **No**.
> - Messages → collected: **No**; shared: **No**.
> - Photos & videos → collected: **No**; shared: **No**.
> - Audio files → collected: **No**; shared: **No**.
> - Files & docs → collected: **No**; shared: **No**.
> - Calendar → collected: **No**; shared: **No**.
> - Contacts → collected: **No**; shared: **No**.
> - App activity (in-app actions) → collected: **No**; shared: **No**.
> - Web browsing → collected: **No**; shared: **No**.
> - App info & performance → collected: **No**; shared: **No**.
> - Device or other IDs → collected: **No**; shared: **No**.

## 3. Security practices

- **Data in transit:** the app does not make network calls in its
  normal operation. The only declared network permission
  (`INTERNET`) is inherited from the Flutter tooling and is used
  by the `google_fonts` package on first launch to fetch the Inter
  font family from `fonts.gstatic.com`. Those font files are cached
  in the app's private storage afterwards. See
  "Optional: remove all network calls" below for the steps to
  eliminate this surface entirely.
- **Data at rest:** stored in Android's per-app private storage.
  Users who enable Android's full-device encryption get
  encryption at rest transparently. The app does not implement
  its own at-rest encryption.
- **User controls:** every store is user-editable; the
  *Delete all data* action is irreversible and gated by a typed
  confirmation. The export history can be cleared row by row.
- **Account handling:** none. There is no account, no sign-in, no
  password, no token, no email.

## 4. Compliance & children

- **COPPA:** Nudge is not directed at children under 13. The app
  does not collect any personal information from anyone, so
  COPPA is satisfied by construction.
- **GDPR / UK GDPR:** No personal data is processed; the data that
  does exist is processed solely on the user's device, with the
  user as the sole data controller.
- **CCPA / CPRA:** No "sale" or "sharing" of personal information
  occurs, because no personal information leaves the device.

## 5. Auditor / reviewer note

If a reviewer needs to verify any of the above, the source code is
publicly available (the repository URL is set in the Play Store
listing). In particular:

- The Dart codebase does not depend on any analytics SDK. A
  full-text search of the repository for `firebase`,
  `crashlytics`, `sentry`, `amplitude`, `mixpanel`, `analytics`,
  `tracker`, and `telemetry` returns no matches in the app
  source.
- The Java codebase does not register any background network
  callers. The only network surface in `MainActivity.java` is
  the SAF file-picker result returned to Flutter for the Import
  flow; no HTTP client is instantiated anywhere.
- The `AndroidManifest.xml` **does** declare
  `android.permission.INTERNET`. This is inherited from the
  Flutter Gradle plugin and is required for the `google_fonts`
  package (which fetches font files from `fonts.gstatic.com` on
  first launch and caches them locally). The recipient sees
  the device IP but **no Nudge-specific identifier or analytics
  payload** is sent. To confirm:

  ```sh
  grep -i 'INTERNET' android/app/src/main/AndroidManifest.xml
  # Expected: <uses-permission android:name="android.permission.INTERNET" />
  ```

  If the strictest "zero network" stance is required, see
  "Optional: remove all network calls" below.

## 6. Optional: remove all network calls

If a privacy-purist market requires zero outbound network calls,
follow these steps to drop `google_fonts` and the `INTERNET`
permission:

1. In `pubspec.yaml`, remove `google_fonts: ^8.1.0`.
2. Download the Inter font family from <https://rsms.me/inter/>
   (Open Font License) and place the `.ttf` files under
   `assets/fonts/`.
3. In `pubspec.yaml`, declare them under `flutter: fonts:`.
4. Replace every `GoogleFonts.inter(...)` call in `lib/` with a
   plain `TextStyle(...)` using the new font family.
5. Remove the `<uses-permission android:name="android.permission.INTERNET" />`
   line from `android/app/src/main/AndroidManifest.xml`.

After these five steps the release APK declares zero network
permissions, makes zero outbound network calls, and is trivially
auditable. The trade-off is a slightly larger APK (the bundled
font files) and a slightly less polished typography pipeline.
For a 1.0.0 "local-first" launch in a privacy-conscious market,
this is a worthwhile trade.