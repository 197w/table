-- Rarytka · migracja 0001
-- Rozszerzenia, profile gości, restauracje, godziny otwarcia i menu.

create extension if not exists postgis with schema extensions;
create extension if not exists btree_gist with schema extensions;

-- ---------------------------------------------------------------
-- Profile gości
-- ---------------------------------------------------------------

create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  first_name  text check (char_length(first_name) <= 60),
  created_at  timestamptz not null default now()
);

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------
-- Restauracje
-- ---------------------------------------------------------------

create type public.restaurant_plan as enum ('free', 'pro');

create table public.restaurants (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,
  cuisine            text not null,
  price_level        smallint not null default 2 check (price_level between 1 and 4),
  description        text,
  address            text not null,
  city               text not null,
  phone              text not null,
  nip                text not null,
  location           extensions.geography(point, 4326) not null,
  plan               public.restaurant_plan not null default 'free',
  timezone           text not null default 'Europe/Warsaw',
  slot_interval_min  smallint not null default 15 check (slot_interval_min in (15, 30)),
  is_example         boolean not null default false,
  created_at         timestamptz not null default now()
);

create index restaurants_location_idx on public.restaurants using gist (location);
create index restaurants_cuisine_idx on public.restaurants (cuisine);

-- Dzień tygodnia według ISO: 1 = poniedziałek, 7 = niedziela.
-- Wersja 0.1 nie obsługuje zamknięcia po północy.
create table public.opening_hours (
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  weekday        smallint not null check (weekday between 1 and 7),
  opens          time not null,
  closes         time not null,
  primary key (restaurant_id, weekday),
  check (closes > opens)
);

-- ---------------------------------------------------------------
-- Menu
-- ---------------------------------------------------------------

create table public.menu_sections (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  name           text not null,
  position       smallint not null default 0
);

create index menu_sections_restaurant_idx on public.menu_sections (restaurant_id, position);

create table public.menu_items (
  id            uuid primary key default gen_random_uuid(),
  section_id    uuid not null references public.menu_sections (id) on delete cascade,
  name          text not null,
  description   text,
  price_grosze  integer not null check (price_grosze >= 0),
  allergens     text[] not null default '{}',
  position      smallint not null default 0
);

create index menu_items_section_idx on public.menu_items (section_id, position);
