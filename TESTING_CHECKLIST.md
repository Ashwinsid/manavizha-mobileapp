# Manavizha Mobile — Manual Testing Checklist

Covers everything changed in the web-parity work: server-enforced actions,
encrypted messaging, photo privacy, partner preferences, browse filters, deep
links and the horoscope engine fix.

Most items need a **real device or emulator with internet**, because the app now
calls the deployed web API rather than writing Supabase tables directly.

---

## 0. Before you start

- [ ] SQL migration applied in Supabase (`user_keys.private_key` column exists) — **already done**
- [ ] `manavizha://auth-callback` added in Supabase → Authentication → URL Configuration → Redirect URLs
- [ ] Web app deployed with the latest changes (`/api/keys`, `lib/e2e.ts`, `lib/astrology.ts`)
- [ ] Mobile app built against the right API host
      (defaults to `https://manavizha.com`; for staging build with
      `--dart-define=WEB_APP_BASE_URL=https://your-staging-host`)
- [ ] `flutter analyze` clean and `flutter test` passing (8/8)

### Test accounts to prepare

| Account | Purpose |
|---|---|
| **A** — female, **premium** | main test account |
| **B** — male, **premium** | the other side of every interaction |
| **C** — male, **free tier** | premium gating and contact-view limit tests |
| **D** — admin | verify reports arrive in the moderation queue |

A and B must be opposite genders so they appear in each other's browse results.

> ⚠️ Many tests need you to act on **two accounts**. Two devices (or one device
> + the website) is much faster than logging in and out.

---

## 1. Sign up & authentication

- [ ] **New signup** → after submitting, a "Verify your email" dialog appears showing the entered email
- [ ] Dismissing it returns to the login screen with the email prefilled
- [ ] The confirmation email arrives; opening the link **opens the app** (not the browser)
- [ ] **Forgot password** on the login screen opens a dialog, prefilled with any typed email
- [ ] Submitting shows "If an account exists… a reset link has been sent"
- [ ] The reset email link **opens the app** and lands on the "Set a new password" screen
- [ ] Password validation rejects: under 11 chars, no uppercase, no lowercase, no number, no symbol, mismatched confirm
- [ ] A valid new password saves, shows a success toast, and lands on the correct dashboard
- [ ] Logging in with the **new** password works; the old password is rejected
- [ ] Settings → Change Password still sends a reset link that opens the app

---

## 2. Interests / likes — *cross-platform*

- [ ] A sends interest to B from the browse card → success, card shows liked state
- [ ] **B receives an in-app notification** (bell) and an email
- [ ] The interest appears in B's Likes tab → Received (pending)
- [ ] **Send interest on the WEB from B → it appears in the MOBILE Likes tab for A**
- [ ] **Accept on MOBILE an interest that was sent from WEB** → works
- [ ] After accepting, the sender gets an `interest_accepted` notification + email
- [ ] The pair now shows as **Mutual** on both mobile *and* web
- [ ] Decline works and the pair does not become mutual
- [ ] Sending interest twice shows "You already sent interest to this profile" (no crash)
- [ ] Withdraw interest removes the row on both platforms

---

## 3. Blocking — *enforcement is the point*

- [ ] A blocks B → B disappears from A's browse list
- [ ] Settings → Blocked Profiles lists B; unblock works and B reappears
- [ ] While blocked, **B cannot send interest to A** → error message, no row created
- [ ] While blocked, **B cannot send a message to A** → refused
- [ ] While blocked, **contact details are refused** for both directions

> Before this work the mobile app bypassed these checks entirely — this section
> is the highest-value regression test in the document.

---

## 4. Shortlists

- [ ] Shortlist a profile from a browse card → success
- [ ] **The shortlisted member receives a `profile_shortlisted` notification**
- [ ] The profile appears under the "Shortlisted" browse category
- [ ] Un-shortlisting removes it
- [ ] Shortlisting an already-shortlisted profile shows "Already on your shortlist"
- [ ] A profile shortlisted on the **web** shows as shortlisted on **mobile**

---

## 5. Messaging + encryption — *cross-platform*

Requires a mutual match between A and B, and a premium sender.

- [ ] **Free account C cannot send** → premium upgrade prompt, message not sent
- [ ] Premium A can send to mutual match B
- [ ] **B receives a `message_received` notification**
- [ ] Message appears in B's inbox and thread, with correct read receipts
- [ ] Realtime: with the thread open on both sides, a new message appears without refreshing
- [ ] Messaging a **declined** interest is refused
- [ ] Messaging a **blocked** member is refused

### Encryption (after web deploy)

- [ ] Open the **web** messages page once as each of A and B (uploads their key)
- [ ] Send a message **from web** → **it opens as readable text on mobile** ✅
- [ ] Send a message **from mobile** → **it opens as readable text on web** ✅
- [ ] Conversation list previews show readable text, not ciphertext
- [ ] Tamil text and emoji survive the round trip intact
- [ ] Log out and back in → history still readable
- [ ] Log in as a *different* account on the same device → you do **not** see the previous account's decrypted messages

> If a message shows `🔒 Encrypted message`, the sender's key hasn't synced yet —
> open the web messages page as that user once, then reload mobile.

---

## 6. Contact details & tier limits

- [ ] **Free account C**: opening a mutual match's contact sheet shows the locked
      card with an upgrade message — **no phone number visible**
- [ ] **Premium account**: contact details reveal correctly (phone, WhatsApp, address)
- [ ] The profile owner receives a `contact_viewed` notification the first time
- [ ] Re-opening the same profile's contact does **not** consume another unlock
- [ ] After hitting the plan limit, further profiles show "You have reached your contact-view limit…"
- [ ] Phone tap opens the dialer; WhatsApp tap opens WhatsApp; long-press copies

---

## 7. Photo privacy

### As the profile owner (account B)

- [ ] Settings → Privacy Settings now has a **Photo privacy** section
- [ ] Setting **"Visible to everyone"** saves
- [ ] Setting **"Only after accepted interest"** saves
- [ ] Setting **"Protected with a password"** prompts for a password and saves
- [ ] An empty password is rejected

### As a viewer (account A, no accepted interest with B)

- [ ] B set to **everyone** → photos display normally
- [ ] B set to **on_accept** → photos are blurred with a lock and a **"Request photos"** button
- [ ] Tapping it sends the request; the button becomes **"Request pending"**
- [ ] **B receives a `photo_request` notification**
- [ ] B opens A's profile → an amber **"Photo request"** banner with Approve / Decline
- [ ] **Approve** → A gets a `photo_request_approved` notification; reopening B's profile shows photos unblurred
- [ ] **Decline** → A sees "Request declined"
- [ ] B set to **password** → viewer sees "Enter password"; a wrong password shows "Incorrect password"; the correct password unblurs the photos
- [ ] Once A and B have a **mutual accepted interest**, `on_accept` photos are visible without a request
- [ ] Your **own** photos are never blurred on your own profile

---

## 8. Report a profile

- [ ] Profile → overflow (⋮) menu now has **Report member**
- [ ] All six reasons are selectable (fake profile, harassment, inappropriate content, scam, already married, other)
- [ ] Optional details field accepts text
- [ ] Submitting shows "Report submitted. Our team will review this profile."
- [ ] **The report appears in the web admin moderation queue** (account D)
- [ ] The admin email notification is received
- [ ] Reporting the same profile twice shows "You have already reported this profile"
- [ ] Block still works and still pops back to the previous screen

---

## 9. Profile views

- [ ] A opens B's profile → **B sees A under "Who Viewed Me"** on the dashboard (and on web)
- [ ] A's dashboard shows B under "Profiles I Viewed"
- [ ] Opening the same profile repeatedly within an hour does not create duplicates
- [ ] Viewing **your own** profile records nothing

---

## 10. Partner preferences (new screen)

- [ ] Drawer → **Preferences** opens the new screen (no longer a "use the website" message)
- [ ] Radial FAB menu → **Preferences** opens it too
- [ ] With no saved preferences, fields are **pre-filled** from your own profile (age ±5, height ±15, religion, caste, star…)
- [ ] All three sections render: Basic & lifestyle, Religious & horoscope, Professional & location
- [ ] Age and height ranges accept numbers
- [ ] Single-select pickers work (marital status, physical status, eating/smoking/drinking, religion, caste, star, raasi, dosham, income, country, state, city)
- [ ] Multi-select pickers work (languages, education level, degrees, specialization, employed in, occupation)
- [ ] **Subcaste is disabled until a caste is chosen**, then lists only that caste's subcastes
- [ ] Changing caste resets subcaste
- [ ] Selecting education levels **narrows the degree list**
- [ ] "Caste is compulsory" toggle is disabled until a caste is selected
- [ ] **Save** shows a success toast and returns to the previous screen
- [ ] Reopening shows the saved values
- [ ] **The same values appear on the web** `/dashboard/preferences`
- [ ] Saved preferences affect browse results when "Preferences" is toggled on

---

## 11. Browse filters (new)

- [ ] A **Filters** button appears next to the Preferences toggle
- [ ] Tapping it opens the filter sheet
- [ ] Age from/to filters the list
- [ ] Caste filters; subcaste is disabled until a caste is picked
- [ ] College education filters
- [ ] Marital status filters
- [ ] **With photo** toggle hides photo-less profiles
- [ ] **Verified profile** toggle shows only verified profiles
- [ ] The button changes to **"Filters on"** (filled) while filters are active
- [ ] **Clear** resets every field
- [ ] Filters combine correctly with the category chips and the search box
- [ ] The profile count above the list updates
- [ ] Filters and the Preferences toggle work together

---

## 12. Browse pool (cap removed)

- [ ] If the database has more than 150 opposite-gender profiles, **mobile now shows more than 150**
- [ ] Browse still loads in reasonable time
- [ ] The mobile result count is comparable to the web browse page

---

## 13. Horoscope (engine fix) — *verify against web*

- [ ] Generate a horoscope on mobile for a **specific birth date/time/place**
- [ ] Generate the **same** birth details on the **web**
- [ ] **Star (nakshatra) matches**
- [ ] **Rashi matches**
- [ ] **Lagnam matches**
- [ ] Planet placements in the South Indian chart match
- [ ] Dasa periods match
- [ ] Repeat for a **pre-2000 birth date** (this is where the web bug was — both should now agree)
- [ ] Repeat with **Vakkiyam** method selected
- [ ] Test a **late-evening birth time** (e.g. 23:45) — the timezone fix mattered most here
- [ ] Member mode still pre-fills birth details from the signed-in profile
- [ ] PDF download still works
- [ ] Porutham / compatibility sheet still scores correctly

---

## 14. Settings (now server-validated)

- [ ] Email alert toggles save and persist after reopening
- [ ] SMS alert toggles save
- [ ] Call preference saves
- [ ] Mobile privacy, horoscope privacy, profile visibility all save
- [ ] **Deactivate** for a chosen duration works; the profile disappears from others' browse
- [ ] **Reactivate** restores visibility
- [ ] **Mark as Married** asks for confirmation, then signs out to the welcome screen
- [ ] Ignored and Blocked lists load and un-ignore / unblock inline
- [ ] Every change is reflected on the **web** settings page

---

## 15. Regression smoke test

Areas touched indirectly — confirm nothing broke:

- [ ] Splash → role routing still lands admins, partners, parents and members on the right home
- [ ] Dashboard loads: completion ring, daily recommendations, activity carousels
- [ ] Profile setup / edit still saves all sections
- [ ] Photo upload still works
- [ ] Identity verification (selfie) still submits
- [ ] Notification bell still populates and marks read
- [ ] Pricing screen and WhatsApp upgrade link still work
- [ ] Parent management: create / remove parent logins
- [ ] Parent selections screen loads
- [ ] Admin screens: stats, profiles, verification queue, master data, accounts
- [ ] Referral partner screens load
- [ ] Log out works from every role

---

## Known expected behaviour (not bugs)

- Notifications only arrive **while the app is open** — push notifications (FCM) are not implemented yet.
- Horoscope OCR upload is absent on mobile. The web's OCR button also discards its result, so nothing is actually missing.
- Pricing has no in-app payment on either platform by design — upgrades go through WhatsApp/admin.
- A `🔒 Encrypted message` placeholder means the other party's key hasn't synced yet, not a failure.
- Admin **reports queue**, **tier-limit configuration** and **analytics** are web-only.

---

## Sign-off

| | |
|---|---|
| Tested by | |
| Build / version | |
| Date | |
| Devices (Android / iOS versions) | |
| API host | |
| Blocking issues found | |
