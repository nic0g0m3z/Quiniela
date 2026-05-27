-- =====================================================================
-- QUINIELA DATABASE SETUP — FRESH INSTALL (WITH WORLD CUP AUTO-SYNC)
-- Run this once, all at once, in the Supabase SQL Editor.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. EXTENSIONS
-- ---------------------------------------------------------------------
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ---------------------------------------------------------------------
-- 1. CORE TABLES
-- ---------------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  username text unique not null,
  is_platform_admin boolean default false not null,
  created_at timestamptz default now() not null
);

create table if not exists public.quinielas (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text default '',
  owner_id uuid references public.profiles(id) on delete set null,
  invite_code text unique not null,
  tournament text default 'worldcup_2026' not null,
  created_at timestamptz default now() not null
);

create table if not exists public.memberships (
  quiniela_id uuid references public.quinielas(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  joined_at timestamptz default now() not null,
  primary key (quiniela_id, user_id)
);

-- Matches are GLOBAL per tournament (not per quiniela)
create table if not exists public.matches (
  id uuid primary key default gen_random_uuid(),
  tournament text not null default 'worldcup_2026',
  external_id text unique,
  round text,
  group_name text,
  home_team text,
  away_team text,
  kickoff timestamptz,
  status text default 'scheduled' not null,
  home_score int,
  away_score int,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);

-- Predictions are per (quiniela, user, match)
create table if not exists public.predictions (
  quiniela_id uuid references public.quinielas(id) on delete cascade,
  match_id uuid references public.matches(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  home_score int not null,
  away_score int not null,
  submitted_at timestamptz default now() not null,
  primary key (quiniela_id, match_id, user_id)
);

-- ---------------------------------------------------------------------
-- 2. AUTO-CREATE PROFILE ON SIGNUP (first user becomes admin)
-- ---------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger as $$
declare
  user_count int;
begin
  select count(*) into user_count from public.profiles;
  insert into public.profiles (id, username, is_platform_admin)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
    user_count = 0
  );
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------------------------------------------------------------------
-- 3. HELPER FUNCTIONS
-- ---------------------------------------------------------------------

create or replace function public.is_member(qid uuid, uid uuid)
returns boolean
language sql security definer stable
as $$
  select exists (select 1 from public.memberships where quiniela_id = qid and user_id = uid);
$$;

create or replace function public.is_platform_admin()
returns boolean
language sql security definer stable
as $$
  select coalesce((select is_platform_admin from public.profiles where id = auth.uid()), false);
$$;

create or replace function public.find_quiniela_by_code(code text)
returns table (
  id uuid, name text, description text, owner_id uuid,
  invite_code text, tournament text, created_at timestamptz
)
language sql security definer stable
as $$
  select id, name, description, owner_id, invite_code, tournament, created_at
  from public.quinielas where invite_code = upper(code) limit 1;
$$;

grant execute on function public.find_quiniela_by_code(text) to authenticated, anon;

-- ---------------------------------------------------------------------
-- 4. INDEXES
-- ---------------------------------------------------------------------

create index if not exists idx_memberships_user on public.memberships(user_id);
create index if not exists idx_quinielas_invite on public.quinielas(invite_code);
create index if not exists idx_matches_tournament on public.matches(tournament);
create index if not exists idx_matches_kickoff on public.matches(kickoff);
create index if not exists idx_predictions_quiniela on public.predictions(quiniela_id);
create index if not exists idx_predictions_match on public.predictions(match_id);

-- ---------------------------------------------------------------------
-- 5. ROW-LEVEL SECURITY
-- ---------------------------------------------------------------------

alter table public.profiles      enable row level security;
alter table public.quinielas     enable row level security;
alter table public.memberships   enable row level security;
alter table public.matches       enable row level security;
alter table public.predictions   enable row level security;

-- PROFILES
drop policy if exists "profiles_read" on public.profiles;
create policy "profiles_read" on public.profiles
  for select using (auth.role() = 'authenticated');

drop policy if exists "profiles_update_self_no_admin" on public.profiles;
create policy "profiles_update_self_no_admin" on public.profiles
  for update using (auth.uid() = id)
  with check (
    auth.uid() = id
    and is_platform_admin = (select is_platform_admin from public.profiles where id = auth.uid())
  );

drop policy if exists "profiles_update_by_admin" on public.profiles;
create policy "profiles_update_by_admin" on public.profiles
  for update using (public.is_platform_admin());

-- QUINIELAS
drop policy if exists "quinielas_read_members" on public.quinielas;
create policy "quinielas_read_members" on public.quinielas
  for select using (
    owner_id = auth.uid()
    or public.is_member(id, auth.uid())
    or public.is_platform_admin()
  );

drop policy if exists "quinielas_insert_admin_only" on public.quinielas;
create policy "quinielas_insert_admin_only" on public.quinielas
  for insert with check (
    exists (select 1 from public.profiles where id = auth.uid() and is_platform_admin = true)
  );

drop policy if exists "quinielas_update_owner_or_admin" on public.quinielas;
create policy "quinielas_update_owner_or_admin" on public.quinielas
  for update using (owner_id = auth.uid() or public.is_platform_admin());

drop policy if exists "quinielas_delete_owner_or_admin" on public.quinielas;
create policy "quinielas_delete_owner_or_admin" on public.quinielas
  for delete using (owner_id = auth.uid() or public.is_platform_admin());

-- MEMBERSHIPS
drop policy if exists "memberships_read" on public.memberships;
create policy "memberships_read" on public.memberships
  for select using (
    user_id = auth.uid()
    or public.is_member(quiniela_id, auth.uid())
    or exists (select 1 from public.quinielas q where q.id = memberships.quiniela_id and q.owner_id = auth.uid())
  );

drop policy if exists "memberships_join_self" on public.memberships;
create policy "memberships_join_self" on public.memberships
  for insert with check (user_id = auth.uid());

drop policy if exists "memberships_delete" on public.memberships;
create policy "memberships_delete" on public.memberships
  for delete using (
    user_id = auth.uid()
    or exists (select 1 from public.quinielas q where q.id = memberships.quiniela_id and q.owner_id = auth.uid())
    or public.is_platform_admin()
  );

-- MATCHES (read-only for users; only the sync function can write)
drop policy if exists "matches_read_all" on public.matches;
create policy "matches_read_all" on public.matches
  for select to authenticated using (true);

-- PREDICTIONS
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
    and exists (select 1 from public.memberships where quiniela_id = predictions.quiniela_id and user_id = auth.uid())
    and exists (select 1 from public.matches m where m.id = predictions.match_id and m.status != 'finished' and m.kickoff > now())
  );

drop policy if exists "predictions_update_own_unlocked" on public.predictions;
create policy "predictions_update_own_unlocked" on public.predictions
  for update using (
    user_id = auth.uid()
    and exists (select 1 from public.matches m where m.id = predictions.match_id and m.status != 'finished' and m.kickoff > now())
  );

drop policy if exists "predictions_delete_own" on public.predictions;
create policy "predictions_delete_own" on public.predictions
  for delete using (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- 6. WORLD CUP AUTO-SYNC FUNCTION
-- ---------------------------------------------------------------------

create or replace function public.sync_worldcup_2026()
returns text
language plpgsql security definer
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
  select net.http_get(
    url := 'https://raw.githubusercontent.com/openfootball/worldcup.json/master/2026/worldcup.json',
    headers := '{"Accept": "application/json"}'::jsonb
  ) into response_id;

  perform pg_sleep(3);

  select content into response_body from net._http_response where id = response_id;
  if response_body is null then
    return 'Sync skipped — no response yet (will retry next cron tick)';
  end if;

  json_data := response_body::jsonb;

  for m in select * from jsonb_array_elements(json_data->'matches')
  loop
    home_team_val := nullif(m->>'team1', '');
    away_team_val := nullif(m->>'team2', '');
    if home_team_val is null and (m->'team1') is not null then
      home_team_val := coalesce(m->'team1'->>'name', m->'team1'->>'code', null);
    end if;
    if away_team_val is null and (m->'team2') is not null then
      away_team_val := coalesce(m->'team2'->>'name', m->'team2'->>'code', null);
    end if;

    ext_id := 'wc2026-' || coalesce(m->>'date', 'tbd') || '-'
              || coalesce(m->>'round', 'unknown') || '-'
              || coalesce(home_team_val, 'TBD') || '-vs-'
              || coalesce(away_team_val, 'TBD');

    ko_date := m->>'date';
    ko_time := coalesce(m->>'time', '12:00');
    ko_time := split_part(ko_time, ' ', 1);
    begin parsed_ts := (ko_date || ' ' || ko_time)::timestamptz;
    exception when others then parsed_ts := null;
    end;

    home_score_val := null; away_score_val := null; match_status := 'scheduled';
    if m->'score' is not null and m->'score'->'ft' is not null
       and jsonb_typeof(m->'score'->'ft') = 'array'
       and jsonb_array_length(m->'score'->'ft') >= 2 then
      home_score_val := (m->'score'->'ft'->0)::int;
      away_score_val := (m->'score'->'ft'->1)::int;
      match_status := 'finished';
    end if;

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
      round = excluded.round, group_name = excluded.group_name,
      home_team = excluded.home_team, away_team = excluded.away_team,
      kickoff = excluded.kickoff,
      home_score = excluded.home_score, away_score = excluded.away_score,
      status = excluded.status, updated_at = now();

    if existing_count = 0 then new_count := new_count + 1;
    else updated_count := updated_count + 1; end if;
  end loop;

  delete from net._http_response where id = response_id;
  return format('Sync complete: %s new, %s updated', new_count, updated_count);
end;
$$;

-- ---------------------------------------------------------------------
-- 7. SCHEDULE SYNC EVERY 30 MINUTES
-- ---------------------------------------------------------------------

do $$
declare job_id int;
begin
  for job_id in select jobid from cron.job where jobname = 'worldcup_2026_sync'
  loop perform cron.unschedule(job_id); end loop;
end;
$$;

select cron.schedule('worldcup_2026_sync', '*/30 * * * *', $$select public.sync_worldcup_2026();$$);

-- Run once now to populate (first call may not have data yet, do twice)
select public.sync_worldcup_2026();
select pg_sleep(5);
select public.sync_worldcup_2026();

-- =====================================================================
-- DONE!
-- Next steps:
--   1. Authentication → Sign In / Providers → Email → toggle OFF "Confirm email"
--   2. Project Settings → API → copy URL + anon key into index.html
--   3. (Optional) Set up email notifications — see DEPLOY-EMAIL.md
-- =====================================================================
