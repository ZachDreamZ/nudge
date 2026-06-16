# Nudge Privacy Policy

**Last updated:** June 2026

Nudge ("we", "our", "the app") is a local-first reminder application for
Android. This policy describes, in plain language, exactly what data the app
handles and what it does with that data. The short version is at the top;
the details are below.

## Short version

- **No account, no sign-up.** Nudge does not know who you are.
- **No analytics, no telemetry, no tracking.** Nothing about you, your
  device, or your rules is ever sent to a server.
- **No remote servers are contacted** unless you explicitly tap
  "Import" and pick a backup file from another device.
- **All your data lives on this device.** Your rules, your profiles,
  and your backup history are stored in private app storage that
  Android sandboxes per-app. No other app — and no one online — can
  read them.
- **You can wipe everything** at any time from
  *Settings → DATA & PRIVACY → Delete all data*. There is no
  "recovery" because there is no copy of your data anywhere else.

## What we store on this device

The app keeps four small data stores, all in the app's private
storage. None of them are encrypted at rest by us (you can use
Android's full-device encryption to encrypt them with your screen
lock):

1. **Rules** — the smart-reminder rules you create or import.
   Each rule stores:
   - The label (e.g. "Plug in before bed").
   - The trigger type (`battery` or `wifi`).
   - The trigger value (a battery percentage threshold or a Wi-Fi SSID).
   - The comparison operator (`<`, `<=`, `==`, `>`, `>=`).
   - The alert type (`standard` for a normal notification sound,
     `alarm` for the alarm ringtone).
   - Optional quiet-hours start and end (in minutes since midnight).
   - The last time the rule fired.
   - Whether the rule is enabled.
2. **Profiles** — named buckets for your rules. There is always a
   default "Personal" profile. You can create more, rename them,
   pick an icon, or delete them. Deleting a profile deletes its rules
   too.
3. **Export history** — a list of the last 20 backup files you've
   shared, with their file name, size, timestamp, and rule count.
   This stays on the device.
4. **Onboarding flag** — a single boolean (`first_run_complete`) that
   tracks whether you've seen the welcome carousel.

## Permissions we request, and why

- **Notifications** (`POST_NOTIFICATIONS` on Android 13+). Required to
  show reminders. Without it, every rule fires into the void. We
  request this on first launch and again before you save the first
  rule, with a clear in-app explanation if you decline.
- **Location ("in use")** (`ACCESS_FINE_LOCATION` /
  `ACCESS_COARSE_LOCATION`). Only requested when you create or edit a
  **Wi-Fi rule** on Android 8.0+. Android redacts the connected
  Wi-Fi SSID to a fake MAC unless the user has granted location
  permission, so we cannot read which network you joined without it.
  Battery-only users never see this prompt.
- **Battery optimisation whitelist** (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`).
  Triggered from the *Settings → Battery optimization* tile. Android
  may otherwise kill the app's background worker, and reminders
  will silently stop. We never bypass this — the user always taps
  "Allow" in the system dialog.

## What we do NOT do

- We do not collect analytics (no Firebase, no Crashlytics, no
  Sentry, no Amplitude, no Mixpanel, nothing).
- We do not place cookies or local-storage trackers.
- We do not display ads.
- We do not share or sell any information to third parties — there
  is no information to share.
- We do not contact any server in the normal course of operation.
  The only network activity the app can produce is the **explicit
  "Import" flow**, which uses a system file picker to let you pick
  a `.json` backup file you previously exported. The contents of
  that file are read on-device; nothing is uploaded.

## How to delete your data

Three options:

1. **In-app** (recommended). *Settings → DATA & PRIVACY →
   Delete all data*. The dialog requires you to type the word
   "DELETE" before the action activates. All rules, all profiles
   (except the default "Personal" which is immediately recreated),
   and the export history are wiped from this device.
2. **Android settings**. *Settings → Apps → Nudge → Storage →
   Clear data*. This is a stronger reset that also clears the
   onboarding flag, so the next launch will show the welcome
   carousel again.
3. **Uninstall the app**. Same effect as option 2.

## Children

The app is not directed at children under 13. We do not knowingly
collect any data from children; in fact we collect no data from
anyone, as described above.

## Changes to this policy

If we change anything material about how the app handles data, we
will update this file and bump the "Last updated" date at the top.
Because we do not collect your contact information, we cannot notify
you directly — please check back before each release.

## Contact

Nudge is an open-source project. The source code, the issue tracker,
and the maintainer's contact information live in the project's
public repository (the URL is set in the Play Store listing).

## License

This policy is released under the same license as the Nudge source
code.