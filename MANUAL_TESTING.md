# Manual Testing Guide — TTS Bandmate

Step-by-step checks for human testers (QA). No coding required. Work through the
sections in order; the early sections set up accounts/bands the later ones need.

## Before you start

- **Platforms to cover:** iOS, Android, Linux desktop, and web (Chrome). Note
  which one you tested on for every bug you file.
- **Test accounts:** use a throwaway email you can receive mail at. Have a
  second account handy for invite/join testing.
- **Reset state:** to retest onboarding, log out (More tab → Sign Out) or
  reinstall / clear app data so you start logged out.
- **Reporting a bug, include:** platform + OS version, what you did
  (numbered steps), what you expected, what actually happened, and a
  screenshot/recording. Note the date/time and the account/band used.

## How to read each test

Each check is **Do this → Expect this**. If the result differs, it's a bug.
"✅" = pass, "❌" = file a bug.

---

## 1. Sign up (new account)

1. Launch the app while logged out → you land on the **Sign In** screen.
2. Tap **Sign up**.
3. Leave fields blank and tap **Create Account** → each empty field shows a
   validation message; no account is created.
4. Enter mismatched passwords → you get a "passwords don't match" style error.
5. Enter a valid name, email, password, and matching confirm → account is
   created and you're taken to the next step (path selection or band setup).
6. Try signing up again with the **same email** → you get a clear "email already
   in use" error, not a crash.

## 2. Log in / log out

1. From **Sign In**, tap **Sign In** with both fields empty → "Please enter your
   email." appears.
2. Enter an invalid email format (e.g. `not-an-email`) → "Enter a valid email
   address." appears.
3. Enter a valid email but no password → "Please enter your password." appears.
4. Enter wrong credentials → a clear "invalid credentials" error, fields stay
   filled, no crash.
5. Tap the **eye icon** on the password field → password text toggles between
   hidden and visible.
6. Enter correct credentials with **extra spaces around the email** → login
   succeeds (email is trimmed).
7. Log in successfully → you proceed past login (to band selection or
   dashboard).
8. Go to **More → Sign Out** → you return to the Sign In screen and cannot get
   back to app content with the back gesture/button.
9. Close and reopen the app after a successful login → you stay logged in
   (no need to re-enter credentials).

## 3. Bands: selection, create, join

1. **No band yet:** after first login you're prompted to set up / pick a band.
2. **Single band:** if your account has exactly one band, it auto-selects and
   drops you straight on the Dashboard.
3. **Multiple bands:** you see a band picker; choosing one opens the Dashboard
   for that band.
4. **Create a band:** go to the create-band flow, enter a name, save → the band
   is created and becomes the active band.
5. **Join a band:** use the join flow (invite code / QR). A valid code joins you
   to the band; an invalid one shows a clear error.
6. **Switch bands:** change the active band (band selector) → Dashboard,
   Bookings, Library, etc. all refresh to show the newly selected band's data,
   not the previous band's.
7. Confirm the currently selected band is clearly indicated in the UI.

## 4. Bottom navigation (5 tabs)

The tab bar has: **Dashboard, Search, Bookings, Library, More**.

1. Tap each tab → the correct screen opens and that tab shows as selected
   (highlighted/filled icon).
2. Navigate into a detail screen, then switch tabs and come back → the tab
   returns you to a sensible state.
3. Re-open the app after navigating somewhere → it restores you to a reasonable
   last location (route is remembered).

## 5. Dashboard

1. Open **Dashboard** → it loads without spinning forever; upcoming
   events/bookings are shown.
2. If there's a **calendar / filter** control, open the filter sheet, apply a
   filter → the list updates accordingly; clear it → list returns.
3. With **multiple bands**, confirm the calendar/filter can scope by band and
   the markers/events match the selected band(s).
4. Empty state: an account/band with nothing scheduled shows a friendly empty
   message, not a blank or broken screen.

## 6. Search

1. Open **Search**, type a query → relevant results appear.
2. Search a term with **no matches** → a clear "no results" state, no crash.
3. Clear the query → the screen returns to its default/empty state.

## 7. Bookings

1. Open **Bookings** → list loads for the active band.
2. **Create:** start a new booking, fill required fields (name, date, etc.),
   save → it appears in the list. Try saving with a required field blank →
   validation blocks it.
3. **Detail:** open a booking → details render (venue, date, price, contacts).
   Check that a booking with **no price** shows `$0.00` and a paid booking shows
   the correct formatted amount.
4. **Edit:** change a field, save → the change persists after leaving and
   reopening.
5. **Contacts:** add/edit a contact on a booking → it saves and shows.
6. **Payments:** open payments, add a payment → totals/amounts update correctly.
7. **Contract:** open the contract screen → it loads/displays as expected.
8. **History:** open booking history → past entries display.
9. **Multi-band:** with multiple bands, confirm bookings only show for the band
   they belong to and switching bands swaps the list.

## 8. Library (charts)

1. Open **Library** → charts load for the active band.
2. **Filter:** open the filter sheet, apply filters → the list narrows; clear →
   it restores.
3. **Create chart:** add a new chart (title required, optional composer,
   description, price, public toggle) → it appears in the list with the correct
   band tag.
4. **Detail:** open a chart → details and any uploads display.
5. **Delete:** delete a chart → it disappears from the list and stays gone after
   refresh.
6. **Public/private:** toggle works and is reflected on the chart.

## 9. Events

1. Open an event (from Dashboard or a booking) → detail screen loads.
2. **Edit:** change event fields, save → changes persist.
3. **Attire / details rows** render correctly.
4. **Attachments:** view/add attachments where supported.

## 10. Live setlist session

1. From an event, open the **live session / setlist** screen.
2. Confirm it loads the setlist and you can move through songs/charts.
3. If real-time is in use, with two devices on the same event, an action on one
   should reflect on the other (real-time sync).

## 11. Rehearsals, Media, Finances, Band Settings

1. **Rehearsals:** list loads; open a rehearsal detail → renders correctly.
2. **Media:** open the media screen; open a media item in the viewer → it
   displays/plays; back returns to the list.
3. **Finances:** open Finances → figures load without error.
4. **Band Settings:** open from More. Edit band info → saves. Open member
   permissions → members list and permission toggles work. Only owners/admins
   should see/edit settings they're allowed to.

## 12. Offline & connectivity

1. Turn off network (airplane mode / disable wifi) while in the app → an
   **offline banner** appears.
2. Restore the network → a brief **"back online"** indication appears, then
   normal operation resumes.
3. Trigger an action that needs the network while offline → you get a clear
   error, not a silent hang or crash.

## 13. Session expiry / auth errors

1. If your session token becomes invalid/expired (or is revoked server-side),
   the next action should bounce you to the **Sign In** screen rather than
   showing broken/empty data.

## 14. Cross-platform & polish pass

On each platform you test, sanity-check:

- Layout isn't cut off, overlapping, or stretched (try narrow phone and wide
  desktop/web windows).
- Text is readable; tap targets are reachable.
- Back navigation and the device/browser back button behave sensibly.
- No placeholder text, broken images, or obvious console/UI errors.
- Pull-to-refresh / refresh controls actually refresh the data.

---

## Quick regression checklist

Use this for a fast pass before a release:

- [ ] Sign up new account
- [ ] Log in (wrong then right credentials)
- [ ] Select / switch band
- [ ] Dashboard loads with data
- [ ] Create + edit a booking
- [ ] Add a payment to a booking
- [ ] Create + delete a library chart
- [ ] Open an event and its live setlist
- [ ] Search returns results
- [ ] Offline banner appears and clears
- [ ] Edit band settings
- [ ] Sign out returns to login
