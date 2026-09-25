-- Table · migracja 0027
-- 1. Restauracja zakłada konto mailem firmowym i sama tworzy lokal. Nowy lokal działa w panelu od razu,
--    a gościom pokazuje się dopiero po weryfikacji przez Table (restaurants.listed).
-- 2. Czas pracy: pracownik zaczyna zmianę, skanując aplikacją Table Praca kod QR z panelu.
--    Skan odblokowuje też panel na uprawnienia jego stanowiska.
-- 3. Zamówienia zapisują, który pracownik je nabił (do statystyk obsługi).
-- 4. Statystyki sprzedaży i dostęp do historii zamówień z uprawnieniem „Statystyki”.

-- ---------------------------------------------------------------
-- 1. Lokale zakładane przez restauracje
-- ---------------------------------------------------------------

alter table public.restaurants add column listed boolean not null default false;
update public.restaurants set listed = true;

comment on column public.restaurants.listed is
  'Lokal widoczny dla gości. Nowe lokale czekają na weryfikację przez Table.';

-- Dwie polityki, bo gość bez logowania (anon) nie ma dostępu do schematu private.
drop policy "Lokale widoczne dla wszystkich" on public.restaurants;
create policy "Goście widzą zweryfikowane lokale"
  on public.restaurants for select to anon, authenticated
  using (listed);
create policy "Obsługa widzi swoje lokale, także przed weryfikacją"
  on public.restaurants for select to authenticated
  using (private.has_staff_role(id));

-- Wyszukiwarka gości pomija lokale bez weryfikacji.
create or replace function public.search_restaurants(p_lat double precision, p_lng double precision, p_radius_km numeric DEFAULT 10, p_cuisine text DEFAULT NULL::text, p_sort text DEFAULT 'ranking'::text, p_city text DEFAULT NULL::text, p_query text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, name text, cuisine text, price_level smallint, address text, city text, plan restaurant_plan, is_example boolean, logo_url text, distance_m double precision, verified_reviews integer, unverified_reviews integer, food_avg numeric, service_avg numeric, ambience_avg numeric, food_score numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  with q as (
    select nullif(btrim(p_query), '') as text
  ),
  origin as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  ),
  nearby as (
    select r.*, st_distance(r.location, o.g) as dist
    from restaurants r, origin o, q
    where r.listed
      and (
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
$function$;

-- Lista lokali w panelu z informacją, czy goście już je widzą.
drop function public.panel_my_restaurants();
create or replace function public.panel_my_restaurants()
returns table (id uuid, name text, city text, plan restaurant_plan, role staff_role, timezone text,
               logo_url text, listed boolean)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.name, r.city, r.plan, s.role, r.timezone, r.logo_url, r.listed
  from restaurant_staff s
  join restaurants r on r.id = s.restaurant_id
  where s.user_id = auth.uid()
  order by r.name
$$;

revoke execute on function public.panel_my_restaurants() from public, anon;
grant execute on function public.panel_my_restaurants() to authenticated;

-- Tworzy lokal dla zalogowanego konta firmowego i czyni je właścicielem.
-- Położenie na mapie: środek innych lokali w tym mieście albo środek Polski; poprawia je weryfikacja.
create or replace function public.panel_create_restaurant(
  p_name     text,
  p_nip      text,
  p_city     text,
  p_address  text,
  p_phone    text,
  p_cuisine  text
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid       uuid := auth.uid();
  v_nip       text := regexp_replace(coalesce(p_nip, ''), '[^0-9]', '', 'g');
  v_location  geography;
  v_id        uuid;
begin
  if v_uid is null then
    raise exception 'Zaloguj się, żeby utworzyć lokal.';
  end if;
  if coalesce(btrim(p_name), '') = '' or coalesce(btrim(p_city), '') = ''
     or coalesce(btrim(p_address), '') = '' or coalesce(btrim(p_cuisine), '') = '' then
    raise exception 'Uzupełnij nazwę, miasto, adres i rodzaj kuchni.';
  end if;
  if length(v_nip) <> 10 then
    raise exception 'NIP ma 10 cyfr.';
  end if;
  if length(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')) < 9 then
    raise exception 'Wpisz numer telefonu lokalu, co najmniej 9 cyfr.';
  end if;
  if (select count(*) from restaurant_staff where user_id = v_uid and role = 'owner') >= 5 then
    raise exception 'Jedno konto może mieć najwyżej 5 lokali. Napisz do nas, jeśli potrzebujesz więcej.';
  end if;

  select st_centroid(st_collect(r.location::geometry))::geography into v_location
  from restaurants r
  where r.listed and lower(r.city) = lower(btrim(p_city));
  v_location := coalesce(v_location, st_setsrid(st_makepoint(19.4, 52.0), 4326)::geography);

  insert into restaurants (name, cuisine, address, city, phone, nip, location, plan, listed)
  values (btrim(p_name), btrim(p_cuisine), btrim(p_address), btrim(p_city), btrim(p_phone), v_nip,
          v_location, 'free', false)
  returning id into v_id;

  insert into restaurant_staff (restaurant_id, user_id, role) values (v_id, v_uid, 'owner');
  return v_id;
end;
$$;

revoke execute on function public.panel_create_restaurant(text, text, text, text, text, text) from public, anon;
grant execute on function public.panel_create_restaurant(text, text, text, text, text, text) to authenticated;

-- ---------------------------------------------------------------
-- 2. Uprawnienia: dane lokalu i statystyki
-- ---------------------------------------------------------------

create or replace function public.panel_my_permissions(p_restaurant_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when private.has_staff_role(p_restaurant_id, 'manager') then
      array['reservations', 'floor', 'floor_edit', 'menu', 'orders', 'kitchen',
            'deliveries', 'gift_cards', 'reviews', 'stats', 'staff', 'profile']
    else coalesce((
      select p.permissions
      from public.staff_members m
      join public.staff_positions p on p.id = m.position_id
      where m.restaurant_id = p_restaurant_id
        and m.user_id = (select auth.uid())
        and m.active
      limit 1
    ), '{}')
  end
$$;

-- Historia zamówień jest w statystykach, więc stanowisko ze statystykami też ją czyta.
drop policy "Obsługa i kuchnia widzą zamówienia" on public.orders;
drop policy "Obsługa i kuchnia widzą pozycje zamówień" on public.order_items;

create policy "Obsługa, kuchnia i statystyki widzą zamówienia"
  on public.orders for select to authenticated
  using (
    private.has_permission(restaurant_id, 'orders')
    or private.has_permission(restaurant_id, 'kitchen')
    or private.has_permission(restaurant_id, 'stats')
  );

create policy "Obsługa, kuchnia i statystyki widzą pozycje zamówień"
  on public.order_items for select to authenticated
  using (
    private.has_permission(restaurant_id, 'orders')
    or private.has_permission(restaurant_id, 'kitchen')
    or private.has_permission(restaurant_id, 'stats')
  );

-- ---------------------------------------------------------------
-- 3. Czas pracy i logowanie kodem QR
-- ---------------------------------------------------------------

-- Numer telefonu w jednej postaci: same cyfry z kierunkowym (48 dla 9 cyfr bez kierunkowego).
create or replace function private.norm_phone(p text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when length(d) = 9 then '48' || d
    when d like '0048%' then substr(d, 3)
    else d
  end
  from (select regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') as d) x
$$;

-- Aktywni pracownicy z numerem telefonu zalogowanego konta (aplikacja Table Praca).
create or replace function private.my_members()
returns setof public.staff_members
language sql
stable
security definer
set search_path = ''
as $$
  select m.*
  from public.staff_members m, auth.users u
  where u.id = (select auth.uid())
    and u.phone is not null
    and m.active
    and private.norm_phone(m.phone) = private.norm_phone(u.phone)
$$;

revoke execute on function private.norm_phone(text) from public, anon;
revoke execute on function private.my_members() from public, anon;
grant execute on function private.norm_phone(text) to authenticated;
grant execute on function private.my_members() to authenticated;

create table public.staff_shifts (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  member_id      uuid not null references public.staff_members (id) on delete cascade,
  started_at     timestamptz not null default now(),
  ended_at       timestamptz,
  -- scan: kod QR, panel: wpisana ręcznie przez kierownika
  source         text not null default 'scan' check (source in ('scan', 'panel')),
  created_at     timestamptz not null default now(),
  check (ended_at is null or ended_at > started_at)
);

-- Pracownik ma najwyżej jedną otwartą zmianę.
create unique index staff_shifts_open_idx on public.staff_shifts (member_id) where ended_at is null;
create index staff_shifts_restaurant_idx on public.staff_shifts (restaurant_id, started_at desc);

alter table public.staff_shifts enable row level security;

create policy "Obsługa widzi zmiany lokalu"
  on public.staff_shifts for select to authenticated
  using (private.has_staff_role(restaurant_id));

create policy "Pracownik widzi swoje zmiany"
  on public.staff_shifts for select to authenticated
  using (member_id in (select id from private.my_members()));

alter publication supabase_realtime add table public.staff_shifts;

-- Kody QR panelu. Każdy żyje 90 sekund i działa raz.
create table public.panel_login_tokens (
  token              text primary key,
  restaurant_id      uuid not null references public.restaurants (id) on delete cascade,
  created_by         uuid references auth.users (id) on delete set null,
  created_at         timestamptz not null default now(),
  expires_at         timestamptz not null default now() + interval '90 seconds',
  claimed_member_id  uuid references public.staff_members (id) on delete cascade,
  claimed_at         timestamptz
);

create index panel_login_tokens_restaurant_idx on public.panel_login_tokens (restaurant_id, created_at);
alter table public.panel_login_tokens enable row level security;
-- Bez polityk: kody czyta i zapisuje tylko baza przez funkcje poniżej.

-- Nowy kod QR dla panelu. Panel zmienia go co 30 sekund, więc zdjęcie kodu szybko przestaje działać.
create or replace function public.panel_new_login_token(p_restaurant_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token  text := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
begin
  perform private.require_staff(p_restaurant_id);
  delete from panel_login_tokens
  where restaurant_id = p_restaurant_id and expires_at < now() - interval '1 hour';
  insert into panel_login_tokens (token, restaurant_id, created_by) values (v_token, p_restaurant_id, auth.uid());
  return v_token;
end;
$$;

-- Czy ktoś zeskanował kod panelu. Zwraca pracownika i jego uprawnienia, żeby panel mógł się odblokować.
create or replace function public.panel_login_token_status(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row  panel_login_tokens%rowtype;
begin
  select * into v_row from panel_login_tokens where token = p_token;
  if not found then
    return null;
  end if;
  perform private.require_staff(v_row.restaurant_id);
  if v_row.claimed_member_id is null then
    return jsonb_build_object('claimed', false, 'expired', v_row.expires_at < now());
  end if;
  return (
    select jsonb_build_object(
      'claimed', true,
      'member_id', m.id,
      'name', m.name,
      'position', p.name,
      'permissions', coalesce(to_jsonb(p.permissions), '[]'::jsonb),
      'shift_started_at', (select s.started_at from staff_shifts s where s.member_id = m.id and s.ended_at is null)
    )
    from staff_members m
    left join staff_positions p on p.id = m.position_id
    where m.id = v_row.claimed_member_id
  );
end;
$$;

-- Aplikacja Table Praca: pracownik skanuje kod z panelu. Rozpoczyna zmianę (jeśli jeszcze trwa, zostaje)
-- i odblokowuje panel. Pracownika rozpoznajemy po numerze telefonu, którym się zalogował.
create or replace function public.staff_scan(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row      panel_login_tokens%rowtype;
  v_member   staff_members%rowtype;
  v_started  timestamptz;
  v_new      boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Zaloguj się numerem telefonu.';
  end if;

  select * into v_row from panel_login_tokens
  where token = regexp_replace(coalesce(p_token, ''), '^table-praca:', '')
  for update;
  if not found then
    raise exception 'To nie jest kod z panelu Table. Zeskanuj kod z ekranu „Zaloguj pracownika”.';
  end if;
  if v_row.expires_at < now() then
    raise exception 'Kod już wygasł. Zeskanuj nowy kod z panelu.';
  end if;
  if v_row.claimed_member_id is not null then
    raise exception 'Ten kod został już użyty. Zeskanuj nowy kod z panelu.';
  end if;

  select * into v_member from private.my_members() m where m.restaurant_id = v_row.restaurant_id limit 1;
  if not found then
    raise exception 'Twojego numeru nie ma na liście pracowników tego lokalu. Poproś kierownika o dodanie.';
  end if;

  -- Konto aplikacji zostaje przypisane do pracownika, żeby jego uprawnienia działały też poza panelem.
  if v_member.user_id is null then
    update staff_members set user_id = auth.uid() where id = v_member.id;
  end if;

  select started_at into v_started from staff_shifts where member_id = v_member.id and ended_at is null;
  if v_started is null then
    insert into staff_shifts (restaurant_id, member_id, source)
    values (v_member.restaurant_id, v_member.id, 'scan')
    returning started_at into v_started;
    v_new := true;
  end if;

  update panel_login_tokens set claimed_member_id = v_member.id, claimed_at = now() where token = v_row.token;

  return jsonb_build_object(
    'restaurant', (select name from restaurants where id = v_member.restaurant_id),
    'member', v_member.name,
    'shift_started_at', v_started,
    'started_now', v_new
  );
end;
$$;

-- Aplikacja Table Praca: lokale, w których pracuję, i czy trwa moja zmiana.
create or replace function public.staff_my_jobs()
returns table (member_id uuid, restaurant_id uuid, restaurant_name text, member_name text,
               position_name text, shift_id uuid, shift_started_at timestamptz,
               week_seconds bigint)
language sql
stable
security definer
set search_path = public
as $$
  select m.id, r.id, r.name, m.name, p.name, s.id, s.started_at,
         (select coalesce(sum(extract(epoch from coalesce(x.ended_at, now()) - x.started_at)), 0)::bigint
          from staff_shifts x
          where x.member_id = m.id and x.started_at >= date_trunc('week', now()))
  from private.my_members() m
  join restaurants r on r.id = m.restaurant_id
  left join staff_positions p on p.id = m.position_id
  left join staff_shifts s on s.member_id = m.id and s.ended_at is null
  order by r.name
$$;

-- Aplikacja Table Praca: moje zmiany z ostatnich dni.
create or replace function public.staff_my_shifts(p_days integer default 31)
returns table (id uuid, restaurant_name text, started_at timestamptz, ended_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select s.id, r.name, s.started_at, s.ended_at
  from staff_shifts s
  join restaurants r on r.id = s.restaurant_id
  where s.member_id in (select id from private.my_members())
    and s.started_at >= now() - make_interval(days => greatest(1, least(coalesce(p_days, 31), 366)))
  order by s.started_at desc
$$;

-- Kończy zmianę. Z aplikacji Table Praca (swoją) albo z panelu (dowolnego pracownika lokalu).
create or replace function public.staff_end_shift(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member  staff_members%rowtype;
begin
  select * into v_member from staff_members where id = p_member_id;
  if not found then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  if not (
    exists (select 1 from private.my_members() m where m.id = p_member_id)
    or private.has_staff_role(v_member.restaurant_id)
  ) then
    raise exception 'Nie możesz zakończyć tej zmiany.';
  end if;
  update staff_shifts set ended_at = now() where member_id = p_member_id and ended_at is null;
end;
$$;

-- Kierownik poprawia albo dopisuje zmianę ręcznie.
create or replace function public.panel_save_shift(
  p_id          uuid,
  p_member_id   uuid,
  p_started_at  timestamptz,
  p_ended_at    timestamptz
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member  staff_members%rowtype;
begin
  select * into v_member from staff_members where id = p_member_id;
  if not found then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  perform private.require_staff(v_member.restaurant_id, 'manager');
  if p_started_at is null or (p_ended_at is not null and p_ended_at <= p_started_at) then
    raise exception 'Koniec zmiany musi być po jej początku.';
  end if;
  if p_ended_at is not null and p_ended_at > now() + interval '1 minute' then
    raise exception 'Koniec zmiany nie może być w przyszłości.';
  end if;

  if p_id is null then
    insert into staff_shifts (restaurant_id, member_id, started_at, ended_at, source)
    values (v_member.restaurant_id, p_member_id, p_started_at, p_ended_at, 'panel');
  else
    update staff_shifts
    set started_at = p_started_at, ended_at = p_ended_at, source = 'panel'
    where id = p_id and restaurant_id = v_member.restaurant_id;
  end if;
exception
  when unique_violation then
    raise exception 'Ten pracownik ma już otwartą zmianę. Najpierw ją zakończ.';
end;
$$;

create or replace function public.panel_delete_shift(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
begin
  select restaurant_id into v_restaurant from staff_shifts where id = p_id;
  if v_restaurant is null then
    return;
  end if;
  perform private.require_staff(v_restaurant, 'manager');
  delete from staff_shifts where id = p_id;
end;
$$;

-- ---------------------------------------------------------------
-- 4. Zamówienia z pracownikiem
-- ---------------------------------------------------------------

alter table public.orders
  add column opened_by_member uuid references public.staff_members (id) on delete set null,
  add column closed_by_member uuid references public.staff_members (id) on delete set null;
alter table public.order_items
  add column created_by_member uuid references public.staff_members (id) on delete set null;

-- Pracownik zalogowany na panelu kodem QR: musi być z tego lokalu i mieć trwającą zmianę.
create or replace function private.check_member(p_restaurant_id uuid, p_member_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_member_id is null then
    return;
  end if;
  if not exists (
    select 1 from public.staff_members m
    join public.staff_shifts s on s.member_id = m.id and s.ended_at is null
    where m.id = p_member_id and m.restaurant_id = p_restaurant_id and m.active
  ) then
    raise exception 'Zmiana pracownika się skończyła. Zeskanuj kod z panelu jeszcze raz.';
  end if;
end;
$$;

revoke execute on function private.check_member(uuid, uuid) from public, anon;
grant execute on function private.check_member(uuid, uuid) to authenticated;

drop function public.panel_open_order(uuid, uuid);
create or replace function public.panel_open_order(
  p_restaurant_id  uuid,
  p_table_id       uuid,
  p_member_id      uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id   uuid;
  v_res  uuid;
begin
  perform private.require_permission(p_restaurant_id, 'orders');
  perform private.check_member(p_restaurant_id, p_member_id);

  if not exists (select 1 from dining_tables where id = p_table_id and restaurant_id = p_restaurant_id) then
    raise exception 'Nie znaleziono stolika.';
  end if;

  select id into v_id from orders where table_id = p_table_id and status = 'open';
  if found then
    return v_id;
  end if;

  select h.reservation_id into v_res
  from table_holds h
  join reservations r on r.id = h.reservation_id
  where h.table_id = p_table_id
    and h.active
    and r.status in ('seated', 'confirmed')
    and now() between lower(h.slot) - interval '30 minutes' and upper(h.slot)
  order by (r.status = 'seated') desc, lower(h.slot)
  limit 1;

  begin
    insert into orders (restaurant_id, table_id, reservation_id, opened_by, opened_by_member)
    values (p_restaurant_id, p_table_id, v_res, auth.uid(), p_member_id)
    returning id into v_id;
  exception
    when unique_violation then
      select id into v_id from orders where table_id = p_table_id and status = 'open';
  end;
  return v_id;
end;
$$;

drop function public.panel_add_order_item(uuid, uuid, text, text[], integer, text, integer);
create or replace function public.panel_add_order_item(
  p_order_id      uuid,
  p_menu_item_id  uuid,
  p_variant       text default null,
  p_addons        text[] default '{}',
  p_quantity      integer default 1,
  p_note          text default null,
  p_course        integer default 1,
  p_member_id     uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order    orders%rowtype;
  v_item     record;
  v_option   jsonb;
  v_price    integer;
  v_variant  text;
  v_addons   jsonb := '[]';
  v_name     text;
  v_id       uuid;
begin
  select * into v_order from orders where id = p_order_id;
  if not found then
    raise exception 'Nie znaleziono rachunku.';
  end if;
  perform private.require_permission(v_order.restaurant_id, 'orders');
  perform private.check_member(v_order.restaurant_id, p_member_id);
  if v_order.status <> 'open' then
    raise exception 'Ten rachunek jest już zamknięty.';
  end if;

  select i.id, i.name, i.price_grosze, i.variants, i.addons, i.vat_rate, i.available, s.restaurant_id
  into v_item
  from menu_items i
  join menu_sections s on s.id = i.section_id
  where i.id = p_menu_item_id;
  if not found or v_item.restaurant_id <> v_order.restaurant_id then
    raise exception 'Nie znaleziono pozycji w menu.';
  end if;
  if not v_item.available then
    raise exception 'Ta pozycja jest chwilowo niedostępna.';
  end if;
  if p_quantity is null or p_quantity not between 1 and 99 then
    raise exception 'Ilość od 1 do 99.';
  end if;

  if jsonb_array_length(v_item.variants) > 0 then
    select o into v_option from jsonb_array_elements(v_item.variants) o where o ->> 'name' = p_variant;
    if v_option is null then
      raise exception 'Wybierz wariant pozycji „%”.', v_item.name;
    end if;
    v_price := (v_option ->> 'price_grosze')::integer;
    v_variant := v_option ->> 'name';
  else
    v_price := v_item.price_grosze;
  end if;

  foreach v_name in array coalesce(p_addons, '{}') loop
    v_option := null;
    select o into v_option from jsonb_array_elements(v_item.addons) o where o ->> 'name' = v_name;
    if v_option is null then
      raise exception 'Pozycja „%” nie ma dodatku „%”.', v_item.name, v_name;
    end if;
    v_price := v_price + (v_option ->> 'price_grosze')::integer;
    v_addons := v_addons || jsonb_build_array(v_option);
  end loop;

  insert into order_items (
    order_id, restaurant_id, menu_item_id, name, variant, addons,
    unit_price_grosze, vat_rate, quantity, note, course, created_by, created_by_member
  )
  values (
    p_order_id, v_order.restaurant_id, v_item.id, v_item.name, v_variant, v_addons,
    v_price, v_item.vat_rate, p_quantity, nullif(btrim(p_note), ''),
    greatest(1, least(5, coalesce(p_course, 1))), auth.uid(), p_member_id
  )
  returning id into v_id;
  return v_id;
end;
$$;

drop function public.panel_close_order(uuid, text, uuid, integer);
create or replace function public.panel_close_order(
  p_order_id        uuid,
  p_payment_method  text,
  p_gift_card_id    uuid default null,
  p_gift_amount     integer default null,
  p_member_id       uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
  v_total  integer;
begin
  select * into v_order from orders where id = p_order_id for update;
  if not found then
    raise exception 'Nie znaleziono rachunku.';
  end if;
  perform private.require_permission(v_order.restaurant_id, 'orders');
  perform private.check_member(v_order.restaurant_id, p_member_id);
  if v_order.status <> 'open' then
    raise exception 'Ten rachunek jest już zamknięty.';
  end if;
  if p_payment_method not in ('cash', 'card', 'gift_card', 'other') then
    raise exception 'Wybierz formę płatności.';
  end if;

  select coalesce(sum(unit_price_grosze * quantity), 0) into v_total
  from order_items where order_id = p_order_id and status <> 'cancelled';
  if v_total = 0 then
    raise exception 'Rachunek jest pusty. Anuluj go zamiast zamykać.';
  end if;

  if p_gift_card_id is not null then
    if not exists (
      select 1 from gift_cards where id = p_gift_card_id and restaurant_id = v_order.restaurant_id
    ) then
      raise exception 'Ta karta podarunkowa jest z innego lokalu.';
    end if;
    if p_gift_amount is null or p_gift_amount <= 0 or p_gift_amount > v_total then
      raise exception 'Kwota z karty musi być większa od zera i nie większa niż rachunek.';
    end if;
    if p_gift_amount < v_total and p_payment_method = 'gift_card' then
      raise exception 'Karta nie pokrywa całego rachunku. Wybierz, jak gość dopłaci resztę.';
    end if;
    perform panel_redeem_gift_card(p_gift_card_id, p_gift_amount);
  elsif p_payment_method = 'gift_card' then
    raise exception 'Wpisz kod karty podarunkowej.';
  end if;

  update order_items set status = 'served' where order_id = p_order_id and status in ('new', 'sent', 'ready');
  update orders
  set status = 'paid',
      payment_method = p_payment_method,
      gift_card_id = p_gift_card_id,
      gift_card_grosze = case when p_gift_card_id is null then null else p_gift_amount end,
      closed_at = now(),
      closed_by = auth.uid(),
      closed_by_member = p_member_id
  where id = p_order_id;

  if v_order.reservation_id is not null then
    update reservations set status = 'completed', updated_at = now()
    where id = v_order.reservation_id and status = 'seated';
    if found then
      update table_holds
      set slot = tstzrange(lower(slot), greatest(lower(slot), now()) + interval '1 second'),
          active = false
      where reservation_id = v_order.reservation_id;
    end if;
  end if;
end;
$$;

-- ---------------------------------------------------------------
-- 5. Statystyki sprzedaży
-- ---------------------------------------------------------------

-- Sprzedaż z ostatnich p_days dni (dzień według strefy lokalu) i porównanie z okresem wcześniej.
create or replace function public.panel_sales_stats(p_restaurant_id uuid, p_days integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz     text;
  v_days   integer := greatest(1, least(coalesce(p_days, 30), 366));
  v_start  timestamptz;
  v_prev   timestamptz;
begin
  if not (
    private.has_permission(p_restaurant_id, 'stats')
    or private.has_permission(p_restaurant_id, 'orders')
  ) then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;

  select timezone into v_tz from restaurants where id = p_restaurant_id;
  v_tz := coalesce(v_tz, 'Europe/Warsaw');
  v_start := (date_trunc('day', now() at time zone v_tz) - make_interval(days => v_days - 1)) at time zone v_tz;
  v_prev := v_start - make_interval(days => v_days);

  return (
    with paid as (
      select o.*,
             (select coalesce(sum(i.unit_price_grosze * i.quantity), 0)
              from order_items i where i.order_id = o.id and i.status <> 'cancelled') as total
      from orders o
      where o.restaurant_id = p_restaurant_id and o.status = 'paid' and o.closed_at >= v_prev
    ),
    cur as (select * from paid where closed_at >= v_start),
    prev as (select * from paid where closed_at < v_start),
    items as (
      select i.* from order_items i
      join cur o on o.id = i.order_id
      where i.status <> 'cancelled'
    ),
    days as (
      select d::date as day
      from generate_series((v_start at time zone v_tz)::date, (now() at time zone v_tz)::date, interval '1 day') d
    )
    select jsonb_build_object(
      'revenue', coalesce((select sum(total) from cur), 0),
      'orders', (select count(*) from cur),
      'items', coalesce((select sum(quantity) from items), 0),
      'gift_cards', coalesce((select sum(gift_card_grosze) from cur), 0),
      'cancelled', (select count(*) from orders o where o.restaurant_id = p_restaurant_id
                    and o.status = 'cancelled' and o.closed_at >= v_start),
      'avg_table_minutes', (select round(avg(extract(epoch from closed_at - opened_at)) / 60) from cur),
      'prev_revenue', coalesce((select sum(total) from prev), 0),
      'prev_orders', (select count(*) from prev),
      'daily', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'day', d.day,
          'revenue', coalesce((select sum(c.total) from cur c where (c.closed_at at time zone v_tz)::date = d.day), 0),
          'orders', (select count(*) from cur c where (c.closed_at at time zone v_tz)::date = d.day)
        ) order by d.day), '[]'::jsonb)
        from days d
      ),
      'hourly', (
        select coalesce(jsonb_agg(jsonb_build_object('hour', h, 'revenue', coalesce(x.revenue, 0), 'orders', coalesce(x.orders, 0)) order by h), '[]'::jsonb)
        from generate_series(0, 23) h
        left join (
          select extract(hour from c.opened_at at time zone v_tz)::integer as hour,
                 sum(c.total) as revenue, count(*) as orders
          from cur c group by 1
        ) x on x.hour = h
      ),
      'weekdays', (
        select coalesce(jsonb_agg(jsonb_build_object('weekday', w, 'revenue', coalesce(x.revenue, 0), 'orders', coalesce(x.orders, 0)) order by w), '[]'::jsonb)
        from generate_series(1, 7) w
        left join (
          select extract(isodow from c.closed_at at time zone v_tz)::integer as weekday,
                 sum(c.total) as revenue, count(*) as orders
          from cur c group by 1
        ) x on x.weekday = w
      ),
      'top_items', (
        select coalesce(jsonb_agg(t order by t.quantity desc, t.revenue desc), '[]'::jsonb)
        from (
          select name, sum(quantity)::integer as quantity, sum(unit_price_grosze * quantity)::integer as revenue
          from items group by name order by sum(quantity) desc, sum(unit_price_grosze * quantity) desc limit 10
        ) t
      ),
      'payments', (
        select coalesce(jsonb_agg(p), '[]'::jsonb)
        from (
          select method, sum(amount)::integer as amount, count(*)::integer as orders from (
            select payment_method as method, total - coalesce(gift_card_grosze, 0) as amount
            from cur where payment_method <> 'gift_card'
            union all
            select 'gift_card', coalesce(gift_card_grosze, total) from cur
            where gift_card_grosze is not null or payment_method = 'gift_card'
          ) a
          group by method order by sum(amount) desc
        ) p
      ),
      'vat', (
        select coalesce(jsonb_agg(v order by v.rate desc), '[]'::jsonb)
        from (
          select vat_rate as rate, sum(unit_price_grosze * quantity)::integer as gross
          from items group by vat_rate
        ) v
      ),
      'staff', (
        select coalesce(jsonb_agg(s order by s.revenue desc), '[]'::jsonb)
        from (
          select coalesce(m.name, 'Bez przypisania') as name, sum(c.total)::integer as revenue,
                 count(*)::integer as orders
          from cur c
          left join staff_members m on m.id = c.opened_by_member
          group by m.name
        ) s
      ),
      'kitchen_seconds', (
        select round(avg(extract(epoch from done - sent)))
        from (
          select i.sent_at as sent, max(i.ready_at) as done
          from order_items i
          where i.restaurant_id = p_restaurant_id and i.sent_at >= v_start and i.ready_at is not null
          group by i.order_id, i.sent_at
        ) k
      )
    )
  );
end;
$$;

revoke execute on function public.panel_new_login_token(uuid) from public, anon;
revoke execute on function public.panel_login_token_status(text) from public, anon;
revoke execute on function public.staff_scan(text) from public, anon;
revoke execute on function public.staff_my_jobs() from public, anon;
revoke execute on function public.staff_my_shifts(integer) from public, anon;
revoke execute on function public.staff_end_shift(uuid) from public, anon;
revoke execute on function public.panel_save_shift(uuid, uuid, timestamptz, timestamptz) from public, anon;
revoke execute on function public.panel_delete_shift(uuid) from public, anon;
revoke execute on function public.panel_open_order(uuid, uuid, uuid) from public, anon;
revoke execute on function public.panel_add_order_item(uuid, uuid, text, text[], integer, text, integer, uuid) from public, anon;
revoke execute on function public.panel_close_order(uuid, text, uuid, integer, uuid) from public, anon;
revoke execute on function public.panel_sales_stats(uuid, integer) from public, anon;

grant execute on function public.panel_new_login_token(uuid) to authenticated;
grant execute on function public.panel_login_token_status(text) to authenticated;
grant execute on function public.staff_scan(text) to authenticated;
grant execute on function public.staff_my_jobs() to authenticated;
grant execute on function public.staff_my_shifts(integer) to authenticated;
grant execute on function public.staff_end_shift(uuid) to authenticated;
grant execute on function public.panel_save_shift(uuid, uuid, timestamptz, timestamptz) to authenticated;
grant execute on function public.panel_delete_shift(uuid) to authenticated;
grant execute on function public.panel_open_order(uuid, uuid, uuid) to authenticated;
grant execute on function public.panel_add_order_item(uuid, uuid, text, text[], integer, text, integer, uuid) to authenticated;
grant execute on function public.panel_close_order(uuid, text, uuid, integer, uuid) to authenticated;
grant execute on function public.panel_sales_stats(uuid, integer) to authenticated;
