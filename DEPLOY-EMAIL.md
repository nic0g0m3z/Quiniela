# Email Notifications Setup

This adds an email notification to all members whenever a new World Cup match is added (e.g., when quarterfinal matchups get determined).

**This is optional.** The app works fine without it; matches still appear automatically. Email is just a convenience.

## What you'll need

- A **Resend** account (free for 3,000 emails/month — way more than you need)
- The **Supabase CLI** installed on your computer (one-time install)
- ~15 minutes

---

## Step 1: Sign up for Resend

1. Go to **https://resend.com** → sign up
2. After signing in, go to **API Keys** in the left sidebar
3. Click **Create API Key** → name it `quiniela` → keep "Sending access" selected → create
4. **Copy the key** that appears (starts with `re_...`) — you'll need it in a minute. You only see it once.

### About the sender address

By default Resend lets you send from `onboarding@resend.dev` to verified email addresses only (you can test). To send to anyone, you need to either:
- **Verify a domain you own** (instructions in Resend → Domains) — more setup but lets you send from a proper address
- **For a small private app**, using `onboarding@resend.dev` is fine if all your friends verify their addresses with Resend (annoying), OR you can verify a domain

For simplicity: skip domain verification for now. The function will be ready to use it later when you do.

---

## Step 2: Install the Supabase CLI

This is needed to deploy the email function. Install once:

### macOS
```
brew install supabase/tap/supabase
```

### Windows (PowerShell)
```
scoop install supabase
```
or download from https://github.com/supabase/cli/releases

### Linux
```
curl -fsSL https://supabase.com/install.sh | sh
```

### Verify
```
supabase --version
```

---

## Step 3: Link your Supabase project

In your terminal, navigate to the `quiniela` folder (where these files are):

```
cd path/to/quiniela
supabase login
supabase link --project-ref YOUR_PROJECT_REF
```

`YOUR_PROJECT_REF` is the random string in your Supabase URL — `https://xxxxxxxxxxxx.supabase.co` → the `xxxxxxxxxxxx` part.

---

## Step 4: Set the secrets

The function needs three secrets. Run each line (replacing the values):

```
supabase secrets set RESEND_API_KEY=re_yourkeyhere
supabase secrets set FROM_EMAIL=onboarding@resend.dev
supabase secrets set APP_URL=https://your-quiniela.vercel.app
```

(Replace `https://your-quiniela.vercel.app` with your actual live site URL.)

---

## Step 5: Deploy the function

```
supabase functions deploy notify-new-matches --no-verify-jwt
```

The `--no-verify-jwt` flag is needed because the database calls it directly (not via a user login).

After deployment, copy the function's URL — it'll be shown in the terminal output, like:
```
https://xxxxxxxxxxxx.supabase.co/functions/v1/notify-new-matches
```

---

## Step 6: Connect the function to new-match events

In the Supabase SQL Editor, run this — **replace the URL** with your actual function URL from step 5:

```sql
-- Trigger that calls the edge function whenever a new match with real teams is inserted
create or replace function public.notify_new_match()
returns trigger language plpgsql security definer as $$
begin
  -- Skip TBD/placeholder rows
  if NEW.home_team is null or NEW.away_team is null
     or NEW.home_team ilike '%winner%' or NEW.away_team ilike '%winner%'
     or NEW.home_team ilike '%loser%' or NEW.away_team ilike '%loser%'
     or NEW.home_team ilike '%tbd%' or NEW.away_team ilike '%tbd%' then
    return NEW;
  end if;

  -- Async HTTP call to the edge function
  perform net.http_post(
    url := 'https://YOUR-PROJECT-REF.supabase.co/functions/v1/notify-new-matches',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
    ),
    body := jsonb_build_object('record', row_to_json(NEW))
  );
  return NEW;
end;
$$;

drop trigger if exists trg_notify_new_match on public.matches;
create trigger trg_notify_new_match
  after insert on public.matches
  for each row execute function public.notify_new_match();
```

> ⚠️ Replace `YOUR-PROJECT-REF` in the URL above with your actual project ref.

---

## Step 7: Test it

In SQL Editor, manually insert a test match:

```sql
insert into public.matches (tournament, external_id, round, home_team, away_team, kickoff)
values ('worldcup_2026', 'test-match-' || gen_random_uuid(), 'Test', 'Test Team A', 'Test Team B', now() + interval '1 day');
```

Check your email (and the inbox of anyone in a quiniela). The email should arrive within a few seconds.

To clean up:
```sql
delete from public.matches where external_id like 'test-match-%';
```

---

## What about emails for updates (not just new matches)?

The current setup only emails on **insert** (new matches). It doesn't email when a match's teams get updated (e.g., the JSON file changes "Winner Group A" to "Argentina"). For knockout rounds, this means:

- When the bracket gets filled in, the system **updates** existing match rows rather than inserting new ones
- So no email fires for these updates with the current setup

If you want emails for that, you can add an UPDATE trigger too. Let me know if you want me to write it — it's about 10 more lines of SQL.

---

## Costs

- **Resend free**: 3,000 emails/month, 100/day. For a friend group of <20 people across the entire World Cup (104 matches), you'd use a maximum of ~2,000 emails — well within free.
- **Supabase Edge Functions**: 500,000 invocations/month free. You'll use <200.

You will not be charged anything.
