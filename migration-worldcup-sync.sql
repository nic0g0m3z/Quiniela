-- =====================================================================
-- MIGRATION: Add World Cup auto-sync to existing Quiniela database
-- =====================================================================
-- Run this in the Supabase SQL Editor on your EXISTING database to
-- add auto-sync support without losing your current data.
--
-- If you're setting up from scratch, just use the full supabase-setup.sql
-- file instead — it already includes everything below.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Enable required extensions
-- ---------------------------------------------------------------------
create extension if not exists pg_cron;
create extension if not exists pg_net;  -- for HTTP requests from the database

-- ---------------------------------------------------------------------
-- 2. Restructure matches to be tournament-global, not per-quiniela
-- ---------------------------------------------------------------------
-- Strategy: rename old table, create new shared one, migrate nothing
-- (since you're starting fresh for the World Cup).

-- Save existing predictions/matches in case you want to recover (renames, no data loss)
alter table if exists public.matches rename to matches_legacy;
alter table if exists public.predictions rename to predictions_legacy;

-- The new global matches table (one row per real-world match)
create table public.matches (
  id uuid primary key default gen_random_uuid(),
  tournament text not null default 'worldcup_2026',  -- room to expand later
  external_id text unique,   -- stable ID from the data source (e.g. "wc2026-match-01")
  round text,                 -- "Matchday 1", "Round of 16", "Final", etc.
  group_name text,            -- "Group A", or null for knockouts
  home_team text,             -- can be null for knockout placeholders
  away_team text,
  kickoff timestamptz,
  status text default 'scheduled' not null,  -- scheduled | finished
  home_score int,
  away_score int,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);

create index if not exists idx_matches_tournament on public.matches(tournament);
create index if not exists idx_matches_kickoff on public.matches(kickoff);

-- Predictions now reference the global matches and are scoped to (quiniela, user, match)
create table public.predictions (
  quiniela_id uuid references public.quinielas(id) on delete cascade,
  match_id uuid references public.matches(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  home_score int not null,
  away_score int not null,
  submitted_at timestamptz default now() not null,
  primary key (quiniela_id, match_id, user_id)
);

create index if not exists idx_predictions_quiniela on public.predictions(quiniela_id);
create index if not exists idx_predictions_match on public.predictions(match_id);

-- ---------------------------------------------------------------------
-- 3. Add tournament column to quinielas
-- ---------------------------------------------------------------------
alter table public.quinielas
  add column if not exists tournament text default 'worldcup_2026' not null;

-- ---------------------------------------------------------------------
-- 4. RLS policies for the new tables
-- ---------------------------------------------------------------------
alter table public.matches enable row level security;
alter table public.predictions enable row level security;

-- All authenticated users can read matches (they're public tournament data)
drop policy if exists "matches_read_all" on public.matches;
create policy "matches_read_all" on public.matches
  for select to authenticated using (true);

-- No INSERT/UPDATE/DELETE policies on matches for users —
-- only the sync function (which runs as definer) modifies matches.

-- Predictions: users see their own anytime, others only after kickoff/lock
drop policy if exists "predictions_read" on public.predictions;
create policy "predictions_read" on public.predictions
  for select using (
    user_id = auth.uid()
    or exists (
      select 1 from public.matches m
      join public.memberships mm on mm.quiniela_id = predictions.quiniela_id
      where m.id = predictions.match_id
        and mm.user_id = auth.uid()
        and (m.status = 'finished' or m.kickoff <= now())
    )
  );

drop policy if exists "predictions_insert_own_unlocked" on public.predictions;
create policy "predictions_insert_own_unlocked" on public.predictions
  for insert with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.memberships
      where quiniela_id = predictions.quiniela_id and user_id = auth.uid()
    )
    and exists (
      select 1 from public.matches m
      where m.id = predictions.match_id
        and m.status != 'finished'
        and m.kickoff > now()
    )
  );

drop policy if exists "predictions_update_own_unlocked" on public.predictions;
create policy "predictions_update_own_unlocked" on public.predictions
  for update using (
    user_id = auth.uid()
    and exists (
      select 1 from public.matches m
      where m.id = predictions.match_id
        and m.status != 'finished'
        and m.kickoff > now()
    )
  );

drop policy if exists "predictions_delete_own" on public.predictions;
create policy "predictions_delete_own" on public.predictions
  for delete using (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- 5. The auto-sync function — fetches openfootball JSON and upserts matches
-- ---------------------------------------------------------------------

create or replace function public.sync_worldcup_2026()
returns text
language plpgsql
security definer
as $$
declare
  response_id bigint;
  response_body text;
  json_data jsonb;
  m jsonb;
  new_count int := 0;
  updated_count int := 0;
  existing_count int;
  ko_time text;
  ko_date text;
  parsed_ts timestamptz;
  home_team_val text;
  away_team_val text;
  home_score_val int;
  away_score_val int;
  match_status text;
  ext_id text;
begin
  -- Trigger the HTTP request (pg_net is async)
  select net.http_get(
    url := 'https://raw.githubusercontent.com/openfootball/worldcup.json/master/2026/worldcup.json',
    headers := '{"Accept": "application/json"}'::jsonb
  ) into response_id;

  -- Wait briefly for the response (pg_net stores results in net._http_response)
  perform pg_sleep(3);

  select content into response_body
  from net._http_response
  where id = response_id;

  if response_body is null then
    return 'Sync skipped — no response yet (will retry next cron tick)';
  end if;

  json_data := response_body::jsonb;

  -- Loop through each match in the JSON
  for m in select * from jsonb_array_elements(json_data->'matches')
  loop
    -- Build stable external_id from round + teams (or placeholders)
    home_team_val := nullif(m->>'team1', '');
    away_team_val := nullif(m->>'team2', '');

    -- For knockout matches with TBD teams, the JSON sometimes has placeholders
    -- like {"name":"Winner Group A"} as objects — flatten them.
    if home_team_val is null and (m->'team1') is not null then
      home_team_val := coalesce(m->'team1'->>'name', m->'team1'->>'code', null);
    end if;
    if away_team_val is null and (m->'team2') is not null then
      away_team_val := coalesce(m->'team2'->>'name', m->'team2'->>'code', null);
    end if;

    -- External ID: use date + round + teams for uniqueness
    ext_id := 'wc2026-' || coalesce(m->>'date', 'tbd') || '-'
              || coalesce(m->>'round', 'unknown') || '-'
              || coalesce(home_team_val, 'TBD') || '-vs-'
              || coalesce(away_team_val, 'TBD');

    -- Parse kickoff timestamp
    ko_date := m->>'date';
    ko_time := coalesce(m->>'time', '12:00');
    -- Strip timezone offsets from time field (e.g. "13:00 UTC-6" → "13:00")
    ko_time := split_part(ko_time, ' ', 1);
    begin
      parsed_ts := (ko_date || ' ' || ko_time)::timestamptz;
    exception when others then
      parsed_ts := null;
    end;

    -- Parse score if present
    home_score_val := null;
    away_score_val := null;
    match_status := 'scheduled';
    if m->'score' is not null and m->'score'->'ft' is not null then
      if jsonb_typeof(m->'score'->'ft') = 'array'
         and jsonb_array_length(m->'score'->'ft') >= 2 then
        home_score_val := (m->'score'->'ft'->0)::int;
        away_score_val := (m->'score'->'ft'->1)::int;
        match_status := 'finished';
      end if;
    end if;

    -- Upsert by external_id
    select count(*) into existing_count from public.matches where external_id = ext_id;

    insert into public.matches (
      tournament, external_id, round, group_name,
      home_team, away_team, kickoff,
      home_score, away_score, status, updated_at
    ) values (
      'worldcup_2026', ext_id, m->>'round', m->>'group',
      home_team_val, away_team_val, parsed_ts,
      home_score_val, away_score_val, match_status, now()
    )
    on conflict (external_id) do update set
      round = excluded.round,
      group_name = excluded.group_name,
      home_team = excluded.home_team,
      away_team = excluded.away_team,
      kickoff = excluded.kickoff,
      home_score = excluded.home_score,
      away_score = excluded.away_score,
      status = excluded.status,
      updated_at = now();

    if existing_count = 0 then
      new_count := new_count + 1;
    else
      updated_count := updated_count + 1;
    end if;
  end loop;

  -- Cleanup old http response rows
  delete from net._http_response where id = response_id;

  return format('Sync complete: %s new, %s updated', new_count, updated_count);
end;
$$;

-- ---------------------------------------------------------------------
-- 6. Schedule the sync every 30 minutes
-- ---------------------------------------------------------------------

-- Remove any prior schedule to keep this idempotent
do $$
declare
  job_id int;
begin
  for job_id in select jobid from cron.job where jobname = 'worldcup_2026_sync'
  loop
    perform cron.unschedule(job_id);
  end loop;
end;
$$;

select cron.schedule(
  'worldcup_2026_sync',
  '*/30 * * * *',  -- every 30 minutes
  $$select public.sync_worldcup_2026();$$
);

-- ---------------------------------------------------------------------
-- 7. Run it once now to populate the table immediately
-- ---------------------------------------------------------------------
select public.sync_worldcup_2026();

-- Wait a few seconds and run again — first call fires the HTTP request,
-- second call usually has the response ready.
select pg_sleep(5);
select public.sync_worldcup_2026();

-- =====================================================================
-- DONE!
-- Verify by running:
--   select count(*) from public.matches;
--   select * from public.matches order by kickoff limit 10;
-- =====================================================================
