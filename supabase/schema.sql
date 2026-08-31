create extension if not exists pgcrypto;

create table public.habits (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  emoji text not null default '🌱',
  color integer not null,
  daily_goal integer not null check (daily_goal > 0),
  unit text not null default 'times',
  category text not null default '',
  reminder jsonb not null default '{"mode":"none"}'::jsonb,
  icon_base64 text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.habit_entries (
  id uuid primary key,
  habit_id uuid not null references public.habits(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  local_date date not null,
  count integer not null default 0 check (count >= 0),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (habit_id, local_date)
);

create index habits_user_updated_idx on public.habits (user_id, updated_at);
create index entries_user_updated_idx on public.habit_entries (user_id, updated_at);

alter table public.habits enable row level security;
alter table public.habit_entries enable row level security;

create policy "users manage their habits" on public.habits
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "users manage their entries" on public.habit_entries
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger habits_set_updated_at before update on public.habits
  for each row execute function public.set_updated_at();
create trigger entries_set_updated_at before update on public.habit_entries
  for each row execute function public.set_updated_at();
