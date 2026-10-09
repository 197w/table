-- Mapa dostawców. Lokal może wymagać lokalizacji dostawców przez całą zmianę („Ustawienia lokalu” →
-- „Dostawa i odbiór”). Wtedy telefon dostawcy wysyła pozycję od początku do końca zmiany, a dostawca
-- bez świeżej pozycji (ostatnie 3 minuty) nie dostaje kursów. Panel pokazuje na mapie dostawców,
-- cele dostaw i trasy; kafelki mapy, adresy i trasy daje funkcja Edge „maps” (Google, a bez klucza
-- tymczasowo OpenStreetMap).

alter table public.restaurants
  add column courier_tracking boolean not null default false;
grant select (courier_tracking) on public.restaurants to authenticated;

-- Pozycja dostawcy na zmianie (jedna na pracownika). Czyta ją tylko panel przez panel_courier_map.
create table public.staff_locations (
  member_id      uuid primary key references public.staff_members (id) on delete cascade,
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  lat            double precision not null check (lat between -90 and 90),
  lng            double precision not null check (lng between -180 and 180),
  accuracy       real,
  heading        real,
  speed          real,
  updated_at     timestamptz not null default now()
);
alter table public.staff_locations enable row level security;

-- Cel dostawy na mapie: współrzędne adresu (szuka ich funkcja Edge „maps” przy pierwszym pokazaniu).
-- delivery_geo: google albo osm (skąd współrzędne), none (adresu nie znaleziono), null (jeszcze nie szukano).
alter table public.orders
  add column delivery_lat double precision check (delivery_lat between -90 and 90),
  add column delivery_lng double precision check (delivery_lng between -180 and 180),
  add column delivery_geo text check (delivery_geo in ('google', 'osm', 'none'));

-- Krótka pamięć tras: kilka komputerów z panelem korzysta z jednej trasy, a Google liczy ją
-- najwyżej co kilka minut na kurs. Wiersze znikają po kursie i po godzinie.
create table public.courier_routes (
  member_id      uuid not null references public.staff_members (id) on delete cascade,
  order_id       uuid not null references public.orders (id) on delete cascade,
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  polyline       text not null,
  duration_s     integer,
  distance_m     integer,
  origin_lat     double precision,
  origin_lng     double precision,
  provider       text not null,
  computed_at    timestamptz not null default now(),
  primary key (member_id, order_id)
);
alter table public.courier_routes enable row level security;

-- ---------------------------------------------------------------
-- Kolejka: dostawca bez świeżej pozycji nie dostaje kursów
-- ---------------------------------------------------------------

-- Świeża pozycja: z ostatnich 3 minut.
create or replace function private.located(p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.staff_locations
    where member_id = p_member_id and updated_at > now() - interval '3 minutes'
  )
$$;

drop function if exists private.courier_queue(uuid);
create function private.courier_queue(p_restaurant_id uuid)
returns table (member_id uuid, name text, waiting_since timestamptz, busy boolean, located boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select m.id,
         m.name,
         greatest(s.started_at, coalesce(m.courier_ready_at, s.started_at)),
         exists (
           select 1 from public.orders o
           where o.courier_member = m.id and o.fulfillment in ('accepted', 'ready', 'on_the_way')
         ),
         -- Lokal bez wymogu lokalizacji: każdy dostawca na zmianie może dostać kurs.
         not r.courier_tracking or private.located(m.id)
  from public.staff_members m
  join public.restaurants r on r.id = m.restaurant_id
  join public.staff_shifts s on s.member_id = m.id and s.ended_at is null
  where m.restaurant_id = p_restaurant_id
    and m.active
    and private.is_courier(m.id)
  order by 4, 5 desc, 3, s.started_at
$$;

create or replace function private.dispatch_deliveries(p_restaurant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order    public.orders%rowtype;
  v_courier  uuid;
begin
  perform pg_advisory_xact_lock(hashtext('dispatch:' || p_restaurant_id::text));
  for v_order in
    select o.* from public.orders o
    where o.restaurant_id = p_restaurant_id
      and o.kind = 'delivery'
      and o.courier_member is null
      and o.kitchen_at is null
      and o.fulfillment in ('accepted', 'ready')
    order by o.accepted_at nulls last, o.opened_at
  loop
    -- Zamówienie z kursu mogło już dostać dostawcę razem z innym z tego kursu.
    continue when exists (select 1 from public.orders x where x.id = v_order.id and x.courier_member is not null);
    -- Kurs dostaje wolny dostawca, którego widać na mapie (gdy lokal tego wymaga).
    select q.member_id into v_courier from private.courier_queue(p_restaurant_id) q
    where not q.busy and q.located limit 1;
    exit when v_courier is null;
    update public.orders set courier_member = v_courier, courier_assigned_at = now()
    where courier_member is null
      and (id = v_order.id or id in (select private.course_waiting(v_order.course_id)));
  end loop;
end;
$$;

create or replace function public.panel_couriers(p_restaurant_id uuid)
returns table (member_id uuid, name text, waiting_since timestamptz, busy boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform private.require_permission(p_restaurant_id, 'orders');
  return query select q.member_id, q.name, q.waiting_since, q.busy from private.courier_queue(p_restaurant_id) q;
end;
$$;

-- ---------------------------------------------------------------
-- Telefon dostawcy
-- ---------------------------------------------------------------

-- Lokale pracownika: do tego, co było, dochodzi wymóg lokalizacji i to, czy rozwozi zamówienia.
drop function if exists public.staff_my_jobs();
create function public.staff_my_jobs()
returns table (
  member_id uuid, restaurant_id uuid, restaurant_name text, member_name text, position_name text,
  permissions text[], shift_id uuid, shift_started_at timestamptz, week_seconds bigint, schedule_period text,
  courier_tracking boolean, is_courier boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select m.id, r.id, r.name, m.name, p.name, private.member_permissions(m.id),
         s.id, s.started_at,
         (select coalesce(sum(extract(epoch from coalesce(x.ended_at, now()) - x.started_at)), 0)::bigint
          from staff_shifts x
          where x.member_id = m.id and x.started_at >= date_trunc('week', now())),
         r.schedule_period,
         r.courier_tracking,
         private.is_courier(m.id)
  from private.my_members() m
  join restaurants r on r.id = m.restaurant_id
  left join staff_positions p on p.id = m.position_id
  left join staff_shifts s on s.member_id = m.id and s.ended_at is null
  order by r.name
$$;

-- Pozycja dostawcy na zmianie, co kilkanaście sekund. Ta sama pozycja trafia do gości, których
-- zamówienia są w drodze (mapa w szczegółach zamówienia). Po odzyskaniu lokalizacji dostawca
-- wraca do kolejki od razu.
create or replace function public.staff_share_location(
  p_member_id  uuid,
  p_lat        double precision,
  p_lng        double precision,
  p_accuracy   real default null,
  p_heading    real default null,
  p_speed      real default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member staff_members%rowtype;
  v_was    boolean;
begin
  v_member := private.my_member(p_member_id);
  if not exists (select 1 from staff_shifts where member_id = p_member_id and ended_at is null) then
    delete from staff_locations where member_id = p_member_id;
    return;
  end if;
  v_was := private.located(p_member_id);
  insert into staff_locations (member_id, restaurant_id, lat, lng, accuracy, heading, speed, updated_at)
  values (p_member_id, v_member.restaurant_id, p_lat, p_lng, p_accuracy, p_heading, p_speed, now())
  on conflict (member_id) do update
    set restaurant_id = excluded.restaurant_id, lat = excluded.lat, lng = excluded.lng,
        accuracy = excluded.accuracy, heading = excluded.heading, speed = excluded.speed, updated_at = now();
  insert into courier_positions (order_id, restaurant_id, member_id, lat, lng, accuracy, updated_at)
  select o.id, o.restaurant_id, p_member_id, p_lat, p_lng, p_accuracy, now()
  from orders o
  where o.courier_member = p_member_id and o.fulfillment = 'on_the_way'
  on conflict (order_id) do update
    set lat = excluded.lat, lng = excluded.lng, accuracy = excluded.accuracy,
        member_id = excluded.member_id, updated_at = now();
  if not v_was then
    perform private.dispatch_deliveries(v_member.restaurant_id);
  end if;
end;
$$;

-- Telefon nie może podać pozycji (brak zgody, wyłączony GPS): dostawca od razu wypada z kolejki.
create or replace function public.staff_stop_location(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.my_member(p_member_id);
  delete from staff_locations where member_id = p_member_id;
end;
$$;

-- Tablica dostawcy: wymóg lokalizacji, czy mnie widać i kto w kolejce jest widoczny.
create or replace function public.staff_deliveries(p_member_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_member  staff_members%rowtype;
  v_r       restaurants%rowtype;
  v_since   timestamptz;
begin
  v_member := private.my_member(p_member_id);
  select * into v_r from restaurants where id = v_member.restaurant_id;
  v_since := date_trunc('day', now() at time zone v_r.timezone) at time zone v_r.timezone;
  return jsonb_build_object(
    'restaurant_name', v_r.name,
    'restaurant_address', v_r.address || ', ' || v_r.city,
    'on_shift', exists (select 1 from staff_shifts where member_id = p_member_id and ended_at is null),
    'is_courier', private.is_courier(p_member_id),
    'tracking', v_r.courier_tracking,
    'located', private.located(p_member_id),
    'queue', coalesce((
      select jsonb_agg(jsonb_build_object(
        'member_id', q.member_id, 'name', q.name, 'busy', q.busy, 'since', q.waiting_since, 'located', q.located
      ))
      from private.courier_queue(v_member.restaurant_id) q
    ), '[]'::jsonb),
    'waiting', (
      select count(*) from orders
      where restaurant_id = v_member.restaurant_id and kind = 'delivery' and courier_member is null
        and kitchen_at is null and fulfillment in ('accepted', 'ready')
    ),
    'courses', coalesce((
      select jsonb_agg(private.course_json(o) order by o.courier_assigned_at)
      from orders o
      where o.courier_member = p_member_id and o.fulfillment in ('accepted', 'ready', 'on_the_way')
    ), '[]'::jsonb),
    'today_count', (
      select count(*) from orders
      where courier_member = p_member_id and fulfillment = 'delivered' and delivered_at >= v_since
    ),
    'today_cash_grosze', coalesce((
      select sum((private.course_json(o) ->> 'total_grosze')::integer) from orders o
      where o.courier_member = p_member_id and o.fulfillment = 'delivered' and o.delivered_at >= v_since
        and o.payment_choice = 'cash'
    ), 0)
  );
end;
$$;

-- Koniec zmiany: pozycja i trasy dostawcy znikają.
create or replace function private.shift_location_cleanup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.staff_locations where member_id = new.member_id;
  delete from public.courier_routes where member_id = new.member_id;
  return new;
end;
$$;
create trigger staff_shifts_location_cleanup
  after update of ended_at on public.staff_shifts
  for each row when (old.ended_at is null and new.ended_at is not null)
  execute function private.shift_location_cleanup();

-- Kurs zakończony albo zmieniony: trasa do niego jest już zbędna.
create or replace function private.order_route_cleanup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.courier_routes
  where order_id = new.id and (new.fulfillment <> 'on_the_way' or new.courier_member is distinct from member_id);
  return new;
end;
$$;
create trigger orders_route_cleanup
  after update of fulfillment, courier_member on public.orders
  for each row when (old.fulfillment = 'on_the_way')
  execute function private.order_route_cleanup();

-- Zmiana adresu dostawy: współrzędne trzeba znaleźć od nowa.
create or replace function private.order_geo_reset()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.delivery_lat := null;
  new.delivery_lng := null;
  new.delivery_geo := null;
  return new;
end;
$$;
create trigger orders_geo_reset
  before update of delivery_address, address_street, address_house, address_city on public.orders
  for each row
  when (old.delivery_address is distinct from new.delivery_address
        or old.address_street is distinct from new.address_street
        or old.address_house is distinct from new.address_house
        or old.address_city is distinct from new.address_city)
  execute function private.order_geo_reset();

-- ---------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------

create or replace function public.panel_set_courier_tracking(p_restaurant_id uuid, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.require_permission(p_restaurant_id, 'profile');
  update restaurants set courier_tracking = coalesce(p_enabled, false) where id = p_restaurant_id;
  -- Po wyłączeniu wymogu dostawcy bez lokalizacji wracają do kolejki.
  perform private.dispatch_deliveries(p_restaurant_id);
end;
$$;

-- Wszystko dla mapy: lokal, dostawcy na zmianie z pozycją, dostawy w toku z celami i świeże trasy.
create or replace function public.panel_courier_map(p_restaurant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_r restaurants%rowtype;
begin
  perform private.require_permission(p_restaurant_id, 'orders');
  select * into v_r from restaurants where id = p_restaurant_id;
  return jsonb_build_object(
    'tracking', v_r.courier_tracking,
    'restaurant', jsonb_build_object(
      'name', v_r.name,
      'address', v_r.address || ', ' || v_r.city,
      'lat', st_y(v_r.location::geometry),
      'lng', st_x(v_r.location::geometry)
    ),
    'couriers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'member_id', q.member_id,
        'name', q.name,
        'busy', q.busy,
        'located', q.located,
        'since', q.waiting_since,
        'color', m.color,
        'vehicle', (select v.kind from vehicles v where v.member_id = q.member_id and v.active order by v.created_at limit 1),
        'lat', l.lat,
        'lng', l.lng,
        'accuracy', l.accuracy,
        'heading', l.heading,
        'speed', l.speed,
        'updated_at', l.updated_at
      ))
      from private.courier_queue(p_restaurant_id) q
      join staff_members m on m.id = q.member_id
      left join staff_locations l on l.member_id = q.member_id
    ), '[]'::jsonb),
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id,
        'number', o.number,
        'fulfillment', o.fulfillment,
        'courier_member', o.courier_member,
        'course_id', o.course_id,
        'address', o.delivery_address,
        'customer_name', o.customer_name,
        'lat', o.delivery_lat,
        'lng', o.delivery_lng,
        'geo', o.delivery_geo,
        'promised_at', o.promised_at,
        'scheduled_for', o.scheduled_for,
        'kitchen_at', o.kitchen_at,
        'picked_up_at', o.picked_up_at
      ) order by o.promised_at nulls last, o.number)
      from orders o
      where o.restaurant_id = p_restaurant_id
        and o.kind = 'delivery'
        and o.fulfillment in ('accepted', 'ready', 'on_the_way')
    ), '[]'::jsonb),
    'routes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'member_id', c.member_id,
        'order_id', c.order_id,
        'polyline', c.polyline,
        'duration_s', c.duration_s,
        'distance_m', c.distance_m,
        'provider', c.provider,
        'computed_at', c.computed_at
      ))
      from courier_routes c
      where c.restaurant_id = p_restaurant_id and c.computed_at > now() - interval '15 minutes'
    ), '[]'::jsonb)
  );
end;
$$;

-- Dla funkcji Edge „maps” (wywoływanej z tokenem pracownika panelu): sprawdza uprawnienie
-- i podaje adres zamówienia do znalezienia na mapie.
create or replace function public.panel_geocode_input(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_o orders%rowtype;
  v_r restaurants%rowtype;
begin
  select * into v_o from orders where id = p_order_id;
  if not found then
    raise exception 'Nie ma takiego zamówienia.';
  end if;
  perform private.require_permission(v_o.restaurant_id, 'orders');
  select * into v_r from restaurants where id = v_o.restaurant_id;
  return jsonb_build_object(
    'order_id', v_o.id,
    'restaurant_id', v_o.restaurant_id,
    'address', v_o.delivery_address,
    'street', v_o.address_street,
    'house', v_o.address_house,
    'city', coalesce(v_o.address_city, v_r.city),
    'restaurant_lat', st_y(v_r.location::geometry),
    'restaurant_lng', st_x(v_r.location::geometry),
    'lat', v_o.delivery_lat,
    'lng', v_o.delivery_lng,
    'geo', v_o.delivery_geo
  );
end;
$$;

-- Dla funkcji Edge „maps”: początek (pozycja dostawcy), cel i trasa z pamięci, jeśli jest świeża.
create or replace function public.panel_route_input(p_member_id uuid, p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_o orders%rowtype;
  v_l staff_locations%rowtype;
  v_c courier_routes%rowtype;
begin
  select * into v_o from orders where id = p_order_id;
  if not found then
    raise exception 'Nie ma takiego zamówienia.';
  end if;
  perform private.require_permission(v_o.restaurant_id, 'orders');
  select * into v_l from staff_locations where member_id = p_member_id and restaurant_id = v_o.restaurant_id;
  select * into v_c from courier_routes where member_id = p_member_id and order_id = p_order_id;
  return jsonb_build_object(
    'restaurant_id', v_o.restaurant_id,
    'active', v_o.courier_member = p_member_id and v_o.fulfillment = 'on_the_way',
    'origin_lat', v_l.lat,
    'origin_lng', v_l.lng,
    'dest_lat', v_o.delivery_lat,
    'dest_lng', v_o.delivery_lng,
    'cached', case when v_c.member_id is null then null else jsonb_build_object(
      'polyline', v_c.polyline,
      'duration_s', v_c.duration_s,
      'distance_m', v_c.distance_m,
      'provider', v_c.provider,
      'computed_at', v_c.computed_at,
      'origin_lat', v_c.origin_lat,
      'origin_lng', v_c.origin_lng
    ) end
  );
end;
$$;

-- Sprzątanie co kwadrans: stare trasy i pozycje z telefonów, które zgasły bez końca zmiany.
create or replace function private.courier_map_cleanup()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.courier_routes where computed_at < now() - interval '1 hour';
  delete from public.staff_locations where updated_at < now() - interval '12 hours';
$$;
select cron.schedule('table_courier_map_cleanup', '*/15 * * * *', 'select private.courier_map_cleanup()');

-- ---------------------------------------------------------------
-- Uprawnienia
-- ---------------------------------------------------------------

revoke execute on function private.located(uuid) from public, anon, authenticated;
revoke execute on function private.courier_queue(uuid) from public, anon, authenticated;
revoke execute on function private.shift_location_cleanup() from public, anon, authenticated;
revoke execute on function private.order_route_cleanup() from public, anon, authenticated;
revoke execute on function private.order_geo_reset() from public, anon, authenticated;
revoke execute on function private.courier_map_cleanup() from public, anon, authenticated;

revoke execute on function public.staff_my_jobs() from public, anon;
revoke execute on function public.staff_share_location(uuid, double precision, double precision, real, real, real) from public, anon;
revoke execute on function public.staff_stop_location(uuid) from public, anon;
revoke execute on function public.panel_set_courier_tracking(uuid, boolean) from public, anon;
revoke execute on function public.panel_courier_map(uuid) from public, anon;
revoke execute on function public.panel_geocode_input(uuid) from public, anon;
revoke execute on function public.panel_route_input(uuid, uuid) from public, anon;

grant execute on function public.staff_my_jobs() to authenticated;
grant execute on function public.staff_share_location(uuid, double precision, double precision, real, real, real) to authenticated;
grant execute on function public.staff_stop_location(uuid) to authenticated;
grant execute on function public.panel_set_courier_tracking(uuid, boolean) to authenticated;
grant execute on function public.panel_courier_map(uuid) to authenticated;
grant execute on function public.panel_geocode_input(uuid) to authenticated;
grant execute on function public.panel_route_input(uuid, uuid) to authenticated;
