# CTRLS.zip

A minimalist, invite-only social network for the CTRL+S friend group,
styled as a desktop file browser. See [SPEC.md](SPEC.md) for the full
product spec — that's the source of truth for how this is supposed to
work.

## Stack

- Static frontend (plain HTML/CSS/JS, no build step) → **GitHub Pages**
- **Firebase** (Spark/free tier) → Firestore, Storage, Realtime chat, Auth

No paid tiers, no Cloud Functions, no credit card on file anywhere.

## Status

Scaffolding only right now — page shells and TODOs, no real Firebase
wiring yet. Nothing here talks to a real Firebase project until you've
done the one-time setup below.

## One-time setup (things only you can do — need your own accounts)

1. **Create a Firebase project.**
   - Go to https://console.firebase.google.com, create a new project
     (Spark/free plan is fine, no card required).
   - Enable **Authentication** → Email/Password provider (we use this
     with synthesized fake addresses instead of real emails — see
     SPEC.md's "Auth without email" section).
   - Enable **Firestore Database** and **Storage**.
   - In Project Settings → General → Your apps, add a Web app and copy
     the config object it gives you.
2. **Fill in your local Firebase config.**
   ```bash
   cp js/firebase-config.example.js js/firebase-config.js
   ```
   Paste your project's values into `js/firebase-config.js`. This file is
   gitignored so it won't get committed.
3. **Install the Firebase CLI** (only needed to deploy security rules,
   not for hosting):
   ```bash
   npm install -g firebase-tools
   firebase login
   firebase use --add   # pick your project, alias it "default"
   ```
4. **Create a GitHub repo and push this project**, then in the repo's
   Settings → Pages, set the source to the `main` branch, root folder.
5. **Point the domain.** In Squarespace Domains' DNS settings for
   `ctrls.zip`, add the records GitHub's Pages docs specify for a custom
   apex domain, and add a `CNAME` file at the repo root with `ctrls.zip`
   in it once you're ready to go live.

## Local preview

No build step — just serve the folder statically and open it, e.g.:

```bash
npx serve .
```

## Deploying security rules

Once `firebase-config.js` and `firebase use` are set up:

```bash
firebase deploy --only firestore:rules,storage
```
