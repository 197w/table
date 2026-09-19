-- Table · migracja 0013
-- Logo lokalu, karty podarunkowe (tryb testowy bez płatności), grafik pracowników,
-- krzesła do rezerwacji, stałe elementy sali i własne ustawienie krzeseł przy stoliku.

-- ---------------------------------------------------------------
-- Logo lokalu
-- ---------------------------------------------------------------

alter table public.restaurants
  add column logo_url text check (char_length(logo_url) <= 500);

grant update (logo_url) on public.restaurants to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('restaurant-logos', 'restaurant-logos', true, 2097152,
        array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do nothing;

-- Plik logo leży w folderze o nazwie identyfikatora lokalu: <restaurant_id>/logo-....png
create or replace function private.can_manage_logo(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  begin
    v_id := split_part(p_name, '/', 1)::uuid;
  exception
    when others then return false;
  end;
  return private.has_staff_role(v_id, 'manager');
end;
$$;

revoke execute on function private.can_manage_logo(text) from public, anon;
grant execute on function private.can_manage_logo(text) to authenticated;

create policy "Kierownik dodaje logo lokalu"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'restaurant-logos' and private.can_manage_logo(name));

create policy "Kierownik zmienia logo lokalu"
  on storage.objects for update to authenticated
  using (bucket_id = 'restaurant-logos' and private.can_manage_logo(name))
  with check (bucket_id = 'restaurant-logos' and private.can_manage_logo(name));

create policy "Kierownik usuwa logo lokalu"
  on storage.objects for delete to authenticated
  using (bucket_id = 'restaurant-logos' and private.can_manage_logo(name));

-- Wyszukiwarka gości zwraca też logo.
drop function if exists public.search_restaurants(double precision, double precision, numeric, text, text, text);

create or replace function public.search_restaurants(
  p_lat        double precision,
  p_lng        double precision,
  p_radius_km  numeric default 10,
  p_cuisine    text default null,
  p_sort       text default 'ranking',
  p_city       text default null
)
returns table (
  id                  uuid,
  name                text,
  cuisine             text,
  price_level         smallint,
  address             text,
  city                text,
  plan                public.restaurant_plan,
  is_example          boolean,
  logo_url            text,
  distance_m          double precision,
  verified_reviews    integer,
  unverified_reviews  integer,
  food_avg            numeric,
  service_avg         numeric,
  ambience_avg        numeric,
  food_score          numeric
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with origin as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  ),
  nearby as (
    select r.*, st_distance(r.location, o.g) as dist
    from restaurants r, origin o
    where (
        case
          when p_city is not null then r.city = p_city
          else st_dwithin(r.location, o.g, least(greatest(p_radius_km, 1), 50) * 1000)
        end
      )
      and (p_cuisine is null or r.cuisine = p_cuisine)
  ),
  stats as (
    select
      rv.restaurant_id,
      count(*) filter (where rv.verification <> 'none')          as verified,
      count(*) filter (where rv.verification = 'none')           as unverified,
      avg(rv.food) filter (where rv.verification <> 'none')      as food_avg,
      avg(rv.service) filter (where rv.verification <> 'none')   as service_avg,
      avg(rv.ambience) filter (where rv.verification <> 'none')  as ambience_avg
    from reviews rv
    join nearby n on n.id = rv.restaurant_id
    group by rv.restaurant_id
  ),
  region as (
    select coalesce(sum(s.food_avg * s.verified) / nullif(sum(s.verified), 0), 4.0) as c
    from stats s
  ),
  scored as (
    select
      n.id, n.name, n.cuisine, n.price_level, n.address, n.city, n.plan, n.is_example, n.logo_url,
      n.dist,
      coalesce(s.verified, 0)::integer   as verified,
      coalesce(s.unverified, 0)::integer as unverified,
      round(s.food_avg, 2)     as food_avg,
      round(s.service_avg, 2)  as service_avg,
      round(s.ambience_avg, 2) as ambience_avg,
      case
        when coalesce(s.verified, 0) = 0 then null
        else round(
          (s.verified::numeric / (s.verified + 10)) * s.food_avg
          + (10::numeric / (s.verified + 10)) * region.c, 3)
      end as score
    from nearby n
    left join stats s on s.restaurant_id = n.id
    cross join region
  )
  select
    sc.id, sc.name, sc.cuisine, sc.price_level, sc.address, sc.city, sc.plan, sc.is_example, sc.logo_url,
    sc.dist, sc.verified, sc.unverified, sc.food_avg, sc.service_avg, sc.ambience_avg, sc.score
  from scored sc
  order by
    (case when p_sort = 'distance' then sc.dist end) asc nulls last,
    sc.score desc nulls last,
    sc.dist asc
  limit 100
$$;

revoke execute on function public.search_restaurants(double precision, double precision, numeric, text, text, text) from public;
grant execute on function public.search_restaurants(double precision, double precision, numeric, text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------
-- Plan sali: krzesła do rezerwacji, ustawienie krzeseł, stałe elementy
-- ---------------------------------------------------------------

-- „seat” to pojedyncze krzesło albo hoker, który gość rezerwuje jak stolik, na przykład przy barze.
alter table public.dining_tables
  add column kind    text not null default 'table' check (kind in ('table', 'seat')),
  add column chairs  jsonb check (chairs is null or jsonb_typeof(chairs) = 'array');

comment on column public.dining_tables.chairs is
  'Własne położenie krzeseł: [{"x": cm, "y": cm}] względem środka blatu. Null oznacza ustawienie automatyczne.';

create table public.floor_elements (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  zone           text not null default 'sala',
  x_cm           integer not null default 100 check (x_cm between 0 and 10000),
  y_cm           integer not null default 100 check (y_cm between 0 and 10000),
  width_cm       integer not null default 100 check (width_cm between 5 and 5000),
  height_cm      integer not null default 40 check (height_cm between 5 and 5000),
  rotation       smallint not null default 0 check (rotation between 0 and 359),
  shape          text not null default 'rect' check (shape in ('rect', 'round'))
);

create index floor_elements_restaurant_idx on public.floor_elements (restaurant_id);

alter table public.floor_elements enable row level security;

create policy "Personel widzi stałe elementy sali"
  on public.floor_elements for select to authenticated
  using (private.has_staff_role(restaurant_id));

create policy "Kierownik zmienia stałe elementy sali"
  on public.floor_elements for all to authenticated
  using (private.has_staff_role(restaurant_id, 'manager'))
  with check (private.has_staff_role(restaurant_id, 'manager'));

-- ---------------------------------------------------------------
-- Pracownicy i dyspozycyjność
-- ---------------------------------------------------------------

create table public.staff_members (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  name           text not null check (char_length(btrim(name)) between 1 and 80),
  position       text check (char_length(position) <= 40),
  phone          text check (char_length(phone) <= 20),
  color          smallint not null default 0 check (color between 0 and 7),
  active         boolean not null default true,
  created_at     timestamptz not null default now()
);

create index staff_members_restaurant_idx on public.staff_members (restaurant_id);

create table public.staff_availability (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  member_id      uuid not null references public.staff_members (id) on delete cascade,
  day            date not null,
  starts         time not null,
  ends           time not null,
  note           text check (char_length(note) <= 200),
  created_at     timestamptz not null default now(),
  check (ends > starts)
);

create index staff_availability_day_idx on public.staff_availability (restaurant_id, day);
create index staff_availability_member_idx on public.staff_availability (member_id);

alter table public.staff_members enable row level security;
alter table public.staff_availability enable row level security;

create policy "Personel widzi pracowników"
  on public.staff_members for select to authenticated
  using (private.has_staff_role(restaurant_id));

create policy "Kierownik zmienia pracowników"
  on public.staff_members for all to authenticated
  using (private.has_staff_role(restaurant_id, 'manager'))
  with check (private.has_staff_role(restaurant_id, 'manager'));

create policy "Personel widzi dyspozycyjność"
  on public.staff_availability for select to authenticated
  using (private.has_staff_role(restaurant_id));

create policy "Kierownik zmienia dyspozycyjność"
  on public.staff_availability for all to authenticated
  using (private.has_staff_role(restaurant_id, 'manager'))
  with check (
    private.has_staff_role(restaurant_id, 'manager')
    and exists (
      select 1 from public.staff_members m
      where m.id = member_id and m.restaurant_id = staff_availability.restaurant_id
    )
  );

-- ---------------------------------------------------------------
-- Karty podarunkowe
-- Tryb testowy: zakup bez płatności. Stripe podłączymy później.
-- ---------------------------------------------------------------

create table public.gift_cards (
  id              uuid primary key default gen_random_uuid(),
  restaurant_id   uuid not null references public.restaurants (id) on delete cascade,
  buyer_id        uuid references auth.users (id) on delete set null,
  code            text not null unique,
  initial_grosze  integer not null check (initial_grosze between 2000 and 200000),
  balance_grosze  integer not null check (balance_grosze >= 0),
  recipient_name  text check (char_length(recipient_name) <= 80),
  message         text check (char_length(message) <= 300),
  test_mode       boolean not null default true,
  status          text not null default 'active' check (status in ('active', 'void')),
  expires_at      timestamptz not null default (now() + interval '12 months'),
  created_at      timestamptz not null default now(),
  check (balance_grosze <= initial_grosze)
);

create index gift_cards_restaurant_idx on public.gift_cards (restaurant_id, created_at desc);
create index gift_cards_buyer_idx on public.gift_cards (buyer_id);

create table public.gift_card_redemptions (
  id             uuid primary key default gen_random_uuid(),
  card_id        uuid not null references public.gift_cards (id) on delete cascade,
  amount_grosze  integer not null check (amount_grosze > 0),
  staff_id       uuid references auth.users (id) on delete set null,
  created_at     timestamptz not null default now()
);

create index gift_card_redemptions_card_idx on public.gift_card_redemptions (card_id);

alter table public.gift_cards enable row level security;
alter table public.gift_card_redemptions enable row level security;

create policy "Gość widzi swoje karty"
  on public.gift_cards for select to authenticated
  using (buyer_id = (select auth.uid()));

create policy "Personel widzi karty lokalu"
  on public.gift_cards for select to authenticated
  using (private.has_staff_role(restaurant_id));

create policy "Gość widzi realizacje swoich kart"
  on public.gift_card_redemptions for select to authenticated
  using (exists (
    select 1 from public.gift_cards c
    where c.id = card_id and c.buyer_id = (select auth.uid())
  ));

create policy "Personel widzi realizacje kart lokalu"
  on public.gift_card_redemptions for select to authenticated
  using (exists (
    select 1 from public.gift_cards c
    where c.id = card_id and private.has_staff_role(c.restaurant_id)
  ));

-- Kod bez znaków, które łatwo pomylić (0/O, 1/I/L): XXXX-XXXX-XXXX.
create or replace function private.new_gift_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_alphabet  constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_bytes     bytea := extensions.gen_random_bytes(12);
  v_code      text := '';
begin
  for i in 0..11 loop
    v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, i) % length(v_alphabet)) + 1, 1);
    if i in (3, 7) then
      v_code := v_code || '-';
    end if;
  end loop;
  return v_code;
end;
$$;

revoke execute on function private.new_gift_code() from public, anon, authenticated;

create or replace function public.purchase_gift_card(
  p_restaurant_id   uuid,
  p_amount_grosze   integer,
  p_recipient_name  text default null,
  p_message         text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_plan  public.restaurant_plan;
  v_id    uuid;
  v_try   integer := 0;
begin
  if v_uid is null then
    raise exception 'Zaloguj się, żeby kupić kartę podarunkową.';
  end if;

  select plan into v_plan from restaurants where id = p_restaurant_id;
  if not found then
    raise exception 'Nie znaleziono restauracji.';
  end if;
  if v_plan <> 'pro' then
    raise exception 'Ta restauracja nie sprzedaje kart podarunkowych.';
  end if;

  if p_amount_grosze is null or p_amount_grosze not between 2000 and 200000
     or p_amount_grosze % 100 <> 0 then
    raise exception 'Wybierz kwotę od 20 do 2000 zł w pełnych złotych.';
  end if;

  loop
    v_try := v_try + 1;
    begin
      insert into gift_cards (
        restaurant_id, buyer_id, code, initial_grosze, balance_grosze, recipient_name, message
      ) values (
        p_restaurant_id, v_uid, private.new_gift_code(), p_amount_grosze, p_amount_grosze,
        nullif(btrim(p_recipient_name), ''), nullif(btrim(p_message), '')
      )
      returning id into v_id;
      exit;
    exception
      when unique_violation then
        if v_try >= 5 then
          raise exception 'Nie udało się utworzyć karty. Spróbuj ponownie.';
        end if;
    end;
  end loop;

  return v_id;
end;
$$;

create or replace function public.my_gift_cards()
returns table (
  id               uuid,
  restaurant_id    uuid,
  restaurant_name  text,
  restaurant_city  text,
  logo_url         text,
  code             text,
  initial_grosze   integer,
  balance_grosze   integer,
  recipient_name   text,
  message          text,
  test_mode        boolean,
  status           text,
  expires_at       timestamptz,
  created_at       timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.restaurant_id, r.name, r.city, r.logo_url, c.code, c.initial_grosze,
         c.balance_grosze, c.recipient_name, c.message, c.test_mode, c.status,
         c.expires_at, c.created_at
  from gift_cards c
  join restaurants r on r.id = c.restaurant_id
  where c.buyer_id = auth.uid()
  order by c.created_at desc
$$;

create or replace function public.panel_gift_cards(
  p_restaurant_id  uuid,
  p_code           text default null
)
returns table (
  id              uuid,
  code            text,
  initial_grosze  integer,
  balance_grosze  integer,
  recipient_name  text,
  message         text,
  test_mode       boolean,
  status          text,
  expires_at      timestamptz,
  created_at      timestamptz,
  last_used_at    timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_code  text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
begin
  perform private.require_staff(p_restaurant_id);

  return query
  select c.id, c.code, c.initial_grosze, c.balance_grosze, c.recipient_name, c.message,
         c.test_mode, c.status, c.expires_at, c.created_at,
         (select max(x.created_at) from gift_card_redemptions x where x.card_id = c.id)
  from gift_cards c
  where c.restaurant_id = p_restaurant_id
    and (v_code = '' or replace(c.code, '-', '') = v_code)
  order by c.created_at desc
  limit 500;
end;
$$;

create or replace function public.panel_redeem_gift_card(
  p_card_id        uuid,
  p_amount_grosze  integer
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_card  gift_cards%rowtype;
begin
  select * into v_card from gift_cards where id = p_card_id for update;
  if not found then
    raise exception 'Nie znaleziono karty.';
  end if;

  perform private.require_staff(v_card.restaurant_id);

  if v_card.status <> 'active' then
    raise exception 'Ta karta jest unieważniona.';
  end if;
  if v_card.expires_at < now() then
    raise exception 'Karta straciła ważność %.', to_char(v_card.expires_at, 'DD.MM.YYYY');
  end if;
  if p_amount_grosze is null or p_amount_grosze <= 0 then
    raise exception 'Wpisz kwotę do pobrania z karty.';
  end if;
  if p_amount_grosze > v_card.balance_grosze then
    raise exception 'Na karcie zostało tylko % zł.', replace(to_char(v_card.balance_grosze / 100.0, 'FM999990.00'), '.', ',');
  end if;

  update gift_cards set balance_grosze = balance_grosze - p_amount_grosze where id = p_card_id;
  insert into gift_card_redemptions (card_id, amount_grosze, staff_id)
  values (p_card_id, p_amount_grosze, auth.uid());

  return v_card.balance_grosze - p_amount_grosze;
end;
$$;

revoke execute on function public.purchase_gift_card(uuid, integer, text, text) from public, anon;
revoke execute on function public.my_gift_cards() from public, anon;
revoke execute on function public.panel_gift_cards(uuid, text) from public, anon;
revoke execute on function public.panel_redeem_gift_card(uuid, integer) from public, anon;

grant execute on function public.purchase_gift_card(uuid, integer, text, text) to authenticated;
grant execute on function public.my_gift_cards() to authenticated;
grant execute on function public.panel_gift_cards(uuid, text) to authenticated;
grant execute on function public.panel_redeem_gift_card(uuid, integer) to authenticated;
