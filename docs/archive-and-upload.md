# Archive & Upload to App Store Connect — PushX

## Prerequisites

- Xcode with your Apple Developer account signed in
- App Store Connect app created (see `app-store-connect-setup.md`)
- Bundle ID in Xcode matches App Store Connect: `com.pushupcoach.phase0`
- A physical device or "Any iOS Device" selected as build destination

---

## Step 1: Set Version and Build Number

1. Open `PushupCoach.xcodeproj` in Xcode
2. Select the **PushupCoach** target → **General** tab
3. Set:
   - **Display Name:** PushX
   - **Version:** 0.1.0
   - **Build:** 1

For subsequent uploads, increment **Build** (e.g., 2, 3, ...) while keeping **Version** the same until you're ready for a new version.

## Step 2: Set the App Icon

1. In the Project Navigator, open `PushupCoach/Assets.xcassets`
2. Click **AppIcon**
3. Drag `docs/pushx-app-icon-1024.png` (1024x1024) into the **App Store 1024pt** slot
4. Xcode automatically generates all required sizes from the 1024x1024 source

If using Xcode 15+ with the single-size icon feature, you only need the 1024x1024 image.

## Step 3: Select the Archive Destination

1. In the Xcode toolbar, click the device/simulator dropdown
2. Select **Any iOS Device (arm64)** — NOT a specific simulator
   - You cannot archive for a simulator; it must target a real device architecture

## Step 4: Configure Signing

1. Select the **PushupCoach** target → **Signing & Capabilities**
2. Ensure:
   - **Automatically manage signing** is checked
   - **Team** is set to your Apple Developer team
   - **Bundle Identifier** is `com.pushupcoach.phase0`
3. If you see signing errors, check that your Developer Program membership is active

## Step 5: Archive

1. In the menu bar: **Product → Archive**
   - Shortcut: there is no default shortcut; use the menu
2. Xcode will build the app in Release configuration
3. When complete, the **Organizer** window opens showing your archive

If the archive fails:
- Check for build errors in the Issue Navigator
- Ensure you're targeting "Any iOS Device" not a simulator
- Verify all signing certificates are valid

## Step 6: Validate

1. In the Organizer, select your archive
2. Click **Validate App**
3. Choose:
   - **Distribution method:** App Store Connect
   - **Destination:** Upload
   - **Signing:** Automatically manage signing
4. Click **Validate**
5. Fix any validation errors before proceeding

Common validation issues:
- Missing app icon → see Step 2
- Missing Info.plist keys → ensure `NSCameraUsageDescription` is set
- Invalid provisioning profile → re-check signing

## Step 7: Upload (Distribute)

1. In the Organizer, with your archive selected, click **Distribute App**
2. Choose:
   - **Method:** App Store Connect
   - **Destination:** Upload
3. Follow the prompts (signing, entitlements review)
4. Click **Upload**
5. Wait for the upload to complete (may take 2-5 minutes depending on app size)

## Step 8: Wait for Processing

After upload:
1. Go to [App Store Connect](https://appstoreconnect.apple.com) → your app
2. The build will show as **Processing** for 5-30 minutes
3. Once processing completes, the build appears in the **Builds** section of your app version
4. You may receive an email about any compliance issues (e.g., encryption)

## Step 9: Select Build and Submit

1. In App Store Connect, go to your app version
2. In the **Build** section, click **+** and select your uploaded build
3. Fill in any remaining required fields (screenshots, description, etc.)
4. Click **Add for Review** → **Submit to App Review**

## Step 10: TestFlight (While Waiting for Review)

TestFlight is available immediately after upload — you don't need to wait for App Store review.

1. In App Store Connect → **TestFlight** tab
2. Your build appears after processing
3. **Internal Testing:**
   - Add yourself and team members (up to 100)
   - They get access immediately
4. **External Testing (for your WhatsApp group):**
   - Create a **New Group** (e.g., "Beta Testers")
   - Click **+** to add testers by email
   - Or click **Enable Public Link** to generate a shareable TestFlight link
   - Share the public link in your WhatsApp group
   - External testing requires a brief Beta App Review (usually <24 hours)

### TestFlight public link approach (recommended for WhatsApp):
1. TestFlight → Your build → External Testing
2. Create group → Enable Public Link
3. Copy the link (looks like `https://testflight.apple.com/join/XXXXXX`)
4. Share in your WhatsApp group with a message like:

> "Hey! I built a pushup form tracker that uses AI to watch you do pushups and score your form. Would love your feedback. Download via TestFlight: [link]. Place your phone against a wall, get into pushup position, and tap Start."

---

## Quick Reference

```bash
# Check build settings from command line (optional)
xcodebuild -project PushupCoach.xcodeproj -scheme PushupCoach -showBuildSettings | grep -E "PRODUCT_BUNDLE_IDENTIFIER|MARKETING_VERSION|CURRENT_PROJECT_VERSION"

# Archive from command line (alternative to Xcode UI)
xcodebuild -project PushupCoach.xcodeproj \
  -scheme PushupCoach \
  -sdk iphoneos \
  -configuration Release \
  -archivePath ./build/PushupCoach.xcarchive \
  archive

# Export for App Store upload
xcodebuild -exportArchive \
  -archivePath ./build/PushupCoach.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath ./build/export
```

Note: The Xcode UI approach (Steps 5-7) is simpler and recommended for the first upload.
