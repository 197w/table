-- Dostawca danego dnia (25.11.2026, prośba użytkownika: „jeśli dany pracownik danego dnia nie pracuje jako Dostawca,
-- nie musi wpisywać licznika i robić zdjęć”). Do tej pory dostawcą był każdy, kto ma stanowisko z uprawnieniem
-- „deliveries” (`private.is_courier`), także jako dodatkowe stanowisko albo w stanowisku kierownika lub właściciela
-- z zaznaczonymi wszystkimi uprawnieniami. Teraz dostawcą w danym dniu jest ten, kto:
--   • ma w Grafiku na ten dzień przyjęte godziny ze stanowiskiem z „deliveries” (stanowisko na dzień,
--     `staff_schedule.position_id`), a gdy w Grafiku na ten dzień jest inne stanowisko, nie jest dostawcą;
--   • bez stanowiska w Grafiku na ten dzień: jego główne stanowisko ma „deliveries” (bez stanowiska głównego:
--     dowolne stanowisko, jak dotąd).
-- Dzień to dzień rozpoczęcia trwającej zmiany w strefie lokalu (zmiana przez północ liczy się do dnia początku;
-- zmiana otwarta dłużej niż 20 godzin, czyli niezamknięta, liczy się do dzisiaj).
-- Na tym opiera się wszystko, co dotyczy dostawcy: kolejka kursów, kontrola auta (przebieg i zdjęcia), wymuszona
-- lokalizacja i wysyłanie pozycji, zakładka Dostawy w Table for employees.

create or replace function private.position_is_courier(p_position_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select p.system_key is distinct from 'all' and 'deliveries' = any (p.permissions)
    from public.staff_positions p where p.id = p_position_id
  ), false)
$$;

create or replace function private.courier_today(p_member_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_member   public.staff_members%rowtype;
  v_tz       text;
  v_day      date;
  v_planned  uuid;
begin
  if not private.is_courier(p_member_id) then
    return false;
  end if;
  select * into v_member from public.staff_members where id = p_member_id;
  select coalesce(timezone, 'Europe/Warsaw') into v_tz from public.restaurants where id = v_member.restaurant_id;
  v_day := (coalesce(
    (select s.started_at from public.staff_shifts s
     where s.member_id = p_member_id and s.ended_at is null and s.started_at > now() - interval '20 hours'
     order by s.started_at desc limit 1),
    now()
  ) at time zone v_tz)::date;
  select s.position_id into v_planned from public.staff_schedule s
  where s.member_id = p_member_id and s.day = v_day and s.status = 'accepted' and s.position_id is not null
  limit 1;
  if v_planned is not null then
    return private.position_is_courier(v_planned);
  end if;
  if v_member.position_id is null then
    return true;
  end if;
  return private.position_is_courier(v_member.position_id);
end;
$$;

revoke execute on function private.position_is_courier(uuid) from public, anon, authenticated;
revoke execute on function private.courier_today(uuid) from public, anon, authenticated;

-- Kolejka dostawców: tylko dostawcy tego dnia na zmianie.
create or replace function private.courier_queue(p_restaurant_id uuid)
returns table(member_id uuid, name text, waiting_since timestamp with time zone, busy boolean, located boolean)
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
         coalesce(private.vehicle_ready(m.id), true)
  from public.staff_members m
  join public.staff_shifts s on s.member_id = m.id and s.ended_at is null
  where m.restaurant_id = p_restaurant_id
    and m.active
    and private.courier_today(m.id)
  order by 4, 5 desc, 3, s.started_at
$$;

-- Lokale pracownika: „is_courier” to teraz dostawca tego dnia (wymuszona lokalizacja i wysyłanie pozycji w aplikacji).
create or replace function public.staff_my_jobs()
returns table(member_id uuid, restaurant_id uuid, restaurant_name text, member_name text, position_name text,
              permissions text[], shift_id uuid, shift_started_at timestamp with time zone, week_seconds bigint,
              schedule_period text, courier_tracking boolean, is_courier boolean)
language sql
stable
security definer
set search_path = 'public'
as $$
  select m.id, r.id, r.name, m.name, p.name, private.member_permissions(m.id),
         s.id, s.started_at,
         (select coalesce(sum(extract(epoch from coalesce(x.ended_at, now()) - x.started_at)), 0)::bigint
          from staff_shifts x
          where x.member_id = m.id and x.started_at >= date_trunc('week', now())),
         r.schedule_period,
         r.courier_tracking,
         private.courier_today(m.id)
  from private.my_members() m
  join restaurants r on r.id = m.restaurant_id
  left join staff_positions p on p.id = m.position_id
  left join staff_shifts s on s.member_id = m.id and s.ended_at is null
  order by r.name
$$;

-- Kontrola auta tylko dla dostawcy tego dnia.
create or replace function public.staff_vehicle_status(p_member_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public'
as $$
declare
  v_member  staff_members%rowtype;
  v_shift   staff_shifts%rowtype;
  v_tz      text;
  v_day     date;
  v_vehicle uuid;
begin
  v_member := private.my_member(p_member_id);
  select coalesce(timezone, 'Europe/Warsaw') into v_tz from restaurants where id = v_member.restaurant_id;
  v_day := (now() at time zone v_tz)::date;
  select * into v_shift from staff_shifts where member_id = p_member_id and ended_at is null
  order by started_at desc limit 1;
  select vehicle_id into v_vehicle from vehicle_days where member_id = p_member_id and day = v_day;
  return jsonb_build_object(
    'required', private.courier_today(p_member_id) and private.vehicle_check_required(v_member.restaurant_id),
    'on_shift', v_shift.id is not null,
    'vehicle_id', v_vehicle,
    'start', (select jsonb_build_object('vehicle_id', c.vehicle_id, 'odometer_km', c.odometer_km, 'at', c.created_at)
              from vehicle_checks c where c.shift_id = v_shift.id and c.kind = 'start'
              order by c.created_at desc limit 1),
    'end', (select jsonb_build_object('vehicle_id', c.vehicle_id, 'odometer_km', c.odometer_km, 'at', c.created_at)
            from vehicle_checks c where c.shift_id = v_shift.id and c.kind = 'end'
            order by c.created_at desc limit 1),
    'vehicles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'name', v.name, 'plate', v.plate, 'kind', v.kind,
        'last_km', (select c.odometer_km from vehicle_checks c
                    where c.vehicle_id = v.id and c.odometer_km is not null
                    order by c.created_at desc limit 1),
        'taken_by', (select m.name from vehicle_days d join staff_members m on m.id = d.member_id
                     where d.vehicle_id = v.id and d.day = v_day and d.member_id <> p_member_id)
      ) order by v.name)
      from vehicles v where v.restaurant_id = v_member.restaurant_id and v.active
    ), '[]'::jsonb)
  );
end;
$$;

-- Dostawy w aplikacji: „is_courier” to dostawca tego dnia.
create or replace function public.staff_deliveries(p_member_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public'
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
    'is_courier', private.courier_today(p_member_id),
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

-- Pozycja z telefonu tylko od dostawcy tego dnia (reszta jak w 0097).
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
  if not private.courier_today(p_member_id) then
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
