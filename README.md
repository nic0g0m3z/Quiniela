# Quiniela

A World Cup 2026 prediction pool app. Friends register accounts, join your quinielas via invite code, predict match scores, and compete on auto-updating leaderboards. All match data — fixtures, kickoffs, results, knockout brackets — syncs automatically from a public data source. No manual entry needed.

## What's in this folder

```
quiniela/
├── index.html                       ← the app (single file)
├── supabase-setup.sql               ← database setup (fresh installs)
├── migration-worldcup-sync.sql      ← migration script (existing setups)
├── notify-new-matches/index.ts      ← email notification Edge Function
├── SETUP.md                         ← step-by-step deployment guide
├── DEPLOY-EMAIL.md                  ← optional email setup guide
├── CUSTOMIZE.md                     ← how to change colors, text, scoring, etc.
└── README.md                        ← this file
```

## Quick start

### Fresh install (recommended)
Read **`SETUP.md`** and follow it. It walks you through:
- Creating a free Supabase database (~10 min)
- Running the SQL setup script (auto-installs auto-sync)
- Configuring the app (~1 min)
- Running locally OR deploying publicly to Vercel (~15 min)

### Migrating an existing setup
If you already had the old version of this app running and want to upgrade to auto-sync:
- Run `migration-worldcup-sync.sql` in the Supabase SQL Editor
- Replace your live `index.html` with the new one
- Your accounts and quinielas stay intact, but per-quiniela matches are replaced with global synced ones

### Optional: email notifications
After the main app is up, see **`DEPLOY-EMAIL.md`** to enable emails when new matches appear.

## Features

- 🔐 Email + password authentication (Supabase Auth)
- ⚽ **Fully automatic** World Cup 2026 data — fixtures, scores, knockouts
- 👑 Quiniela owners manage from outside (don't auto-join)
- 👥 Multiple quinielas, separate leaderboards per pool
- 🔗 6-character invite codes for joining
- 🏆 Auto-recalculating leaderboard (exact / outcome / wrong)
- 🛡️ Database-level Row-Level Security
- 📧 Optional email notifications on new matches
- 📱 Mobile-friendly design

## Tech stack

- **Frontend**: React 18 + Babel from CDN — no build step
- **Backend**: Supabase (Postgres + Auth + Edge Functions + pg_cron)
- **Data source**: openfootball/worldcup.json (public domain, free)
- **Email**: Resend (optional)
- **Hosting**: Vercel (free tier)

Everything in `index.html` is a single file. No bundler, no npm, no Node.js needed for the app itself.

## License / use

Yours. Use it, change it, deploy it, host private pools with friends. Have fun 🏆
