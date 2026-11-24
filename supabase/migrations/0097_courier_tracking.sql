-- Pozycja dostawców i historia tras (24.11.2026, prośba użytkownika: „dodaj wymuszoną lokalizację w aplikacji dla
-- pracowników (jeśli posiada stanowisko Dostawca), dodaj do tego historię tras, które wykonał dany kierowca … żeby
-- sprawdzić np. czy dany kierowca nie pojechał naokoło”).
--
-- Table for employees wysyła pozycję dostawcy (stanowisko z uprawnieniem „deliveries”, `private.is_courier`) tylko
-- w czasie jego zmiany, paczkami (telefon zbiera punkty także bez internetu). Ostatnia pozycja trafia do
-- `staff_locations` (mapa dostawców w panelu, 0087), każdy punkt do `courier_track_points` (historia tras). Punkty
-- starsze niż 30 dni baza kasuje przy kolejnym zapisie tego dostawcy. Poza zmianą i bez stanowiska dostawcy baza nic
-- nie zapisuje.

create table if not exists public.courier_track_points (
  id             bigint generated always as identity primary key,
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  member_id      uuid not null references public.staff_members (id) on delete cascade,
  at             timestamptz not null,
  lat            double precision not null check (lat between -90 and 90),
  lng            double precision not null check (lng between -180 and 180),
  accuracy       real,
  speed          real,
  heading        real
);

create index if not exists courier_track_points_member_at on public.courier_track_points (member_id, at);
create index if not exists courier_track_points_restaurant_at on public.courier_track_points (restaurant_id, at);

alter table public.courier_track_points enable row level security;
revoke all on public.courier_track_points from anon, authenticated;

-- Punkty z telefonu: lista {lat, lng, at, accuracy, speed, heading} (najwyżej 500 naraz). Zwraca, ile zapisano.
-- Punkty niedokładne (dokładność gorsza niż 150 m), z przyszłości albo starsze niż 12 godzin są pomijane.
create or replace function public.staff_share_locations(p_member_id uuid, p_points jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member  staff_members%rowtype;
  v_count   integer := 0;
  v_last    record;
begin
  v_member := private.my_member(p_member_id);
  if not private.is_courier(p_member_id) then
    return 0;
  end if;
  if not exists (select 1 from staff_shifts where member_id = p_member_id and ended_at is null) then
    return 0;
  end if;
  if p_points is null or jsonb_typeof(p_points) <> 'array' then
    return 0;
  end if;

  with raw as (
    select (p ->> 'lat')::double precision as lat,
           (p ->> 'lng')::double precision as lng,
           coalesce((p ->> 'at')::timestamptz, now()) as at,
           nullif(p ->> 'accuracy', '')::real as accuracy,
           nullif(p ->> 'speed', '')::real as speed,
           nullif(p ->> 'heading', '')::real as heading
    from (select * from jsonb_array_elements(p_points) limit 500) x(p)
  ),
  ok as (
    select * from raw
    where lat between -90 and 90 and lng between -180 and 180
      and at between now() - interval '12 hours' and now() + interval '5 minutes'
      and (accuracy is null or accuracy <= 150)
  ),
  ins as (
    insert into courier_track_points (restaurant_id, member_id, at, lat, lng, accuracy, speed, heading)
    select v_member.restaurant_id, p_member_id, at, lat, lng, accuracy, speed, heading from ok
    returning at, lat, lng, accuracy, speed, heading
  )
  select count(*)::integer into v_count from ins;

  -- Najnowszy punkt jako bieżąca pozycja (mapa dostawców w panelu).
  select * into v_last from courier_track_points
  where member_id = p_member_id order by at desc limit 1;
  if found then
    insert into staff_locations (member_id, restaurant_id, lat, lng, accuracy, heading, speed, updated_at)
    values (p_member_id, v_member.restaurant_id, v_last.lat, v_last.lng, v_last.accuracy, v_last.heading, v_last.speed,
            v_last.at)
    on conflict (member_id) do update
    set restaurant_id = excluded.restaurant_id, lat = excluded.lat, lng = excluded.lng, accuracy = excluded.accuracy,
        heading = excluded.heading, speed = excluded.speed, updated_at = excluded.updated_at
    where staff_locations.updated_at is null or excluded.updated_at >= staff_locations.updated_at;
  end if;

  delete from courier_track_points where member_id = p_member_id and at < now() - interval '30 days';
  return v_count;
end;
$$;

-- Starsza nazwa z aplikacji (jeden punkt): zapis jak paczka z jednym punktem.
create or replace function public.staff_share_location(
  p_member_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_accuracy real default null,
  p_heading real default null,
  p_speed real default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.staff_share_locations(
    p_member_id,
    jsonb_build_array(jsonb_build_object(
      'lat', p_lat, 'lng', p_lng, 'at', now(), 'accuracy', p_accuracy, 'heading', p_heading, 'speed', p_speed
    ))
  );
end;
$$;

-- Dostawcy z trasą albo dostawami w dniu lokalu [p_day]: do wyboru w historii tras. Uprawnienie „orders” (jak mapa
-- dostawców) albo „fleet”.
create or replace function public.panel_courier_days(p_restaurant_id uuid, p_day date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_range record;
begin
  if not (private.has_permission(p_restaurant_id, 'orders') or private.has_permission(p_restaurant_id, 'fleet')) then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;
  select * into v_range from private.day_range(p_restaurant_id, p_day);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'member_id', m.id, 'name', m.name, 'color', m.color,
      'points', (select count(*) from courier_track_points t
                 where t.member_id = m.id and t.at >= v_range.starts and t.at < v_range.ends),
      'deliveries', (select count(*) from orders o
                     where o.courier_member = m.id and o.kind = 'delivery' and o.status <> 'cancelled'
                       and coalesce(o.picked_up_at, o.opened_at) >= v_range.starts
                       and coalesce(o.picked_up_at, o.opened_at) < v_range.ends)
    ) order by m.name)
    from staff_members m
    where m.restaurant_id = p_restaurant_id
      and (exists (select 1 from courier_track_points t
                   where t.member_id = m.id and t.at >= v_range.starts and t.at < v_range.ends)
           or exists (select 1 from orders o
                      where o.courier_member = m.id and o.kind = 'delivery' and o.status <> 'cancelled'
                        and coalesce(o.picked_up_at, o.opened_at) >= v_range.starts
                        and coalesce(o.picked_up_at, o.opened_at) < v_range.ends))
  ), '[]'::jsonb);
end;
$$;

-- Historia tras dostawcy w dniu lokalu: punkty z telefonu po kolei (najwyżej 20 000) i jego dostawy z czasami odbioru
-- i dowiezienia, żeby panel pokazał przejazd każdego kursu i porównał go z najkrótszą trasą.
create or replace function public.panel_courier_history(p_restaurant_id uuid, p_member_id uuid, p_day date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_range record;
begin
  if not (private.has_permission(p_restaurant_id, 'orders') or private.has_permission(p_restaurant_id, 'fleet')) then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;
  if not exists (select 1 from staff_members where id = p_member_id and restaurant_id = p_restaurant_id) then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  select * into v_range from private.day_range(p_restaurant_id, p_day);
  return jsonb_build_object(
    'points', coalesce((
      select jsonb_agg(jsonb_build_array(
        (extract(epoch from x.at) * 1000)::bigint, round(x.lat::numeric, 6), round(x.lng::numeric, 6), x.speed
      ) order by x.at)
      from (
        select at, lat, lng, speed from courier_track_points
        where member_id = p_member_id and at >= v_range.starts and at < v_range.ends
        order by at
        limit 20000
      ) x
    ), '[]'::jsonb),
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id, 'number', o.number, 'course_id', o.course_id, 'fulfillment', o.fulfillment,
        'address', o.delivery_address, 'customer', coalesce(o.customer_company, o.customer_name),
        'picked_up_at', o.picked_up_at, 'delivered_at', o.delivered_at, 'promised_at', o.promised_at,
        'opened_at', o.opened_at
      ) order by coalesce(o.picked_up_at, o.opened_at))
      from orders o
      where o.courier_member = p_member_id and o.restaurant_id = p_restaurant_id and o.kind = 'delivery'
        and o.status <> 'cancelled'
        and coalesce(o.picked_up_at, o.opened_at) >= v_range.starts
        and coalesce(o.picked_up_at, o.opened_at) < v_range.ends
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.staff_share_locations(uuid, jsonb) from public, anon;
revoke execute on function public.panel_courier_days(uuid, date) from public, anon;
revoke execute on function public.panel_courier_history(uuid, uuid, date) from public, anon;
grant execute on function public.staff_share_locations(uuid, jsonb) to authenticated;
grant execute on function public.panel_courier_days(uuid, date) to authenticated;
grant execute on function public.panel_courier_history(uuid, uuid, date) to authenticated;
