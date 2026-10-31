# Releasing MeetingRush

MeetingRush ships as a Homebrew cask.
Pushing a `vX.Y.Z` tag runs [the release workflow](../.github/workflows/release.yml), which tests the tagged commit, builds a universal (Apple silicon and Intel) `MeetingRush.app`, signs and zips it, records a build provenance attestation and publishes the zip as a GitHub Release.
The cask in [meetingrush/homebrew-tap](https://github.com/meetingrush/homebrew-tap) points at that zip, and Homebrew installs the app into `/Applications`.

Only reviewed code gets signed:

- The signing secrets live in the repository's `release` environment, whose deployment rule only admits `v*` tags.
- The **Release tags** ruleset lets only organisation admins create, move or delete `v*` tags.
- The workflow refuses a tag whose commit isn't already on `main`, or that doesn't match `VERSION`.

Until the project has a paid Apple Developer ID, releases are signed with a free Apple Development certificate.
It keeps the app's signature the same from one release to the next, so macOS keeps its calendar and keychain permissions across upgrades, but Gatekeeper doesn't accept it for downloaded apps.
The cask therefore removes the quarantine flag after installing, until releases are notarised.

## One-time setup

### 1. Create the signing certificate

1. In Xcode, open **Settings → Accounts**, click **+**, and sign in with your Apple ID.
   A free account shows up as **Your Name (Personal Team)**.
2. Select the Personal Team, click **Manage Certificates…**, then **+ → Apple Development**.
3. Note the certificate's full name, for signing local builds:

   ```sh
   security find-identity -v -p codesigning
   # 1) 0123ABCD… "Apple Development: Your Name (XXXXXXXXXX)"
   ```

### 2. Export it and add it to GitHub

1. In Keychain Access, open the **login** keychain, **My Certificates**, and find **Apple Development: Your Name**.
   Expand it to check its private key is underneath, then right-click the certificate, choose **Export…**, save it as `AppleDevelopment.p12`, and set a strong password.
   Exporting from **Certificates** instead leaves the private key out.
2. Check the file holds a signing identity, in a throwaway keychain:

   ```sh
   KC="$TMPDIR/check.keychain-db"
   security delete-keychain "$KC" 2>/dev/null   # a leftover from an earlier attempt
   security create-keychain -p check "$KC" && security unlock-keychain -p check "$KC"
   security import AppleDevelopment.p12 -k "$KC" -f pkcs12 -T /usr/bin/codesign   # prompts for the password
   security find-identity -p codesigning "$KC"   # expect one Apple Development identity under Matching identities
   security delete-keychain "$KC"
   ```

   The valid count can be 0 here on a Mac without Apple's WWDR G3 certificate, which doesn't matter for this check.
   Always finish with the last command: the throwaway keychain holds your private key behind a weak password.
3. Add both secrets to the `release` environment, not to the repository:

   ```sh
   base64 -i AppleDevelopment.p12 | gh secret set MACOS_CERTIFICATE_P12 --env release --repo meetingrush/meetingrush
   gh secret set MACOS_CERTIFICATE_PASSWORD --env release --repo meetingrush/meetingrush   # prompts for the password
   ```

   The workflow signs with the one identity in the certificate, so there's no identity to keep in step with it.
   It fails if the certificate is missing or holds more than one identity, rather than falling back to ad-hoc signing.
4. Delete `AppleDevelopment.p12`.

Apple Development certificates expire after a year.
When it does, create a new one and repeat this step; the next release asks for calendar access once more.

### 3. Optional: sign local builds the same way

To stop macOS asking for calendar access after every local rebuild, add the identity to an untracked `local.mk` in each worktree:

```make
CODESIGN_IDENTITY := Apple Development: Your Name (XXXXXXXXXX)
```

Local builds stay native-only, without the hardened runtime, so they build offline and debuggers can attach.
To check a release build locally, which needs a network connection for the signing timestamp:

```sh
RELEASE=1 make app
```

## Releasing a version

`make release` runs the release one step at a time, using your own `gh` login.
Run it again after merging each pull request it opens:

```sh
make release VERSION=X.Y.Z
```

1. The first run opens a pull request on a `release-x-y-z` branch that sets `VERSION`.
2. Once it's merged, the next run tags the tip of `main` and pushes the tag.
   It then follows the release workflow until the GitHub Release is published.
   The run fails straight away if the tag doesn't match `VERSION` or isn't on `main`.
3. The same run downloads the release zip, checks its provenance attestation and opens a `homebrew-tap` pull request on a `meetingrush-x-y-z` branch, with the new `version` and `sha256` in `Casks/meetingrush.rb`.
   It runs `brew style` on the cask first.
4. Once that's merged, run `brew update`, then `make release VERSION=X.Y.Z` once more.
   It runs `brew audit --cask --strict --online` on the merged cask, which it can't do earlier: `brew audit` only reads the installed tap, not a file in a worktree.
   Then `brew upgrade --cask meetingrush` installs the new version.

The script creates its branches as worktrees next to the others, and expects the tap's clone at `../homebrew-tap`; set `TAP_REPO` if it lives elsewhere.
Pushing the tag needs organisation admin rights, because of the **Release tags** ruleset.
If a step fails, fix the cause and run the same command again; it picks up where it stopped.
If the release workflow fails and needs a code fix, merge the fix, delete the tag with `git push origin :refs/tags/vX.Y.Z`, and run the command again to tag the new `main`.

The cask also pins the signing team ID, which only changes with the certificate, so the script leaves it alone.
Read it from a release with `codesign -dv MeetingRush.app 2>&1 | grep TeamIdentifier`.
The ID in brackets in the certificate's name is a different, per-person ID and fails the cask's check.

To check that a downloaded release was built by this workflow from this repository:

```sh
gh release download vX.Y.Z --repo meetingrush/meetingrush --pattern 'MeetingRush-*.zip'
gh attestation verify MeetingRush-X.Y.Z.zip --repo meetingrush/meetingrush \
    --signer-workflow meetingrush/meetingrush/.github/workflows/release.yml --source-ref refs/tags/vX.Y.Z
```

Until releases are notarised, this and the cask's `sha256` are the only checks on the download, because the cask removes the quarantine flag that would make Gatekeeper check it.

## Moving a Mac from the formula to the cask

Do this once on each Mac that installed MeetingRush with the old formula:

```sh
pkill -x MeetingRush
brew uninstall --formula meetingrush
rm -f ~/Applications/MeetingRush.app   # a symlink to the old install, if you made one
brew update
brew install --cask meetingrush/tap/meetingrush
open /Applications/MeetingRush.app
```

macOS asks for calendar access once more, because the signature has changed, and for keychain access if Google Calendar is connected.
Launch at login still points at the old install, so turn it off and on again in Settings.

If Spotlight still offers the old build, re-register the new app and drop the old record:

```sh
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
$LSREGISTER -f /Applications/MeetingRush.app
$LSREGISTER -gc
mdimport /Applications/MeetingRush.app
```

## Switching to a paid Developer ID

Once you join the Apple Developer Program:

1. In Xcode, **Manage Certificates… → + → Developer ID Application**.
   Export it as in setup step 2, and replace the `MACOS_CERTIFICATE_P12` and `MACOS_CERTIFICATE_PASSWORD` secrets in the `release` environment with it.
2. In App Store Connect, open **Users and Access → Integrations → App Store Connect API**, and generate a key with the **Developer** role.
   Download the `.p8` file (it can only be downloaded once) and note the key ID and issuer ID.
3. Add the notarisation secrets:

   ```sh
   gh secret set NOTARY_KEY_P8 --env release --repo meetingrush/meetingrush < AuthKey_XXXXXXXXXX.p8
   gh secret set NOTARY_KEY_ID --env release --repo meetingrush/meetingrush --body XXXXXXXXXX
   gh secret set NOTARY_ISSUER_ID --env release --repo meetingrush/meetingrush --body 00000000-0000-0000-0000-000000000000
   ```

4. Release as usual.
   The workflow notarises and staples the app when these secrets exist.
   A Developer ID release without them fails instead of shipping un-notarised.
5. In the tap, remove the cask's `postflight_steps`, which check the signing team and strip the quarantine flag.
   If you keep them for a while, update the team ID they check: a paid team has a different ID from the Personal Team.

The first Developer ID release asks for calendar access once more, because the certificate has changed.

## Troubleshooting

- **"The .p12 has no private key":** the exported file holds only the certificate.
  Export it again from **My Certificates**, check it as in setup step 2, and replace both secrets.
- **Keychain Access says the certificate is "not trusted", or `security find-identity -v -p codesigning` finds 0 valid identities:** Apple's WWDR G3 intermediate certificate isn't installed on that Mac.
  Only local signed builds need it, because the release workflow imports it itself:

  ```sh
  curl -fsSL https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer -o "$TMPDIR/AppleWWDRCAG3.cer"
  security add-certificates "$TMPDIR/AppleWWDRCAG3.cer"
  ```

- **"Expected one signing identity in the certificate, found: none":** the certificate didn't validate.
  Check it hasn't expired; a failed WWDR G3 download in the import step also causes this.
- **"Tag vX.Y.Z points at … which isn't on main":** the tag was made on a branch.
  Delete it, then tag the merge commit on `main`.
- **The app never asks for calendar access, or shows no meetings:** check the signature carries the calendar entitlement, which the hardened runtime requires:

  ```sh
  codesign -d --entitlements - /Applications/MeetingRush.app
  ```
