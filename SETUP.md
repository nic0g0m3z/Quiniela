# Quiniela — Full Setup Guide

Zero to working public app in ~30 minutes.

The app now uses **automatic World Cup 2026 data sync**:
- All 104 matches are pulled from a public data feed
- Scores update automatically as the tournament progresses
- Knockout matchups appear automatically once determined
- Admins don't need to enter anything — just create a quiniela and share the invite code

---

## Part 1: Set up Supabase (the database) — 10 minutes

### 1.1 Create a Supabase account & project

1. Go to **https://supabase.com** → Sign up → New Project
2. Fill in:
   - **Name**: `quiniela`
   - **Database password**: click Generate, save it
   - **Region**: closest to your players
   - **Plan**: Free
3. Wait ~2 minutes for it to set up

### 1.2 Run the database setup

1. Left sidebar → **SQL Editor** → **+ New query**
2. Open `supabase-setup.sql` from this folder, copy the entire contents, paste into the editor
3. Click **Run**
4. **The script may take 10-15 seconds** because it fetches the World Cup data on first run. That's normal.
5. You should see "Success" at the bottom

Verify by running:
```sql
select count(*) from public.matches;
```
You should get around 100+ matches.

### 1.3 Disable email confirmation

1. Left sidebar → **Authentication** → **Sign In / Providers** → click **Email**
2. Toggle **"Confirm email"** OFF
3. Click **Save**

### 1.4 Get your API credentials

1. Left sidebar → **gear icon** → **API**
2. Copy these two values:
   - **Project URL** (`https://xxxxx.supabase.co` — no trailing slash, no path)
   - **`anon` `public`** key (long string starting with `eyJ...`)

---

## Part 2: Configure the app — 1 minute

1. Open `index.html` in any plain text editor
2. Near the top of the `<script>` section, find:
   ```js
   const SUPABASE_URL = "YOUR_SUPABASE_URL_HERE";
   const SUPABASE_ANON_KEY = "YOUR_SUPABASE_ANON_KEY_HERE";
   ```
3. Replace with your actual values
4. Save

---

## Part 3a: Run locally — 30 seconds

**Double-click `index.html`** → opens in browser → register the first account (you become platform admin automatically).

Only your computer can access this — for shared use, do Part 3b.

---

## Part 3b: Deploy publicly with GitHub + Vercel — 15 minutes

### 3b.1 Create a GitHub repo

1. github.com → sign up → New repository
2. Name: `quiniela`, set to **Private**, Create

### 3b.2 Upload `index.html`

1. Click "uploading an existing file"
2. Drag `index.html` in → Commit changes

### 3b.3 Connect Vercel

1. vercel.com → sign up with GitHub
2. **Add New → Project** → Import your `quiniela` repo
3. Leave defaults → **Deploy**
4. ~30 seconds later you have a URL like `https://quiniela-xxx.vercel.app`

### 3b.4 Disable deployment protection

1. Vercel project → **Settings** → **Deployment Protection**
2. Set to **Disabled** / **None** / **Off** → Save

### 3b.5 Updating later

Edit `index.html` on GitHub → commit → Vercel auto-deploys in ~30 seconds.

> 💡 **After every deploy, hard-refresh your browser** with **Ctrl + Shift + R** (Windows) or **Cmd + Shift + R** (Mac).

---

## Part 4: (Optional) Email notifications — 15 minutes

If you want emails when new matches appear (especially useful for knockouts being determined), follow **`DEPLOY-EMAIL.md`** in this folder.

You can also do this later — the app works fine without it.

---

## Bootstrapping admin access

The **first registered user** automatically becomes platform admin. So:

1. Open your live URL
2. **You register first** — you're now the admin
3. Share the URL with friends → they register as regular users
4. As admin, click "New quiniela" to create a pool
5. **You don't auto-join** — you manage from outside. If you want to play too, click "Join as player" once the quiniela is open
6. Share the invite code with friends so they can join
7. From the Admin tab → Members → "Make admin" lets you promote others

### If admin status didn't apply

Supabase → Table Editor → `profiles` → find your row → flip `is_platform_admin` to `true` → log out and back in.

---

## How the auto-sync works (so you understand what's running)

A scheduled function in your Supabase database wakes up **every 30 minutes**. It:

1. Downloads the latest `worldcup.json` from a public GitHub repository (openfootball/worldcup.json)
2. For each match in the file, it inserts or updates a row in your `matches` table
3. When a match has finished (the JSON includes a score), it marks it `finished` — the leaderboard recalculates automatically
4. When knockout teams get filled in (the JSON updates), the corresponding match rows are updated

The function is named `sync_worldcup_2026` and is scheduled by Postgres's built-in cron extension. You don't need to do anything for it to run.

### Sync runs even with no users

Even if no one opens the app for days, the sync keeps running on Supabase's servers. As long as the project isn't paused for inactivity, data stays current.

### Force a sync manually

In SQL Editor:
```sql
select public.sync_worldcup_2026();
```

### Check sync history

```sql
select * from cron.job_run_details
where jobname = 'worldcup_2026_sync'
order by start_time desc
limit 5;
```

---

## Costs

Both Supabase and Vercel have generous free tiers. You won't be charged.

- **Supabase free**: 500 MB DB + 50k MAU + 5 GB bandwidth + 500k Edge Function invocations
- **Vercel free**: 100 GB bandwidth/month
- **Resend free** (if you set up email): 3,000 emails/month

For a friend group across the entire World Cup, you'll use a tiny fraction.

> **Inactivity pause**: Supabase free projects get paused if there's no activity for 7 days. With the cron sync running every 30 min, your project will never go idle, so this isn't a concern.
