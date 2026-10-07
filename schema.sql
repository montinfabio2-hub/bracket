-- Bracket · schema del database (Supabase / Postgres)
-- Incolla tutto nello "SQL Editor" di Supabase ed esegui una volta.

create table if not exists profiles (
  user_id uuid primary key references auth.users on delete cascade,
  display_name text not null check (char_length(display_name) between 2 and 24)
);
create table if not exists admins (
  user_id uuid primary key references auth.users on delete cascade
);
-- finestra di apertura/chiusura di ogni fase di ogni evento
create table if not exists phase_windows (
  event_id text not null,
  phase_idx int not null,
  opens_at timestamptz not null,
  closes_at timestamptz not null check (closes_at > opens_at),
  primary key (event_id, phase_idx)
);
-- pronostici: massimo 3 per utente, evento e fase (slot 1-3)
create table if not exists entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  event_id text not null,
  phase_idx int not null,
  slot int not null check (slot between 1 and 3),
  picks jsonb not null,
  updated_at timestamptz not null default now(),
  unique (user_id, event_id, phase_idx, slot)
);
-- risultati reali caricati dall'admin
create table if not exists results (
  event_id text not null,
  phase_idx int not null,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (event_id, phase_idx)
);

create or replace function is_admin() returns boolean
language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.admins where user_id = auth.uid())
$$;

alter table profiles enable row level security;
alter table admins enable row level security;
alter table phase_windows enable row level security;
alter table entries enable row level security;
alter table results enable row level security;

create policy profiles_read on profiles for select using (true);
create policy profiles_insert on profiles for insert with check (user_id = auth.uid());
create policy profiles_update on profiles for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy admins_read_self on admins for select using (user_id = auth.uid());

create policy windows_read on phase_windows for select using (true);
create policy windows_admin on phase_windows for all using (is_admin()) with check (is_admin());

-- i pronostici sono visibili solo al proprietario finché la fase è aperta;
-- dopo la chiusura sono visibili a tutti (serve per la classifica)
create policy entries_read on entries for select using (
  user_id = auth.uid()
  or exists (select 1 from phase_windows w where w.event_id = entries.event_id
             and w.phase_idx = entries.phase_idx and now() > w.closes_at)
);
-- si può scrivere solo mentre la finestra è aperta (controllo fatto dal server)
create policy entries_insert on entries for insert with check (
  user_id = auth.uid()
  and exists (select 1 from phase_windows w where w.event_id = entries.event_id
              and w.phase_idx = entries.phase_idx and now() between w.opens_at and w.closes_at)
);
create policy entries_update on entries for update using (user_id = auth.uid()) with check (
  user_id = auth.uid()
  and exists (select 1 from phase_windows w where w.event_id = entries.event_id
              and w.phase_idx = entries.phase_idx and now() between w.opens_at and w.closes_at)
);
create policy entries_delete on entries for delete using (
  user_id = auth.uid()
  and exists (select 1 from phase_windows w where w.event_id = entries.event_id
              and w.phase_idx = entries.phase_idx and now() between w.opens_at and w.closes_at)
);

create policy results_read on results for select using (true);
create policy results_admin on results for all using (is_admin()) with check (is_admin());
