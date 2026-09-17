-- Table · migracja 0002
-- Stoliki, rezerwacje z blokadą podwójnej rezerwacji, opinie i zdarzenia.

-- ---------------------------------------------------------------
-- Stoliki
-- ---------------------------------------------------------------

create table public.dining_tables (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  label          text not null,
  seats          smallint not null check (seats between 1 and 30),
  width_cm       smallint check (width_cm > 0),
  height_cm      smallint check (height_cm > 0),
  zone           text not null default 'sala',
  join_group     text,
  priority       smallint not null default 0,
  active         boolean not null default true
);

create index dining_tables_restaurant_idx on public.dining_tables (restaurant_id) where active;

-- ---------------------------------------------------------------
-- Rezerwacje
-- ---------------------------------------------------------------

create type public.reservation_status as enum
  ('confirmed', 'seated', 'completed', 'cancelled', 'no_show');

create type public.reservation_source as enum
  ('app', 'phone', 'walk_in', 'block');

create type public.reservation_occasion as enum
  ('birthday', 'anniversary', 'date', 'business', 'proposal', 'other');

create table public.reservations (
  id                    uuid primary key default gen_random_uuid(),
  restaurant_id         uuid not null references public.restaurants (id) on delete cascade,
  user_id               uuid references auth.users (id) on delete set null,
  party_size            smallint not null check (party_size between 1 and 30),
  starts_at             timestamptz not null,
  ends_at               timestamptz not null,
  status                public.reservation_status not null default 'confirmed',
  source                public.reservation_source not null default 'app',
  occasion              public.reservation_occasion,
  message               text check (char_length(message) <= 300),
  message_delete_after  timestamptz,
  created_at            timestamptz not null default now(),
  check (ends_at > starts_at)
);

create index reservations_user_idx on public.reservations (user_id, starts_at desc);
create index reservations_restaurant_idx on public.reservations (restaurant_id, starts_at);

-- Alergie i dieta: osobna tabela, zapisywana tylko po zgodzie gościa.
create table public.reservation_diets (
  reservation_id  uuid primary key references public.reservations (id) on delete cascade,
  details         text not null check (char_length(details) <= 300),
  consent_at      timestamptz not null default now(),
  delete_after    timestamptz not null
);

-- Ten sam stolik nie może mieć dwóch nachodzących na siebie przedziałów.
-- Przedział obejmuje wizytę i sprzątanie.
create table public.table_holds (
  reservation_id  uuid not null references public.reservations (id) on delete cascade,
  table_id        uuid not null references public.dining_tables (id) on delete cascade,
  slot            tstzrange not null,
  active          boolean not null default true,
  primary key (reservation_id, table_id),
  exclude using gist (table_id with =, slot with &&) where (active)
);

-- ---------------------------------------------------------------
-- Opinie
-- ---------------------------------------------------------------

create type public.review_verification as enum ('reservation', 'receipt', 'none');

create table public.reviews (
  id              uuid primary key default gen_random_uuid(),
  restaurant_id   uuid not null references public.restaurants (id) on delete cascade,
  user_id         uuid references auth.users (id) on delete cascade,
  reservation_id  uuid unique references public.reservations (id) on delete set null,
  food            smallint not null check (food between 1 and 5),
  service         smallint not null check (service between 1 and 5),
  ambience        smallint not null check (ambience between 1 and 5),
  body            text check (char_length(body) <= 2000),
  verification    public.review_verification not null default 'none',
  seed_author     text,
  created_at      timestamptz not null default now()
);

comment on column public.reviews.seed_author is
  'Tylko dla danych przykładowych. Prawdziwe opinie mają user_id.';

create index reviews_restaurant_idx on public.reviews (restaurant_id, created_at desc);

-- Jedna niezweryfikowana opinia na gościa i lokal.
create unique index reviews_one_unverified_idx
  on public.reviews (user_id, restaurant_id)
  where verification = 'none';

-- ---------------------------------------------------------------
-- Zdarzenia do statystyk restauracji
-- ---------------------------------------------------------------

create table public.restaurant_events (
  id             bigint generated always as identity primary key,
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  kind           text not null check (kind in ('view', 'call_click')),
  user_id        uuid references auth.users (id) on delete set null,
  created_at     timestamptz not null default now()
);

create index restaurant_events_idx on public.restaurant_events (restaurant_id, kind, created_at);
