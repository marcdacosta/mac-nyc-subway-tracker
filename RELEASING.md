# Releasing Mac NYC Subway Tracker

## One-time Apple setup

1. Open **Xcode → Settings → Accounts** and add the Apple ID enrolled in the Apple Developer Program.
2. Select the Developer Program team, open **Manage Certificates**, and create a **Developer ID Application** certificate.
3. Create an app-specific password for the Apple ID.
4. Store the notarization credentials in Keychain, replacing the placeholders:

   ```sh
   xcrun notarytool store-credentials "mac-nyc-subway-tracker" \
     --apple-id "APPLE_ID" \
     --team-id "TEAM_ID"
   ```

   `notarytool` securely prompts for the app-specific password. Do not place the password in this repository or in a shell script.

## Build the release

Find the exact certificate name with:

```sh
security find-identity -v -p codesigning
```

Then build, sign, notarize, staple, and package the release:

```sh
CODE_SIGN_IDENTITY="Developer ID Application: NAME (TEAM_ID)" \
NOTARY_PROFILE="mac-nyc-subway-tracker" \
make release
```

The command creates:

```text
.build/releases/Mac-NYC-Subway-Tracker-v0.1.0-universal.zip
.build/releases/Mac-NYC-Subway-Tracker-v0.1.0-universal.zip.sha256
```

The ZIP contains a Universal 2 app for Apple Silicon and Intel Macs. The script verifies the code signature before packaging and waits for Apple's notarization result.

## Publish on GitHub

Create the release from the same version recorded in `App/Info.plist`:

```sh
gh release create v0.1.0 \
  .build/releases/Mac-NYC-Subway-Tracker-v0.1.0-universal.zip \
  .build/releases/Mac-NYC-Subway-Tracker-v0.1.0-universal.zip.sha256 \
  --title "Mac NYC Subway Tracker v0.1.0" \
  --generate-notes
```

After publishing, download the GitHub asset on a different Mac when possible and confirm that Gatekeeper opens it without an override.
