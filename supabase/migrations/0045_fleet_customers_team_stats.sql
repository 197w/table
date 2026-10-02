-- Table · migracja 0045
-- Nowy układ panelu: grupy Rezerwacje, Kuchnia, Dostawy, Pracownicy, Baza klientów.
-- 1. Flota (grupa Dostawy): pojazdy dostawców (auto, skuter, rower, inny), rejestracja, przypisany dostawca.
--    Uprawnienie „fleet”.
-- 2. Klienci (grupa Baza klientów): goście z rezerwacji i zamówień na wynos z liczbą wizyt, nieobecności i wydatkami.
--    Uprawnienie „customers”.
-- 3. Statystyki zespołu (grupa Pracownicy): godziny, zmiany, rachunki, sprzedaż i kursy na osobę. Uprawnienie „stats”.
-- Nowe uprawnienia dostaje samo stanowisko „ALL”. Pozostałym nadaje je osoba z uprawnieniem „Stanowiska”.

create or replace function private.all_permissions()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['reservations', 'floor', 'floor_edit', 'orders', 'orders_close', 'orders_cancel', 'deliveries', 'fleet',
               'kitchen', 'kitchen_settings', 'serving', 'staff', 'staff_logins', 'schedule', 'timesheet', 'positions',
               'profile', 'menu', 'menu_edit', 'menu_availability', 'inventory_edit', 'inventory_count',
               'customers', 'reviews', 'stats']
$$;

update public.staff_positions set permissions = private.all_permissions() where system_key = 'all';

-- ---------------------------------------------------------------
-- 1. Flota
-- ---------------------------------------------------------------

create table public.vehicles (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  kind           text not null default 'car' check (kind in ('car', 'scooter', 'bike', 'other')),
  name           text not null check (char_length(btrim(name)) between 1 and 80),
  plate          text check (char_length(plate) <= 15),
  member_id      uuid references public.staff_members (id) on delete set null,
  note           text check (char_length(note) <= 200),
  active         boolean not null default true,
  created_at     timestamptz not null default now(),
  unique (restaurant_id, plate)
);

create index vehicles_restaurant_idx on public.vehicles (restaurant_id);

alter table public.vehicles enable row level security;

create policy "Obsługa lokalu widzi pojazdy"
  on public.vehicles for select to authenticated
  using (private.has_staff_role(restaurant_id));

revoke all on public.vehicles from anon, authenticated;
grant select on public.vehicles to authenticated;

-- Dodanie albo zmiana pojazdu. p_id null: nowy pojazd. Rejestracja wielkimi literami, bez podwójnych spacji.
create or replace function public.panel_save_vehicle(
  p_restaurant_id  uuid,
  p_id             uuid,
  p_kind           text,
  p_name           text,
  p_plate          text,
  p_member_id      uuid,
  p_note           text,
  p_active         boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plate  text := nullif(upper(regexp_replace(btrim(coalesce(p_plate, '')), '\s+', ' ', 'g')), '');
  v_id     uuid;
begin
  perform private.require_permission(p_restaurant_id, 'fleet');
  if coalesce(p_kind, '') not in ('car', 'scooter', 'bike', 'other') then
    raise exception 'Wybierz rodzaj pojazdu.';
  end if;
  if coalesce(btrim(p_name), '') = '' then
    raise exception 'Wpisz nazwę pojazdu, na przykład „Fiat Panda”.';
  end if;
  if p_member_id is not null
     and not exists (select 1 from staff_members where id = p_member_id and restaurant_id = p_restaurant_id) then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  if v_plate is not null and exists (
    select 1 from vehicles where restaurant_id = p_restaurant_id and plate = v_plate and id is distinct from p_id
  ) then
    raise exception 'Pojazd z rejestracją % już jest we flocie.', v_plate;
  end if;

  if p_id is null then
    insert into vehicles (restaurant_id, kind, name, plate, member_id, note, active)
    values (p_restaurant_id, p_kind, btrim(p_name), v_plate, p_member_id,
            nullif(btrim(coalesce(p_note, '')), ''), coalesce(p_active, true))
    returning id into v_id;
  else
    update vehicles
    set kind = p_kind, name = btrim(p_name), plate = v_plate, member_id = p_member_id,
        note = nullif(btrim(coalesce(p_note, '')), ''), active = coalesce(p_active, true)
    where id = p_id and restaurant_id = p_restaurant_id
    returning id into v_id;
    if v_id is null then
      raise exception 'Nie znaleziono pojazdu.';
    end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.panel_delete_vehicle(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
begin
  select restaurant_id into v_restaurant from vehicles where id = p_id;
  if v_restaurant is null then
    raise exception 'Nie znaleziono pojazdu.';
  end if;
  perform private.require_permission(v_restaurant, 'fleet');
  delete from vehicles where id = p_id;
end;
$$;

revoke execute on function public.panel_save_vehicle(uuid, uuid, text, text, text, uuid, text, boolean) from public, anon;
revoke execute on function public.panel_delete_vehicle(uuid) from public, anon;
grant execute on function public.panel_save_vehicle(uuid, uuid, text, text, text, uuid, text, boolean) to authenticated;
grant execute on function public.panel_delete_vehicle(uuid) to authenticated;

-- ---------------------------------------------------------------
-- 2. Klienci
-- ---------------------------------------------------------------

-- Goście lokalu: konto w aplikacji (user_id) albo numer telefonu (ostatnie 9 cyfr), a bez obu imię.
-- Wizyty to rezerwacje zakończone przy stoliku (seated, completed), wydatki to zamknięte rachunki z rezerwacji
-- i dostarczone albo odebrane zamówienia na wynos.
create or replace function public.panel_customers(p_restaurant_id uuid)
returns table (
  key               text,
  name              text,
  phone             text,
  from_app          boolean,
  visits            integer,
  reservations      integer,
  no_shows          integer,
  cancelled         integer,
  orders            integer,
  spent_grosze      bigint,
  first_seen        timestamptz,
  last_visit        timestamptz,
  next_reservation  timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform private.require_permission(p_restaurant_id, 'customers');

  return query
  with events as (
    select
      coalesce(
        r.user_id::text,
        'tel:' || nullif(right(regexp_replace(coalesce(r.guest_phone, ''), '[^0-9]', '', 'g'), 9), ''),
        'imie:' || nullif(lower(btrim(r.guest_name)), '')
      ) as key,
      r.user_id is not null as from_app,
      coalesce(nullif(btrim(r.guest_name), ''), nullif(btrim(p.full_name), ''), nullif(btrim(p.first_name), '')) as name,
      coalesce(
        nullif(btrim(r.guest_phone), ''),
        case when u.phone is not null and u.phone <> '' then '+' || u.phone end
      ) as phone,
      r.starts_at as at,
      'reservation'::text as kind,
      r.status::text as status,
      (
        select coalesce(sum(i.unit_price_grosze * i.quantity), 0)
        from orders o
        join order_items i on i.order_id = o.id and i.status <> 'cancelled'
        where o.reservation_id = r.id and o.status = 'paid'
      )::bigint as spent
    from reservations r
    left join profiles p on p.id = r.user_id
    left join auth.users u on u.id = r.user_id
    where r.restaurant_id = p_restaurant_id and r.source <> 'block'
    union all
    select
      coalesce(
        o.guest_id::text,
        'tel:' || nullif(right(regexp_replace(coalesce(o.customer_phone, ''), '[^0-9]', '', 'g'), 9), ''),
        'imie:' || nullif(lower(btrim(o.customer_name)), '')
      ),
      o.guest_id is not null,
      nullif(btrim(o.customer_name), ''),
      nullif(btrim(o.customer_phone), ''),
      o.opened_at,
      'order'::text,
      o.fulfillment,
      (
        (select coalesce(sum(i.unit_price_grosze * i.quantity), 0)
         from order_items i where i.order_id = o.id and i.status <> 'cancelled')
        + o.delivery_fee_grosze
      )::bigint
    from orders o
    where o.restaurant_id = p_restaurant_id and o.kind <> 'dine_in' and o.fulfillment = 'delivered'
  )
  select
    e.key,
    coalesce((array_agg(e.name order by e.at desc) filter (where e.name is not null))[1], 'Gość'),
    (array_agg(e.phone order by e.at desc) filter (where e.phone is not null))[1],
    bool_or(e.from_app),
    (count(*) filter (where e.kind = 'reservation' and e.status in ('seated', 'completed')))::integer,
    (count(*) filter (where e.kind = 'reservation'))::integer,
    (count(*) filter (where e.kind = 'reservation' and e.status = 'no_show'))::integer,
    (count(*) filter (where e.kind = 'reservation' and e.status = 'cancelled'))::integer,
    (count(*) filter (where e.kind = 'order'))::integer,
    coalesce(sum(e.spent), 0)::bigint,
    min(e.at),
    max(e.at) filter (where (e.kind = 'reservation' and e.status in ('seated', 'completed')) or e.kind = 'order'),
    min(e.at) filter (where e.kind = 'reservation' and e.status = 'confirmed' and e.at > now())
  from events e
  where e.key is not null
  group by e.key
  order by 12 desc nulls last, 2;
end;
$$;

revoke execute on function public.panel_customers(uuid) from public, anon;
grant execute on function public.panel_customers(uuid) to authenticated;

-- ---------------------------------------------------------------
-- 3. Statystyki zespołu
-- ---------------------------------------------------------------

create or replace function public.panel_team_stats(p_restaurant_id uuid, p_days integer default 30)
returns table (
  member_id      uuid,
  name           text,
  position_name  text,
  active         boolean,
  seconds        bigint,
  shifts         integer,
  orders_opened  integer,
  orders_closed  integer,
  revenue        bigint,
  items          bigint,
  deliveries     integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_start  timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 366)));
begin
  perform private.require_permission(p_restaurant_id, 'stats');

  return query
  select
    m.id,
    m.name,
    pos.name,
    m.active,
    (
      select coalesce(sum(extract(epoch from coalesce(s.ended_at, now()) - greatest(s.started_at, v_start))), 0)
      from staff_shifts s
      where s.member_id = m.id and coalesce(s.ended_at, now()) > v_start
    )::bigint,
    (select count(*) from staff_shifts s where s.member_id = m.id and coalesce(s.ended_at, now()) > v_start)::integer,
    (select count(*) from orders o where o.opened_by_member = m.id and o.opened_at >= v_start)::integer,
    (select count(*) from orders o
     where o.closed_by_member = m.id and o.status = 'paid' and o.closed_at >= v_start)::integer,
    (
      select coalesce(sum(i.unit_price_grosze * i.quantity), 0)
      from orders o
      join order_items i on i.order_id = o.id and i.status <> 'cancelled'
      where o.closed_by_member = m.id and o.status = 'paid' and o.closed_at >= v_start
    )::bigint,
    (
      select coalesce(sum(i.quantity), 0)
      from order_items i
      where i.created_by_member = m.id and i.status <> 'cancelled' and i.created_at >= v_start
    )::bigint,
    (select count(*) from orders o
     where o.courier_member = m.id and o.fulfillment = 'delivered' and o.delivered_at >= v_start)::integer
  from staff_members m
  left join staff_positions pos on pos.id = m.position_id
  where m.restaurant_id = p_restaurant_id
  order by 5 desc, m.name;
end;
$$;

revoke execute on function public.panel_team_stats(uuid, integer) from public, anon;
grant execute on function public.panel_team_stats(uuid, integer) to authenticated;
