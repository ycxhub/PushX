# App Store Connect Setup Guide — PushX

## Prerequisites

- Apple Developer Program membership ($99/year) — enrolled and active
- Xcode installed with your Apple ID signed in
- App icon file: `docs/pushx-app-icon-1024.png` (1024x1024)

---

## Step 1: Create the App in App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Click **My Apps** → **+** (top left) → **New App**
3. Fill in:
   - **Platforms:** iOS
   - **Name:** PushX
   - **Primary Language:** English (U.S.)
   - **Bundle ID:** Select `com.pushupcoach.phase0` (must match Xcode project)
   - **SKU:** `pushx-ios-v1` (any unique string)
   - **User Access:** Full Access
4. Click **Create**

## Step 2: App Information

1. In the left sidebar, click **App Information**
2. Set:
   - **Subtitle:** AI Pushup Form Coach
   - **Category:** Health & Fitness
   - **Content Rights:** Does not contain third-party content
3. **Save**

## Step 3: Pricing and Availability

1. Click **Pricing and Availability** in the sidebar
2. Set **Price:** Free
3. **Availability:** All territories (or select specific countries)
4. **Save**

## Step 4: Privacy Policy

1. In **App Information**, scroll to **Privacy Policy URL**
2. Enter: `https://hard75.com/pushx/privacy-policy`
3. **Save**

## Step 5: App Privacy (Privacy Labels)

1. Click **App Privacy** in the sidebar
2. Click **Get Started**
3. For the question "Do you or your third-party partners collect data from this app?":
   - Select **No, we do not collect data from this app**
4. **Save** and **Publish**

This will display "Data Not Collected" on the App Store listing.

## Step 6: Age Rating

1. In your app version page, click **Age Rating**
2. Answer all questions — for PushX, all answers should be **No** (no violence, no gambling, etc.)
3. This should give you a **4+** rating
4. **Save**

## Step 7: App Version Information

1. Go to your app version (e.g., 0.1.0) in the sidebar
2. Fill in:
   - **Screenshots:** Upload for 6.7" and 6.1" (see screenshot guide below)
   - **Description:** Copy from `docs/app-store-description.md`
   - **Keywords:** `pushup,form,tracker,counter,workout,fitness,AI,coach,exercise,bodyweight,rep,training,form check`
   - **Support URL:** `https://hard75.com/pushx`
   - **Marketing URL:** (optional) `https://hard75.com/pushx`
   - **What's New:** First release. Real-time pushup tracking with AI form scoring, session history, and form trend charts.

## Step 8: Screenshots

You need screenshots for at least two device sizes:
- **6.7" Display** (iPhone 15 Pro Max / iPhone 16 Pro Max / iPhone 17 Pro Max)
- **6.1" Display** (iPhone 15 Pro / iPhone 16 Pro / iPhone 17 Pro)

### Recommended screenshots (4-6 per size):
1. **Home screen** — showing PushX branding and "Start Pushups" button
2. **Active workout** — camera view with rep counter and skeleton overlay
3. **Session summary** — form scores after a workout
4. **History view** — session list with trend chart
5. **Session detail** — per-rep breakdown
6. **Setup tips** — the phone placement instructions

### How to take them:
```bash
# Run on simulator, then use Cmd+S to save screenshot
# Or: xcrun simctl io booted screenshot ~/Desktop/pushx-screenshot-1.png
xcrun simctl io booted screenshot ~/Desktop/screenshot.png
```

## Step 9: Review Information

1. Scroll to **App Review Information**
2. Fill in:
   - **Contact info:** Your name, email, phone
   - **Notes for reviewer:** "PushX uses the front camera to detect pushup body pose in real time. To test: place the phone vertically against a wall at floor level, get into pushup position 2-3 feet away, and tap Start. The app will detect your body and count reps. All processing is on-device; no data is transmitted."
3. **Sign in required:** No (no account needed)

## Step 10: Submit for Review

After uploading a build (see archive-and-upload.md):
1. Select the uploaded build in the **Build** section
2. Click **Add for Review**
3. Click **Submit to App Review**

Review typically takes 24-48 hours.

---

## Deploy Privacy Policy to Vercel

The site uses `privacy-policy/vercel.json`:

- **`/`** → **308 redirect** to **`/pushx/`** so `hard75.com` and `hard75.com/pushx/` show the same marketing page (`pushx/index.html`).
- **`/pushx/privacy-policy`** → rewrite to **`/index.html`** (plain-text privacy policy at repo root `privacy-policy/index.html`).

```bash
cd privacy-policy
npx vercel --prod
```

When prompted:
- **Project name:** hard75-pushx
- **Directory:** `./`
- **Framework:** Other

Then in Vercel dashboard → Project Settings → Domains, add `hard75.com` and configure the rewrite so `/pushx/privacy-policy` serves the page.

Alternatively, deploy the `privacy-policy/` folder as a subdirectory of your existing hard75.com Vercel project.
