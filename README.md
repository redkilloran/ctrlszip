# CTRLS.zip

A minimalist, invite-only social network for the CTRL+S friend group,
styled as a desktop file browser. See [SPEC.md](SPEC.md) for the full
product spec — that's the source of truth for how this is supposed to
work.

## Stack

- Static frontend (plain HTML/CSS/JS, no build step) → **GitHub Pages**
- **Supabase** (free tier) → Postgres database, Storage, Realtime chat, Auth

No paid tiers, no billing account, no credit card on file anywhere.

## Status

Scaffolding only right now — page shells and TODOs, no real Supabase
wiring yet. Nothing here talks to a real Supabase project until you've
done the one-time setup below.

## One-time setup (things only you can do — need your own accounts)

1. **Create a Supabase project.**
   - Go to https://supabase.com and sign up (you can use a GitHub login,
     which is convenient since you'll need a GitHub account for step 3
     anyway).
   - Click **New Project**. Give it a name (e.g. `ctrls-zip`), generate a
     database password (Supabase will offer to do this for you — just
     save it somewhere, you likely won't need it day-to-day), and pick a
     region close to you. No card is required for the Free plan.
   - Once it finishes provisioning, go to **Project Settings → API**.
     You'll need the **Project URL** and the **anon public key** shown
     there for the next step.
2. **Fill in `js/supabase-config.js`** with the Project URL and
   anon/publishable key from step 1 (`js/supabase-config.example.js`
   shows the shape). Unlike most "config" files, this one IS committed to
   git and needs to be — GitHub Pages only serves committed files, and
   this key is designed to be public in client-side code anyway (real
   protection comes from the RLS policies in `sql/`, not from hiding it).
3. **Create a GitHub repo and push this project**, then in the repo's
   Settings → Pages, set the source to the `main` branch, root folder.
4. **Point the domain.** In Squarespace Domains' DNS settings for
   `ctrls.zip`, add the records GitHub's Pages docs specify for a custom
   apex domain, and add a `CNAME` file at the repo root with `ctrls.zip`
   in it once you're ready to go live.

(A more detailed, click-by-click version of all four steps is in the
chat — ask if you want it written down here too.)

## Local preview

No build step — just serve the folder statically and open it, e.g.:

```bash
npx serve .
```

## Database schema & security

`sql/` holds numbered, one-time migration files — run each one, in order,
in the Supabase dashboard's SQL Editor (Project > SQL Editor > New query,
paste, Run) the first time it's added. Don't re-run a file that already
succeeded; it'll error on already-existing tables/policies rather than
silently no-op. Don't create tables directly in the dashboard outside of
these files without RLS turned on, either — the anon/publishable key is
public, and RLS is what keeps data actually private.

## Required Supabase Auth setting

Handles have no email, so accounts sign up with a synthesized internal
address (`handle@ctrls.zip.internal`) instead of a real one — see
SPEC.md. For that to work, turn **off** "Confirm email" in the dashboard:
**Authentication → Providers → Email → Confirm email → off**. Otherwise
Supabase will wait for a confirmation click on an email address that can
never receive one, and nobody will ever be able to log in.
