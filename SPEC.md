# CTRLS.zip — Project Spec

Living spec for `ctrls.zip`, a minimalist invite-only social network for the
CTRL+S friend group, styled as a desktop file browser. This file is the
source of truth going forward — update it whenever a product decision
changes, since the original concept docs are now historical context rather
than the current plan.

## Concept

Each user profile is a folder. Posts are "files" inside it: text (markdown),
audio messages, or images — no arbitrary uploads, and no video (dropped for
scope/complexity). You navigate the whole site like a file browser: nested
folders, a sidebar hierarchy tree, breadcrumb-style URLs, sortable contents.

It is explicitly not trying to scale, monetize, or collect real identity
info. No email, no phone number, no bio fields. You learn about a person
from what they put in their folder.

## Aesthetic

Solid orange background, white UI elements, retro/pixelated type — matches
the CTRL+S Discord server and podcast branding. Uploaded images are scaled to
440px wide and dithered client-side before upload (Game Boy Camera look, in
orange). Profile pictures are scaled to 100×100 and dithered the same way.

## Onboarding flow

1. A CTRL+S member hands out a physical, folder-shaped invite card in person
   (DIY-crafted). Each card is sequentially numbered (e.g. `#0042`) and hides
   a redemption code.
2. Recipient goes to `ctrls.zip/open`, enters the code.
3. Prompted "Who is this folder for?" (username field) with a "New User?"
   button.
   - New users: button opens the account-creation page in a new tab —
     handle, password, profile picture (dithered). This page is only
     reachable this way; it has no other entry point.
   - After account creation, the user returns to the original tab and
     enters their handle to claim the folder.
4. Claiming a folder lets the user set a codename and cover photo. The
   folder is already nested under whichever event/parent folder the card
   was distributed for (e.g. `momocon2026/`).

## Folder & file mechanics

- Folder contents (files) can be sorted by date or alphabetically.
- Sidebar shows the folder hierarchy tree, similar to a Windows file
  browser. URLs mirror the hierarchy.
- Files and folders can be moved via drag-and-drop on desktop. **On mobile,
  drag-and-drop is replaced with a "Move to…" menu** instead of trying to
  force touch-drag gestures.
- Comments can be left on individual files (not folders directly).
- Every folder has one attached live chat room (only the top-level folder in
  a hierarchy has a chat room — not each nested sub-folder).
- **Privacy:** a user can mark their folder private. Private folders are
  fully unlisted — they do not appear in any sidebar tree, hierarchy view,
  or home-page listing for other users, and are reachable only via direct
  link.
- **Editing/deletion:** users can edit and delete their own files, comments,
  and folders at any time while the folder is active.

## Event folders & zipping

- Special/event folders (e.g. `momocon2026`) are created by an admin ahead
  of an event and distributed via that event's invite cards.
- Once an event concludes, its parent folder is frozen: no more edits to
  anything inside it. It's archived to the "Filing Cabinet" page as
  `momocon2026.zip`.
- **Deletion still works after freezing** — users can delete their own
  files or their whole folder from a zipped archive at any time, they just
  can't edit or add anything new. Deleting a whole folder removes its
  attached chat room along with it (the two are one unit).
- The chat room(s) tied to a zipped folder/parent remain active and
  accessible to anyone who had an account during that folder's active
  window.
- Public (non-private) folders can be downloaded as a self-contained bundle:
  original file structure + a local `.html` viewer.
- **Tags are not a separate feature.** The original hashtag-style tag idea
  has fully merged into the event/parent-folder mechanic above — the folder
  hierarchy itself is the only categorization system.

## Home page

- Folders are sorted by activity; the longer a folder's been inactive, the
  further down the list it falls.
- Private folders never appear here.
- Hovering a folder shows user-submitted details plus stats (file count by
  type).

## Accounts

- No account deletion. Folders and chat history are a permanent archive —
  this is intentional, matching the "time capsule" goal, and keeps the
  build simpler (no orphaned-data cleanup logic needed).
- No password-recovery flow (no email collected, by design). A forgotten
  password means asking the admin to reset it via the dev portal.

## Dev/admin portal

- Site statistics and moderation tools.
- Folder-creation panel: generates a new event/parent folder, assigns it
  the next sequential number, and generates + assigns its redemption code.

## Technical architecture

- **Frontend:** static site (plain HTML/CSS/JS, no build step) hosted on
  **GitHub Pages**, using the `ctrls.zip` domain (already purchased via
  Squarespace Domains) pointed at it via DNS.
- **Backend:** **Firebase** free (Spark) tier —
  - Firestore for folders/files/comments/metadata
  - Firebase Realtime Database or Firestore for live chat
  - Firebase Storage for dithered images/audio
  - Firebase Authentication for login
- **Auth without email:** Firebase Auth's email/password provider is used,
  but with a synthesized internal address per handle (e.g.
  `handle@ctrls.zip.internal`) instead of a real email. This avoids ever
  collecting a real email while still getting Firebase's server-verified
  login and `request.auth`-based security rules.
- **No Cloud Functions / no Blaze plan.** Cloud Functions require Firebase's
  pay-as-you-go Blaze plan, which needs a card on file — explicitly avoided
  per the "no subscription/billing lock-in" requirement. Everything must be
  achievable with Firestore/Storage security rules plus client-side logic
  on the free Spark plan.
- **Dithering:** done client-side via `<canvas>` before upload (same idea
  as [ditherit-v2](https://github.com/alexharris/ditherit-v2)), both to save
  storage and for the intended visual style.
- **Video:** out of scope — photos, markdown text, and audio only.

## Open items / future considerations

- Moderation workflow specifics (what triggers a review, what actions the
  dev portal exposes) — not yet designed, can be fleshed out once the core
  build exists.
- Storage headroom on Firebase's free tier is generous for a friend-group
  scale site but isn't unlimited — worth keeping an eye on usage as the
  archive grows.
