# MeetingRush

A macOS menu bar app that takes over the screen shortly before a meeting starts, with buttons to join the call, snooze or dismiss.
It reads events from Calendar.app, so it sees every account added there (iCloud, Exchange/Microsoft 365, Google),
and can also read Google Calendar directly.
Google Meet, Teams and Zoom links are found in the event, including links wrapped by Outlook Safe Links.
The menu lists the next few meetings, and Settings chooses which calendars alert.

Requires macOS 14 or later.

## Install

```sh
brew install --cask meetingrush/tap/meetingrush
```

The app installs into `/Applications` and requires an Apple silicon Mac.

## Google Calendar

MeetingRush can read Google Calendar through Google's API, which also picks up Meet links reliably.
It signs in with an OAuth client from your own Google Cloud project:

1. In the [Google Cloud console](https://console.cloud.google.com/), create a project.
2. Under **APIs & Services → Library**, enable the **Google Calendar API**.
3. Under **Google Auth Platform**, fill in **Branding** (an app name and your email) and set **Audience** to **External**.
   Then either add yourself as a test user, in which case Google signs you out every 7 days, or click **Publish app**,
   which shows an "unverified app" warning once when you connect and doesn't expire.
4. Under **Clients**, create a client of type **Desktop app** and copy its client ID and secret.
5. In MeetingRush, open **Settings → Google Calendar**, paste both, and click **Connect Google Account…**.

MeetingRush only asks for read-only calendar access. A Google Workspace admin may need to allow the client before a work
account can connect. If the same account is also added to Calendar.app, each meeting still alerts once.

## Build and run

The app builds with the Xcode Command Line Tools alone (`xcode-select --install`):

```sh
make run       # build dist/MeetingRush.app and launch it
make install   # copy it to ~/Applications
```

macOS asks for calendar access on first launch. Launch the bundle (`make run` or `open`), not the bare binary,
or the permission is attributed to your terminal instead of the app.

Running the tests needs full Xcode, because the Command Line Tools ship without a working test framework:

```sh
make test
```

The app target avoids SwiftUI macros (`@State`, `@Entry`, `@Previewable`) for the same reason: their plugin is missing from the
Command Line Tools, so a Homebrew build would fail. Use `@Observable` models and `@AppStorage` instead.

## Troubleshooting

Alert scheduling is logged. To see why an alert did or didn't fire:

```sh
log show --last 4h --predicate 'subsystem == "dev.meetingrush.MeetingRush"' --style compact
```

## Signing during development

`make` signs ad-hoc by default. An ad-hoc signature changes with every build, so macOS may ask for calendar access again
after each rebuild. A self-signed certificate keeps the signature stable:

1. Keychain Access → Certificate Assistant → Create a Certificate…
2. Name it `MeetingRush Dev`, Identity Type **Self Signed Root**, Certificate Type **Code Signing**.
3. Create an untracked `local.mk`:

   ```make
   CODESIGN_IDENTITY := MeetingRush Dev
   ```

`local.mk` can also override `BUNDLE_ID`. Changing it resets the calendar permission and settings.

## Layout

| Path | Contents |
| --- | --- |
| `Sources/MeetingRushCore` | Calendar-agnostic logic: the `Meeting` model, the `CalendarProvider` protocol, link detection, alert planning |
| `Sources/MeetingRush` | The app: menu bar, full-screen overlay, settings, and the EventKit provider |
| `Tests/MeetingRushCoreTests` | Swift Testing tests for the core |
| `Resources/Icons` | Menu bar and app icons: SVG sources plus the generated PDF and `.icns`; `make icons` regenerates them |
| `scripts/bundle.sh` | Builds and signs the `.app` bundle |
| `.github/workflows/release.yml` | Builds, signs and publishes the release zip the cask installs |

New calendar sources implement `CalendarProvider` and are added to the list passed to `AppCoordinator` in `MeetingRushApp.swift`.

## Releasing

Releases are built by GitHub Actions and installed through the cask in
[meetingrush/homebrew-tap](https://github.com/meetingrush/homebrew-tap). See [docs/RELEASING.md](docs/RELEASING.md).

## Licence

MeetingRush is free software, released under the GNU General Public License v3.0 or later. See [LICENSE](LICENSE).
