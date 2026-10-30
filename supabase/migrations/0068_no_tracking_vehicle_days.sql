-- 0068: bez map i śledzenia dostawców; auto przypisane dostawcy na dany dzień (Grafik, Dostawy) zamiast na stałe
-- we Flocie; przed pierwszym kursem i na koniec zmiany dostawca wpisuje przebieg i robi zdjęcia auta dookoła
-- (Table for employees), a panel pokazuje je we Flocie dzień po dniu.

-- ---------------------------------------------------------------
-- 1. Koniec map i śledzenia
-- ---------------------------------------------------------------

update public.restaurants set courier_tracking = false where courier_tracking;
delete from public.staff_locations;
delete from public.courier_positions;
delete from public.courier_routes;

-- Starsze wersje aplikacji jeszcze wysyłają pozycję: przyjmujemy i nic nie zapisujemy.
create or replace function public.staff_share_location(
  p_member_id uuid, p_lat double precision, p_lng double precision, p_accuracy real default null,
  p_heading real default null, p_speed real default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  return;
end;
$$;

create or replace function public.staff_courier_position(
  p_order_id uuid, p_member_id uuid, p_lat double precision, p_lng double precision, p_accuracy real default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  return;
end;
$$;

create or replace function public.guest_courier_position(p_order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select null::jsonb
$$;

drop function if exists public.panel_set_courier_tracking(uuid, boolean);
drop function if exists public.panel_courier_map(uuid);
drop function if exists public.panel_geocode_input(uuid);
drop function if exists public.panel_route_input(uuid, uuid);

-- ---------------------------------------------------------------
-- 2. Auto na dzień
-- ---------------------------------------------------------------

-- Przypisanie na stałe we Flocie znika (auto dostaje dostawca na dany dzień).
update public.vehicles set member_id = null where member_id is not null;

create table if not exists public.vehicle_days (
  restaurant_id     uuid not null references public.restaurants (id) on delete cascade,
  day               date not null,
  vehicle_id        uuid not null references public.vehicles (id) on delete cascade,
  member_id         uuid not null references public.staff_members (id) on delete cascade,
  assigned_by_name  text,
  updated_at        timestamptz not null default now(),
  primary key (vehicle_id, day),
  unique (member_id, day)
);
create index if not exists vehicle_days_restaurant on public.vehicle_days (restaurant_id, day);
alter table public.vehicle_days enable row level security;

-- Auta dostawców w dniach [p_from, p_to].
create or replace function public.panel_vehicle_days(p_restaurant_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (private.has_permission(p_restaurant_id, 'fleet') or private.has_permission(p_restaurant_id, 'schedule')
          or private.has_permission(p_restaurant_id, 'orders')) then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('day', d.day, 'vehicle_id', d.vehicle_id, 'member_id', d.member_id)
                     order by d.day)
    from vehicle_days d
    where d.restaurant_id = p_restaurant_id and d.day between p_from and p_to
  ), '[]'::jsonb);
end;
$$;

-- Auto dostawcy na dzień (z Grafiku albo Dostaw). [p_vehicle_id] null: bez auta tego dnia.
create or replace function private.assign_vehicle_day(
  p_restaurant_id uuid, p_day date, p_member_id uuid, p_vehicle_id uuid, p_by text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.staff_members where id = p_member_id and restaurant_id = p_restaurant_id) then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  delete from public.vehicle_days where member_id = p_member_id and day = p_day;
  if p_vehicle_id is null then
    return;
  end if;
  if not exists (select 1 from public.vehicles where id = p_vehicle_id and restaurant_id = p_restaurant_id) then
    raise exception 'Nie znaleziono pojazdu.';
  end if;
  -- Auto ma jednego kierowcę dziennie: poprzedni traci je tego dnia.
  delete from public.vehicle_days where vehicle_id = p_vehicle_id and day = p_day;
  insert into public.vehicle_days (restaurant_id, day, vehicle_id, member_id, assigned_by_name)
  values (p_restaurant_id, p_day, p_vehicle_id, p_member_id, p_by);
end;
$$;

create or replace function public.panel_set_vehicle_day(
  p_restaurant_id uuid, p_day date, p_member_id uuid, p_vehicle_id uuid, p_editor_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (private.has_permission(p_restaurant_id, 'fleet') or private.has_permission(p_restaurant_id, 'schedule')
          or private.has_permission(p_restaurant_id, 'orders')) then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;
  perform private.check_inventory_member(p_restaurant_id, p_editor_id);
  perform private.assign_vehicle_day(p_restaurant_id, p_day, p_member_id, p_vehicle_id,
                                     private.note_author(p_restaurant_id, p_editor_id));
end;
$$;

-- ---------------------------------------------------------------
-- 3. Kontrola auta: przebieg i zdjęcia dookoła
-- ---------------------------------------------------------------

create table if not exists public.vehicle_checks (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  vehicle_id     uuid not null references public.vehicles (id) on delete cascade,
  member_id      uuid references public.staff_members (id) on delete set null,
  member_name    text,
  shift_id       uuid references public.staff_shifts (id) on delete set null,
  day            date not null,
  kind           text not null check (kind in ('start', 'end')),
  odometer_km    integer check (odometer_km is null or odometer_km between 0 and 9999999),
  -- Ścieżki w zasobniku vehicle-photos: przód, tył, lewy bok, prawy bok.
  photos         text[] not null default '{}',
  created_at     timestamptz not null default now()
);
create index if not exists vehicle_checks_vehicle on public.vehicle_checks (vehicle_id, created_at desc);
create index if not exists vehicle_checks_shift on public.vehicle_checks (shift_id, kind);
alter table public.vehicle_checks enable row level security;

-- Lokal ma floty (aktywne pojazdy), więc dostawca musi zrobić kontrolę auta przed pierwszym kursem.
create or replace function private.vehicle_check_required(p_restaurant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.vehicles v where v.restaurant_id = p_restaurant_id and v.active)
$$;

-- Dostawca gotowy do kursów: lokal bez floty albo kontrola auta na początku tej zmiany zrobiona.
create or replace function private.vehicle_ready(p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not private.vehicle_check_required(m.restaurant_id)
         or exists (
           select 1 from public.vehicle_checks c
           join public.staff_shifts s on s.id = c.shift_id and s.ended_at is null
           where c.member_id = p_member_id and c.kind = 'start'
         )
  from public.staff_members m
  where m.id = p_member_id
$$;

-- Kolejka dostawców: zamiast lokalizacji liczy się kontrola auta (kolumna „located” = gotowy do kursów).
create or replace function private.courier_queue(p_restaurant_id uuid)
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
         coalesce(private.vehicle_ready(m.id), true)
  from public.staff_members m
  join public.staff_shifts s on s.member_id = m.id and s.ended_at is null
  where m.restaurant_id = p_restaurant_id
    and m.active
    and private.is_courier(m.id)
  order by 4, 5 desc, 3, s.started_at
$$;

-- Stan auta w aplikacji dostawcy: czy kontrola jest wymagana, auto na dziś, co już zrobione, lista aut.
create or replace function public.staff_vehicle_status(p_member_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
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
    'required', private.is_courier(p_member_id) and private.vehicle_check_required(v_member.restaurant_id),
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

-- Kontrola auta z aplikacji: przebieg i zdjęcia (ścieżki już wgranych plików). Przy „start” auto staje się
-- autem dostawcy na dziś, a kolejka od razu daje mu czekające kursy.
create or replace function public.staff_vehicle_check(
  p_member_id uuid, p_vehicle_id uuid, p_kind text, p_odometer_km integer, p_photos text[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member   staff_members%rowtype;
  v_vehicle  vehicles%rowtype;
  v_shift    staff_shifts%rowtype;
  v_tz       text;
  v_day      date;
  v_last     integer;
begin
  v_member := private.my_member(p_member_id);
  if p_kind not in ('start', 'end') then
    raise exception 'Nieznany rodzaj kontroli.';
  end if;
  select * into v_vehicle from vehicles where id = p_vehicle_id and restaurant_id = v_member.restaurant_id;
  if not found then
    raise exception 'Nie znaleziono pojazdu.';
  end if;
  select * into v_shift from staff_shifts where member_id = p_member_id and ended_at is null
  order by started_at desc limit 1;
  if not found then
    raise exception 'Kontrolę auta robi się na zmianie. Najpierw zeskanuj kod w lokalu.';
  end if;
  if coalesce(cardinality(p_photos), 0) < 4 then
    raise exception 'Zrób cztery zdjęcia: przód, tył i oba boki.';
  end if;
  if exists (select 1 from unnest(p_photos) p where p not like v_member.restaurant_id::text || '/%') then
    raise exception 'Zdjęcia nie należą do tego lokalu.';
  end if;
  if v_vehicle.kind in ('car', 'scooter') and p_odometer_km is null then
    raise exception 'Wpisz przebieg z licznika.';
  end if;
  if p_odometer_km is not null then
    select c.odometer_km into v_last from vehicle_checks c
    where c.vehicle_id = p_vehicle_id and c.odometer_km is not null order by c.created_at desc limit 1;
    if v_last is not null and p_odometer_km < v_last then
      raise exception 'Przebieg jest mniejszy niż ostatnio wpisany (% km). Sprawdź licznik.', v_last;
    end if;
  end if;
  select coalesce(timezone, 'Europe/Warsaw') into v_tz from restaurants where id = v_member.restaurant_id;
  v_day := (now() at time zone v_tz)::date;
  insert into vehicle_checks (restaurant_id, vehicle_id, member_id, member_name, shift_id, day, kind, odometer_km, photos)
  values (v_member.restaurant_id, p_vehicle_id, p_member_id, v_member.name, v_shift.id, v_day, p_kind, p_odometer_km,
          p_photos);
  if p_kind = 'start' then
    perform private.assign_vehicle_day(v_member.restaurant_id, v_day, p_member_id, p_vehicle_id, v_member.name);
    perform private.dispatch_deliveries(v_member.restaurant_id);
  end if;
end;
$$;

-- Panel → Flota: kontrole auta (z kierowcą, przebiegiem i zdjęciami) w dniach [p_from, p_to].
create or replace function public.panel_vehicle_checks(p_restaurant_id uuid, p_vehicle_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform private.require_permission(p_restaurant_id, 'fleet');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', c.id, 'vehicle_id', c.vehicle_id, 'member_id', c.member_id, 'member_name', c.member_name,
      'day', c.day, 'kind', c.kind, 'odometer_km', c.odometer_km, 'photos', c.photos, 'created_at', c.created_at
    ) order by c.created_at desc)
    from vehicle_checks c
    where c.restaurant_id = p_restaurant_id
      and (p_vehicle_id is null or c.vehicle_id = p_vehicle_id)
      and c.day between p_from and p_to
  ), '[]'::jsonb);
end;
$$;

-- Zdjęcia aut: prywatny zasobnik, pliki w folderze lokalu (pierwszy człon ścieżki to id lokalu).
insert into storage.buckets (id, name, public)
values ('vehicle-photos', 'vehicle-photos', false)
on conflict (id) do nothing;

create or replace function private.can_use_vehicle_photos(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_restaurant uuid;
begin
  begin
    v_restaurant := (storage.foldername(p_name))[1]::uuid;
  exception when others then
    return false;
  end;
  return private.has_staff_role(v_restaurant);
end;
$$;

drop policy if exists "Obsługa lokalu dodaje zdjęcia aut" on storage.objects;
create policy "Obsługa lokalu dodaje zdjęcia aut" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'vehicle-photos' and private.can_use_vehicle_photos(name));
drop policy if exists "Obsługa lokalu widzi zdjęcia aut" on storage.objects;
create policy "Obsługa lokalu widzi zdjęcia aut" on storage.objects
  for select to authenticated
  using (bucket_id = 'vehicle-photos' and private.can_use_vehicle_photos(name));

revoke execute on function private.assign_vehicle_day(uuid, date, uuid, uuid, text) from public, anon, authenticated;
revoke execute on function private.vehicle_check_required(uuid) from public, anon, authenticated;
revoke execute on function private.vehicle_ready(uuid) from public, anon, authenticated;
revoke execute on function public.panel_vehicle_days(uuid, date, date) from public, anon;
revoke execute on function public.panel_set_vehicle_day(uuid, date, uuid, uuid, uuid) from public, anon;
revoke execute on function public.staff_vehicle_status(uuid) from public, anon;
revoke execute on function public.staff_vehicle_check(uuid, uuid, text, integer, text[]) from public, anon;
revoke execute on function public.panel_vehicle_checks(uuid, uuid, date, date) from public, anon;
revoke execute on function private.can_use_vehicle_photos(text) from public, anon;
grant execute on function private.can_use_vehicle_photos(text) to authenticated;
grant execute on function public.panel_vehicle_days(uuid, date, date) to authenticated;
grant execute on function public.panel_set_vehicle_day(uuid, date, uuid, uuid, uuid) to authenticated;
grant execute on function public.staff_vehicle_status(uuid) to authenticated;
grant execute on function public.staff_vehicle_check(uuid, uuid, text, integer, text[]) to authenticated;
grant execute on function public.panel_vehicle_checks(uuid, uuid, date, date) to authenticated;
