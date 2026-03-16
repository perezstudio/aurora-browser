# Aurora — Direct Distribution Setup Guide

## Overview

Aurora ships as a **signed + notarized .dmg** via direct distribution.
Updates are delivered through **Sparkle 2** with Ed25519 signatures.

---

## 1. Apple Developer Account Setup

### Certificate

You need a **Developer ID Application** certificate (not Mac App Distribution).

1. Open **Xcode → Settings → Accounts → Manage Certificates**
2. Click **+** → **Developer ID Application**
3. Xcode creates and installs it in your Keychain automatically

For CI, export the certificate:
```bash
# Find the cert name
security find-identity -v -p codesigning | grep "Developer ID"

# Export as .p12
security export \
  -k ~/Library/Keychains/login.keychain-db \
  -t identities \
  -f pkcs12 \
  -P "your-export-password" \
  -o developer_id.p12

# Base64 encode for GitHub Secret
base64 -i developer_id.p12 | pbcopy
```

Paste the copied value into GitHub Secret: `DEVELOPER_ID_APPLICATION_CERT_P12`

---

## 2. Notarization credentials

Create an **App-Specific Password** at https://appleid.apple.com/account/manage
(not your main Apple ID password — a dedicated one for CI).

GitHub Secrets to set:
| Secret | Value |
|--------|-------|
| `NOTARIZATION_APPLE_ID` | your@apple.id |
| `NOTARIZATION_PASSWORD` | App-specific password |
| `NOTARIZATION_TEAM_ID` | 10-char team ID from developer.apple.com/account |

---

## 3. Sparkle 2 Setup

### Add via Swift Package Manager

In Xcode: **File → Add Package Dependencies**
```
https://github.com/sparkle-project/Sparkle
```
Select version `2.x.x`, add to **Aurora** target.

### Embed XPC Services

In Xcode, select the **Aurora** target → **Build Phases** → **Copy Bundle Resources**.
Add both XPC services from the Sparkle package:
- `Autoupdate.xpc`
- `Downloader.xpc`

These must be at `Aurora.app/Contents/XPCServices/`.

### Generate Ed25519 key pair

```bash
# Find sign_update inside resolved Sparkle package
cd YourProject
find .build -name "generate_keys" -type f | head -1

# Run it — stores private key in Keychain, prints public key
./path/to/generate_keys
```

Copy the **public key** output into `Info.plist` → `SUPublicEDKey`.

Store the **private key** as GitHub Secret `SPARKLE_PRIVATE_KEY`:
```bash
# Export from Keychain
security find-generic-password \
  -s "Sparkle Key" \
  -w | pbcopy
```

---

## 4. Xcode Build Settings

| Setting | Value |
|---------|-------|
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.yourcompany.aurora` |
| `CODE_SIGN_IDENTITY` | `Developer ID Application` |
| `CODE_SIGN_STYLE` | `Manual` |
| `DEVELOPMENT_TEAM` | Your 10-char team ID |
| `SWIFT_OBJC_BRIDGING_HEADER` | `Aurora/Distribution/Aurora-Bridging-Header.h` |
| `INFOPLIST_FILE` | `Aurora/Info.plist` |
| `ENABLE_HARDENED_RUNTIME` | `YES` |
| `CODE_SIGN_ENTITLEMENTS` | `Aurora/Distribution/Aurora.entitlements` |

---

## 5. Hosting the appcast

Host `appcast.xml` at the URL in `SUFeedURL`. Any static host works:
- **GitHub Pages** — free, reliable, version-controlled alongside the app
- **Cloudflare R2** — free tier covers the traffic
- **Your own server**

### Updating the appcast after a release

```bash
# 1. Build + notarize DMG (CI does this)

# 2. Get file size
stat -f %z Aurora-1.1.0.dmg

# 3. Sign the DMG
./bin/sign_update Aurora-1.1.0.dmg
# → prints: edSignature="abc123..."

# 4. Edit appcast.xml:
#    - Add new <item> at top
#    - Set sparkle:edSignature, length, url
#    - Bump sparkle:version (integer)

# 5. Push appcast.xml to your hosting
```

---

## 6. First Release Checklist

- [ ] Developer ID certificate created and installed
- [ ] `YOURTEAMID` replaced in `ExportOptions.plist`
- [ ] `com.yourcompany.aurora` bundle ID set everywhere
- [ ] `SUFeedURL` points to your real appcast URL
- [ ] `SUPublicEDKey` contains the generated public key
- [ ] Sparkle XPC services embedded in app bundle
- [ ] All 5 GitHub Secrets set
- [ ] `appcast.xml` hosted and reachable
- [ ] `length` attribute in appcast set to actual DMG byte size
- [ ] `sparkle:edSignature` in appcast matches the signed DMG
- [ ] Test: download the DMG on a fresh Mac, verify Gatekeeper passes
- [ ] Test: launch app, trigger "Check for Updates", verify Sparkle connects

---

## 7. Signing the update manually (without CI)

```bash
# From your project root after SPM resolves
SIGN=".build/checkouts/Sparkle/bin/sign_update"

# Sign DMG
$SIGN /path/to/Aurora-1.1.0.dmg
# Copy the edSignature value → paste into appcast.xml

# Sign delta (if using delta updates)
$SIGN /path/to/Aurora-1.0.0-1.1.0.delta
```

---

## 8. Creating delta updates (optional but recommended)

Delta updates let users download only the diff (~90% smaller):

```bash
DELTA=".build/checkouts/Sparkle/bin/BinaryDelta"

# Extract old and new .app from archives
$DELTA create \
  /path/to/OldAurora.app \
  /path/to/NewAurora.app \
  Aurora-1.0.0-1.1.0.delta

# Sign the delta
.build/checkouts/Sparkle/bin/sign_update Aurora-1.0.0-1.1.0.delta
```

Add the delta as `<sparkle:deltas>` inside the `<item>` in `appcast.xml`.

---

## Troubleshooting

**Gatekeeper blocks app on first launch**
→ Check notarization completed: `xcrun stapler validate Aurora.app`

**Sparkle says "No valid update found"**
→ Verify `SUFeedURL` is reachable, XML is valid, `sparkle:version` integer is higher than `CFBundleVersion`

**Sparkle signature invalid**
→ Ensure the public key in `Info.plist` matches the private key used to sign
→ Re-run `generate_keys` if unsure — you'll need to re-sign all past DMGs
