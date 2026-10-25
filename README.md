# MeetingRush

A macOS menu bar app that takes over the screen shortly before a meeting starts, with buttons to join the call, snooze or dismiss.
It reads events from Calendar.app, so it sees every account added there: iCloud, Exchange/Microsoft 365, Google.
Google Meet, Teams and Zoom links are found in the event's URL, location or notes, including links wrapped by Outlook Safe Links.
The menu lists the next few meetings, and Settings chooses which calendars alert.

Requires macOS 14 or later.

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
| `scripts/bundle.sh` | Builds and signs the `.app` bundle |
| `packaging/homebrew` | Formula template for a Homebrew tap |

New calendar sources implement `CalendarProvider` and are added to the list passed to `AppCoordinator` in `MeetingRushApp.swift`.

## Homebrew

`packaging/homebrew/meetingrush.rb` builds from source, so Gatekeeper never quarantines the result and no Developer ID is needed.
Copy it into a tap repository and fill in the release URL, checksum and licence.
