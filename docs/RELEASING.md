# Releasing MeetingRush

MeetingRush ships as a Homebrew cask. Pushing a `vX.Y.Z` tag runs [the release workflow](../.github/workflows/release.yml),
which tests, builds, signs and zips `MeetingRush.app` and publishes it as a GitHub Release. The cask in
[meetingrush/homebrew-tap](https://github.com/meetingrush/homebrew-tap) points at that zip, and Homebrew installs the app
into `/Applications`.

Until the project has a paid Apple Developer ID, releases are signed with a free Apple Development certificate. It keeps
the app's signature the same from one release to the next, so macOS keeps its calendar and keychain permissions across
upgrades, but Gatekeeper doesn't accept it for downloaded apps. The cask therefore removes the quarantine flag after
installing, until releases are notarised.

## One-time setup

### 1. Create the signing certificate

1. In Xcode, open **Settings → Accounts**, click **+**, and sign in with your Apple ID. A free account shows up as
   **Your Name (Personal Team)**.
2. Select the Personal Team, click **Manage Certificates…**, then **+ → Apple Development**.
3. Note the certificate's full name, which the workflow signs with:

   ```sh
   security find-identity -v -p codesigning
   # 1) 0123ABCD… "Apple Development: Your Name (XXXXXXXXXX)"
   ```

### 2. Export it and add it to GitHub

1. In Keychain Access, open the **login** keychain, **My Certificates**, and find **Apple Development: Your Name**.
   Right-click it, choose **Export…**, save it as `AppleDevelopment.p12`, and set a strong password.
2. Add three repository secrets:

   ```sh
   base64 -i AppleDevelopment.p12 | gh secret set MACOS_CERTIFICATE_P12 --repo meetingrush/meetingrush
   gh secret set MACOS_CERTIFICATE_PASSWORD --repo meetingrush/meetingrush   # prompts for the export password
   gh secret set MACOS_CODESIGN_IDENTITY --repo meetingrush/meetingrush --body "Apple Development: Your Name (XXXXXXXXXX)"
   ```

3. Delete `AppleDevelopment.p12`.

Apple Development certificates expire after a year. When it does, create a new one and repeat this step; the next
release asks for calendar access once more.

Without these secrets the workflow still runs, signing ad-hoc, and every upgrade asks for calendar access again.

### 3. Optional: sign local builds the same way

To stop macOS asking for calendar access after every local rebuild, add the identity to an untracked `local.mk` in each
worktree:

```make
CODESIGN_IDENTITY := Apple Development: Your Name (XXXXXXXXXX)
```

## Releasing a version

1. On a new branch, set `VERSION` to the new version, then open a pull request and merge it.
2. Tag the merge commit and push the tag:

   ```sh
   cd ~/code/meetingrush
   git fetch --all
   git tag -a vX.Y.Z -m "MeetingRush X.Y.Z" origin/main
   git push origin vX.Y.Z
   ```

3. Follow the workflow with `gh run watch --repo meetingrush/meetingrush`. The run fails straight away if the tag
   doesn't match `VERSION`. When it finishes, the run's summary shows the `version` and `sha256` for the cask.
4. In a `homebrew-tap` worktree, update `version` and `sha256` in `Casks/meetingrush.rb`, check it, and open a pull
   request:

   ```sh
   brew style Casks/meetingrush.rb
   brew audit --cask --strict --online meetingrush/tap/meetingrush
   ```

5. Once it's merged, `brew upgrade --cask meetingrush` installs the new version.

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

macOS asks for calendar access once more, because the signature has changed.

If Spotlight still offers the old build, re-register the new app and drop the old record:

```sh
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
$LSREGISTER -f /Applications/MeetingRush.app
$LSREGISTER -gc
mdimport /Applications/MeetingRush.app
```

## Switching to a paid Developer ID

Once you join the Apple Developer Program:

1. In Xcode, **Manage Certificates… → + → Developer ID Application**. Export it as in setup step 2, and replace the
   `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD` and `MACOS_CODESIGN_IDENTITY` secrets with it.
2. In App Store Connect, open **Users and Access → Integrations → App Store Connect API**, and generate a key with the
   **Developer** role. Download the `.p8` file (it can only be downloaded once) and note the key ID and issuer ID.
3. Add the notarisation secrets:

   ```sh
   gh secret set NOTARY_KEY_P8 --repo meetingrush/meetingrush < AuthKey_XXXXXXXXXX.p8
   gh secret set NOTARY_KEY_ID --repo meetingrush/meetingrush --body XXXXXXXXXX
   gh secret set NOTARY_ISSUER_ID --repo meetingrush/meetingrush --body 00000000-0000-0000-0000-000000000000
   ```

4. Release as usual. The workflow notarises and staples the app when these secrets exist.
5. In the tap, remove the cask's `postflight` block that strips the quarantine flag.

The first Developer ID release asks for calendar access once more, because the certificate has changed.

## Troubleshooting

- **The build step fails with `errSecInternalComponent` or "unable to build chain":** the runner is missing Apple's
  intermediate certificate. Download **Apple Worldwide Developer Relations G3** from
  [Apple's certificate authority page](https://www.apple.com/certificateauthority/) and import it in the
  "Import the signing certificate" step.
- **The app never asks for calendar access, or shows no meetings:** check the signature still carries the calendar
  entitlement, which the hardened runtime requires:

  ```sh
  codesign -d --entitlements - /Applications/MeetingRush.app
  ```
