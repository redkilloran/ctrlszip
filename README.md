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
2. **Fill in your local Supabase config.**
   ```bash
   cp js/supabase-config.example.js js/supabase-config.js
   ```
   Open `js/supabase-config.js` and paste in the Project URL and anon key
   from step 1. This file is gitignored so it won't get committed.
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

`sql/schema.sql` will hold the real table definitions and Row Level
Security (RLS) policies once the data model is designed — run it in the
Supabase dashboard's SQL Editor when that's ready. Until then, don't
create any tables directly in the dashboard without RLS turned on, since
the anon key is public and RLS is what keeps data actually private.
