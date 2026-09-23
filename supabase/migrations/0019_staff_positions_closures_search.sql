-- Table · migracja 0019
-- 1. Stanowiska pracowników z uprawnieniami. Kelner, Kucharz i Dostawca są systemowe i nie da się ich usunąć,
--    bo z nich skorzystają przyszłe pakiety (np. pakiet Dostawca z aplikacją dla kurierów).
-- 2. Pracownik ma imię, nazwisko, telefon i stanowisko.
-- 3. Dni wyjątkowe: lokal zamknięty albo inne godziny w konkretnym dniu.
-- 4. Wyszukiwanie lokali bez rozróżniania polskich znaków.
-- 5. Wyłączanie stolika przez obsługę i przenoszenie jego rezerwacji na inne stoliki.
-- 6. Zbiorowe odwoływanie rezerwacji, na przykład w dniu zamknięcia.

create extension if not exists unaccent with schema extensions;

-- ---------------------------------------------------------------
-- 1. Stanowiska
-- ---------------------------------------------------------------

create table public.staff_positions (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid references public.restaurants (id) on delete cascade,
  system_key     text unique check (system_key in ('waiter', 'cook', 'courier')),
  name           text not null check (char_length(btrim(name)) between 1 and 40),
  permissions    text[] not null default '{}',
  sort           smallint not null default 100,
  created_at     timestamptz not null default now(),
  -- Stanowisko systemowe nie należy do lokalu, własne zawsze należy.
  check ((restaurant_id is null) = (system_key is not null))
);

create unique index staff_positions_name_idx
  on public.staff_positions (restaurant_id, lower(btrim(name)))
  where restaurant_id is not null;

alter table public.staff_positions enable row level security;

create policy "Obsługa widzi stanowiska"
  on public.staff_positions for select to authenticated
  using (restaurant_id is null or private.has_staff_role(restaurant_id));

create policy "Kierownik zmienia własne stanowiska"
  on public.staff_positions for all to authenticated
  using (restaurant_id is not null and private.has_staff_role(restaurant_id, 'manager'))
  with check (restaurant_id is not null and private.has_staff_role(restaurant_id, 'manager'));

insert into public.staff_positions (system_key, name, permissions, sort) values
  ('waiter',  'Kelner',   array['reservations', 'floor', 'orders', 'gift_cards'], 1),
  ('cook',    'Kucharz',  array['kitchen', 'menu'], 2),
  ('courier', 'Dostawca', array['deliveries'], 3);

-- ---------------------------------------------------------------
-- 2. Pracownik: imię, nazwisko, telefon, stanowisko
-- ---------------------------------------------------------------

alter table public.staff_members
  add column first_name   text check (char_length(btrim(first_name)) between 1 and 40),
  add column last_name    text check (char_length(btrim(last_name)) between 1 and 60),
  add column position_id  uuid references public.staff_positions (id) on delete restrict;

create index staff_members_position_idx on public.staff_members (position_id);

-- Dotychczasowe imię i nazwisko w jednym polu dzielimy na pierwszym odstępie.
update public.staff_members
set first_name = split_part(btrim(name), ' ', 1),
    last_name = nullif(btrim(substr(btrim(name), char_length(split_part(btrim(name), ' ', 1)) + 1)), '');

-- Dotychczasowe stanowiska tekstowe: znane nazwy trafiają na systemowe, reszta staje się własnymi.
update public.staff_members m
set position_id = p.id
from public.staff_positions p
where p.system_key = case
    when lower(btrim(m.position)) in ('kelner', 'kelnerka') then 'waiter'
    when lower(btrim(m.position)) in ('kucharz', 'kucharka') then 'cook'
    when lower(btrim(m.position)) in ('dostawca', 'kurier') then 'courier'
  end;

insert into public.staff_positions (restaurant_id, name)
select distinct m.restaurant_id, btrim(m.position)
from public.staff_members m
where m.position_id is null and nullif(btrim(m.position), '') is not null
on conflict do nothing;

update public.staff_members m
set position_id = p.id
from public.staff_positions p
where m.position_id is null
  and p.restaurant_id = m.restaurant_id
  and lower(btrim(p.name)) = lower(btrim(m.position));

-- Przypisać można tylko stanowisko systemowe albo własne stanowisko tego samego lokalu.
create or replace function private.check_staff_position()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.position_id is not null and not exists (
    select 1 from staff_positions p
    where p.id = new.position_id
      and (p.restaurant_id is null or p.restaurant_id = new.restaurant_id)
  ) then
    raise exception 'To stanowisko należy do innego lokalu.';
  end if;
  return new;
end;
$$;

create trigger staff_members_position_check
  before insert or update of position_id on public.staff_members
  for each row execute function private.check_staff_position();

revoke execute on function private.check_staff_position() from public, anon, authenticated;

-- ---------------------------------------------------------------
-- 3. Dni wyjątkowe
-- ---------------------------------------------------------------

create table public.opening_exceptions (
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  day            date not null,
  closed         boolean not null default true,
  opens          time,
  closes         time,
  note           text check (char_length(note) <= 120),
  created_at     timestamptz not null default now(),
  primary key (restaurant_id, day),
  check (closed or (opens is not null and closes is not null and closes > opens))
);

alter table public.opening_exceptions enable row level security;

-- Informacja o zamknięciu nie jest poufna: aplikacja gościa może ją pokazać przy lokalu.
create policy "Każdy widzi dni wyjątkowe"
  on public.opening_exceptions for select to anon, authenticated
  using (true);

create policy "Kierownik zmienia dni wyjątkowe"
  on public.opening_exceptions for all to authenticated
  using (private.has_staff_role(restaurant_id, 'manager'))
  with check (private.has_staff_role(restaurant_id, 'manager'));

-- Godziny otwarcia w danym dniu: dzień wyjątkowy ma pierwszeństwo przed tygodniowym.
-- Brak wiersza oznacza, że lokal jest zamknięty.
create or replace function private.hours_on(p_restaurant_id uuid, p_date date)
returns table (opens time, closes time)
language sql
stable
security definer
set search_path = public
as $$
  select e.opens, e.closes
  from opening_exceptions e
  where e.restaurant_id = p_restaurant_id and e.day = p_date and not e.closed
  union all
  select oh.opens, oh.closes
  from opening_hours oh
  where oh.restaurant_id = p_restaurant_id
    and oh.weekday = extract(isodow from p_date)
    and not exists (
      select 1 from opening_exceptions e
      where e.restaurant_id = p_restaurant_id and e.day = p_date
    )
$$;

revoke execute on function private.hours_on(uuid, date) from public, anon, authenticated;

create or replace function public.available_slots(
  p_restaurant_id  uuid,
  p_date           date,
  p_party_size     integer
)
returns table (slot_start timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  with r as (
    select id, timezone, slot_interval_min, max_party_size
    from restaurants
    where id = p_restaurant_id and plan = 'pro'
  ),
  h as (
    select x.opens, x.closes
    from r, private.hours_on(r.id, p_date) as x
  ),
  d as (
    select private.visit_minutes(p_party_size) as visit,
           private.cleanup_minutes(p_party_size) as cleanup
  ),
  series as (
    select (gs at time zone r.timezone) as starts_at, d.visit, d.cleanup
    from r, h, d,
      generate_series(
        p_date + h.opens,
        p_date + h.closes - make_interval(mins => d.visit),
        make_interval(mins => r.slot_interval_min)
      ) as gs
  )
  select s.starts_at
  from series s
  where p_party_size between 1 and (select max_party_size from r)
    and s.starts_at > now() + interval '30 minutes'
    and private.find_tables(
          p_restaurant_id,
          p_party_size,
          tstzrange(s.starts_at, s.starts_at + make_interval(mins => s.visit + s.cleanup))
        ) is not null
  order by s.starts_at
$$;

create or replace function public.book_table(
  p_restaurant_id  uuid,
  p_starts_at      timestamptz,
  p_party_size     integer,
  p_occasion       public.reservation_occasion default null,
  p_message        text default null,
  p_diet           text default null,
  p_diet_consent   boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_rest      record;
  v_hours     record;
  v_local     timestamp;
  v_visit     integer;
  v_cleanup   integer;
  v_ends      timestamptz;
  v_slot      tstzrange;
  v_ids       uuid[];
  v_res_id    uuid;
  v_attempt   integer := 0;
  v_upcoming  integer;
begin
  if v_uid is null then
    raise exception 'Zaloguj się, żeby zarezerwować stolik.';
  end if;

  select id, timezone, slot_interval_min, plan, max_party_size into v_rest
  from restaurants where id = p_restaurant_id;

  if not found then
    raise exception 'Nie znaleziono restauracji.';
  end if;

  if p_party_size is null or p_party_size not between 1 and v_rest.max_party_size then
    raise exception 'Rezerwacja w aplikacji obejmuje od 1 do % osób. Większą grupę umów telefonicznie.', v_rest.max_party_size;
  end if;

  if v_rest.plan <> 'pro' then
    raise exception 'Ta restauracja przyjmuje rezerwacje tylko telefonicznie.';
  end if;

  if p_starts_at < now() + interval '30 minutes' or p_starts_at > now() + interval '60 days' then
    raise exception 'Wybierz termin od 30 minut do 60 dni od teraz.';
  end if;

  v_visit   := private.visit_minutes(p_party_size);
  v_cleanup := private.cleanup_minutes(p_party_size);
  v_local   := p_starts_at at time zone v_rest.timezone;

  if extract(minute from v_local)::integer % v_rest.slot_interval_min <> 0
     or extract(second from v_local) <> 0 then
    raise exception 'Wybierz godzinę z listy wolnych terminów.';
  end if;

  select x.opens, x.closes into v_hours
  from private.hours_on(p_restaurant_id, v_local::date) as x;

  if not found
     or v_local::time < v_hours.opens
     or v_local + make_interval(mins => v_visit) > v_local::date + v_hours.closes then
    raise exception 'Restauracja jest wtedy zamknięta.';
  end if;

  if nullif(btrim(p_diet), '') is not null and not coalesce(p_diet_consent, false) then
    raise exception 'Zaznacz zgodę, żeby przekazać restauracji informację o alergiach.';
  end if;

  select count(*) into v_upcoming
  from reservations
  where user_id = v_uid and status = 'confirmed' and starts_at > now();

  if v_upcoming >= 5 then
    raise exception 'Masz już 5 nadchodzących rezerwacji. Odwołaj jedną, żeby dodać kolejną.';
  end if;

  v_ends := p_starts_at + make_interval(mins => v_visit);
  v_slot := tstzrange(p_starts_at, v_ends + make_interval(mins => v_cleanup));

  insert into reservations (
    restaurant_id, user_id, party_size, starts_at, ends_at,
    occasion, message, message_delete_after
  )
  values (
    p_restaurant_id, v_uid, p_party_size, p_starts_at, v_ends,
    p_occasion, nullif(btrim(p_message), ''), v_ends + interval '30 days'
  )
  returning id into v_res_id;

  -- Blokada w bazie rozstrzyga wyścig. Przy kolizji próbujemy kolejnego stolika.
  loop
    v_attempt := v_attempt + 1;
    v_ids := private.find_tables(p_restaurant_id, p_party_size, v_slot);

    if v_ids is null then
      raise exception 'Ten termin właśnie się zajął. Wybierz inną godzinę.';
    end if;

    begin
      insert into table_holds (reservation_id, table_id, slot)
      select v_res_id, t.table_id, v_slot
      from unnest(v_ids) as t(table_id);
      exit;
    exception
      when exclusion_violation then
        if v_attempt >= 5 then
          raise exception 'Ten termin właśnie się zajął. Wybierz inną godzinę.';
        end if;
    end;
  end loop;

  if nullif(btrim(p_diet), '') is not null then
    insert into reservation_diets (reservation_id, details, delete_after)
    values (v_res_id, btrim(p_diet), v_ends + interval '30 days');
  end if;

  return v_res_id;
end;
$$;

-- ---------------------------------------------------------------
-- 4. Wyszukiwanie bez ogonków
-- ---------------------------------------------------------------

create or replace function public.search_restaurants(
  p_lat        double precision,
  p_lng        double precision,
  p_radius_km  numeric default 10,
  p_cuisine    text default null,
  p_sort       text default 'ranking',
  p_city       text default null,
  p_query      text default null
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
  with q as (
    select nullif(btrim(p_query), '') as text
  ),
  origin as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  ),
  nearby as (
    select r.*, st_distance(r.location, o.g) as dist
    from restaurants r, origin o, q
    where (
        case
          when q.text is not null then
            unaccent(r.name) ilike '%' || unaccent(q.text) || '%'
            or unaccent(r.city) ilike '%' || unaccent(q.text) || '%'
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
      end as score,
      -- Lokal zaczynający się od wpisanej frazy jest najbliżej tego, czego gość szuka.
      case when (select text from q) is null then 2
           when unaccent(n.name) ilike unaccent((select text from q)) || '%' then 0
           when unaccent(n.name) ilike '%' || unaccent((select text from q)) || '%' then 1
           else 2
      end as match_rank
    from nearby n
    left join stats s on s.restaurant_id = n.id
    cross join region
  )
  select
    sc.id, sc.name, sc.cuisine, sc.price_level, sc.address, sc.city, sc.plan, sc.is_example, sc.logo_url,
    sc.dist, sc.verified, sc.unverified, sc.food_avg, sc.service_avg, sc.ambience_avg, sc.score
  from scored sc
  order by
    sc.match_rank asc,
    (case when p_sort = 'distance' then sc.dist end) asc nulls last,
    sc.score desc nulls last,
    sc.dist asc
  limit 100
$$;

-- ---------------------------------------------------------------
-- 5. Wyłączanie stolika i przenoszenie jego rezerwacji
-- ---------------------------------------------------------------

-- Obsługa może wyłączyć zepsuty stolik w trakcie pracy, bez uprawnień kierownika.
-- Zwraca liczbę nadchodzących rezerwacji, które nadal są na tym stoliku.
create or replace function public.panel_set_table_active(p_table_id uuid, p_active boolean)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
  v_count       integer;
begin
  select restaurant_id into v_restaurant from dining_tables where id = p_table_id;
  if not found then
    raise exception 'Nie znaleziono stolika.';
  end if;

  perform private.require_staff(v_restaurant);

  update dining_tables set active = p_active where id = p_table_id;

  select count(distinct h.reservation_id) into v_count
  from table_holds h
  join reservations r on r.id = h.reservation_id
  where h.table_id = p_table_id
    and h.active
    and r.status = 'confirmed'
    and lower(h.slot) > now();

  return v_count;
end;
$$;

-- Przenosi nadchodzące rezerwacje ze stolika na inne wolne stoliki na ten sam czas.
-- Rezerwacje, dla których nie ma miejsca, zostają na miejscu do ręcznego przeniesienia.
create or replace function public.panel_reassign_table(p_table_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
  v_res         record;
  v_ids         uuid[];
  v_moved       integer := 0;
  v_failed      integer := 0;
begin
  select restaurant_id into v_restaurant from dining_tables where id = p_table_id;
  if not found then
    raise exception 'Nie znaleziono stolika.';
  end if;

  perform private.require_staff(v_restaurant);

  for v_res in
    select distinct r.id, r.party_size, h.slot
    from table_holds h
    join reservations r on r.id = h.reservation_id
    where h.table_id = p_table_id
      and h.active
      and r.status = 'confirmed'
      and lower(h.slot) > now()
    order by h.slot
  loop
    -- Zwalniamy stoliki tej rezerwacji na czas szukania, żeby mogła dostać też swój drugi stolik.
    update table_holds set active = false where reservation_id = v_res.id;
    v_ids := private.find_tables(v_restaurant, v_res.party_size, v_res.slot);

    if v_ids is null or p_table_id = any(v_ids) then
      update table_holds set active = true where reservation_id = v_res.id;
      v_failed := v_failed + 1;
    else
      delete from table_holds where reservation_id = v_res.id;
      insert into table_holds (reservation_id, table_id, slot)
      select v_res.id, t.table_id, v_res.slot from unnest(v_ids) as t(table_id);
      update reservations set updated_at = now() where id = v_res.id;
      v_moved := v_moved + 1;
    end if;
  end loop;

  return jsonb_build_object('moved', v_moved, 'failed', v_failed);
end;
$$;

-- ---------------------------------------------------------------
-- 6. Zbiorowe odwoływanie
-- ---------------------------------------------------------------

-- Odwołuje wskazane potwierdzone rezerwacje lokalu i dopisuje powód do notatki obsługi.
create or replace function public.panel_cancel_reservations(
  p_restaurant_id  uuid,
  p_ids            uuid[],
  p_reason         text default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids  uuid[];
begin
  perform private.require_staff(p_restaurant_id, 'manager');

  with changed as (
    update reservations
    set status = 'cancelled',
        staff_note = left(
          concat_ws(' · ', nullif(btrim(staff_note), ''), nullif(btrim(p_reason), '')),
          500
        ),
        updated_at = now()
    where restaurant_id = p_restaurant_id
      and id = any(p_ids)
      and status = 'confirmed'
    returning id
  )
  select coalesce(array_agg(id), '{}') into v_ids from changed;

  update table_holds set active = false where reservation_id = any(v_ids);

  return cardinality(v_ids);
end;
$$;

revoke execute on function public.panel_set_table_active(uuid, boolean) from public, anon;
revoke execute on function public.panel_reassign_table(uuid) from public, anon;
revoke execute on function public.panel_cancel_reservations(uuid, uuid[], text) from public, anon;

grant execute on function public.panel_set_table_active(uuid, boolean) to authenticated;
grant execute on function public.panel_reassign_table(uuid) to authenticated;
grant execute on function public.panel_cancel_reservations(uuid, uuid[], text) to authenticated;
