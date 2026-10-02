-- Table · migracja 0046
-- 1. Flota: numer VIN pojazdu (17 znaków, litery i cyfry bez I, O, Q), unikalny w lokalu.
-- 2. Stawka godzinowa pracownika w osobnej tabeli staff_rates: czyta i zmienia tylko osoba z uprawnieniem „Pracownicy”
--    (staff_members czytają wszyscy pracownicy lokalu, a stawki innych osób nie są dla nich).
-- 3. Statystyki pracownika i zespołu za miesiąc kalendarzowy (od 1. do ostatniego dnia, w strefie czasowej lokalu)
--    zamiast ostatnich 30 dni, z zarobkiem: przepracowane godziny × stawka.

-- ---------------------------------------------------------------
-- 1. VIN
-- ---------------------------------------------------------------

alter table public.vehicles
  add column vin text check (vin ~ '^[A-HJ-NPR-Z0-9]{17}$');

create unique index vehicles_vin_unique on public.vehicles (restaurant_id, vin) where vin is not null;

drop function public.panel_save_vehicle(uuid, uuid, text, text, text, uuid, text, boolean);
create or replace function public.panel_save_vehicle(
  p_restaurant_id  uuid,
  p_id             uuid,
  p_kind           text,
  p_name           text,
  p_plate          text,
  p_member_id      uuid,
  p_note           text,
  p_active         boolean default true,
  p_vin            text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plate  text := nullif(upper(regexp_replace(btrim(coalesce(p_plate, '')), '\s+', ' ', 'g')), '');
  v_vin    text := nullif(upper(regexp_replace(coalesce(p_vin, ''), '[\s-]', '', 'g')), '');
  v_id     uuid;
begin
  perform private.require_permission(p_restaurant_id, 'fleet');
  if coalesce(p_kind, '') not in ('car', 'scooter', 'bike', 'other') then
    raise exception 'Wybierz rodzaj pojazdu.';
  end if;
  if coalesce(btrim(p_name), '') = '' then
    raise exception 'Wpisz nazwę pojazdu, na przykład „Fiat Panda”.';
  end if;
  if v_vin is not null and v_vin !~ '^[A-HJ-NPR-Z0-9]{17}$' then
    raise exception 'VIN ma 17 znaków: litery i cyfry, bez I, O i Q.';
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
  if v_vin is not null and exists (
    select 1 from vehicles where restaurant_id = p_restaurant_id and vin = v_vin and id is distinct from p_id
  ) then
    raise exception 'Pojazd z tym numerem VIN już jest we flocie.';
  end if;

  if p_id is null then
    insert into vehicles (restaurant_id, kind, name, plate, vin, member_id, note, active)
    values (p_restaurant_id, p_kind, btrim(p_name), v_plate, v_vin, p_member_id,
            nullif(btrim(coalesce(p_note, '')), ''), coalesce(p_active, true))
    returning id into v_id;
  else
    update vehicles
    set kind = p_kind, name = btrim(p_name), plate = v_plate, vin = v_vin, member_id = p_member_id,
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

revoke execute on function public.panel_save_vehicle(uuid, uuid, text, text, text, uuid, text, boolean, text) from public, anon;
grant execute on function public.panel_save_vehicle(uuid, uuid, text, text, text, uuid, text, boolean, text) to authenticated;

-- ---------------------------------------------------------------
-- 2. Stawki
-- ---------------------------------------------------------------

create table public.staff_rates (
  member_id           uuid primary key references public.staff_members (id) on delete cascade,
  restaurant_id       uuid not null references public.restaurants (id) on delete cascade,
  hourly_rate_grosze  integer not null check (hourly_rate_grosze between 0 and 100000),
  updated_at          timestamptz not null default now(),
  updated_by          uuid references auth.users (id) on delete set null
);

alter table public.staff_rates enable row level security;

create policy "Stawki widzi osoba z uprawnieniem Pracownicy"
  on public.staff_rates for select to authenticated
  using (private.has_permission(restaurant_id, 'staff'));

revoke all on public.staff_rates from anon, authenticated;
grant select on public.staff_rates to authenticated;

-- Stawka za godzinę w groszach. Null usuwa stawkę.
create or replace function public.panel_set_staff_rate(p_member_id uuid, p_rate_grosze integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
begin
  select restaurant_id into v_restaurant from staff_members where id = p_member_id;
  if v_restaurant is null then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  perform private.require_permission(v_restaurant, 'staff');
  if p_rate_grosze is null then
    delete from staff_rates where member_id = p_member_id;
    return;
  end if;
  if p_rate_grosze not between 0 and 100000 then
    raise exception 'Stawka od 0 do 1000 zł za godzinę.';
  end if;
  insert into staff_rates (member_id, restaurant_id, hourly_rate_grosze, updated_by)
  values (p_member_id, v_restaurant, p_rate_grosze, auth.uid())
  on conflict (member_id) do update
  set hourly_rate_grosze = excluded.hourly_rate_grosze, updated_at = now(), updated_by = excluded.updated_by;
end;
$$;

revoke execute on function public.panel_set_staff_rate(uuid, integer) from public, anon;
grant execute on function public.panel_set_staff_rate(uuid, integer) to authenticated;

-- Granice miesiąca kalendarzowego w strefie czasowej lokalu: [od, do).
create or replace function private.month_range(p_restaurant_id uuid, p_month date, out starts timestamptz, out ends timestamptz)
language sql
stable
set search_path = ''
as $$
  select
    (date_trunc('month', p_month::timestamp)::timestamp at time zone coalesce(r.timezone, 'Europe/Warsaw')),
    ((date_trunc('month', p_month::timestamp) + interval '1 month')::timestamp at time zone coalesce(r.timezone, 'Europe/Warsaw'))
  from public.restaurants r
  where r.id = p_restaurant_id
$$;

-- ---------------------------------------------------------------
-- 3. Statystyki za miesiąc
-- ---------------------------------------------------------------

drop function public.panel_member_stats(uuid, integer);
create or replace function public.panel_member_stats(p_member_id uuid, p_days integer default 30, p_month date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_member  staff_members%rowtype;
  v_start   timestamptz;
  v_end     timestamptz;
  v_week    timestamptz := date_trunc('week', now());
  v_rate    integer;
  v_seconds bigint;
begin
  select * into v_member from staff_members where id = p_member_id;
  if not found then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  if not private.has_permission(v_member.restaurant_id, 'staff') then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;

  if p_month is null then
    v_start := now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 366)));
    v_end := now();
  else
    select m.starts, m.ends into v_start, v_end from private.month_range(v_member.restaurant_id, p_month) m;
  end if;
  select hourly_rate_grosze into v_rate from staff_rates where member_id = p_member_id;

  select coalesce(sum(extract(epoch from least(coalesce(s.ended_at, now()), v_end) - greatest(s.started_at, v_start))), 0)::bigint
  into v_seconds
  from staff_shifts s
  where s.member_id = p_member_id and coalesce(s.ended_at, now()) > v_start and s.started_at < v_end;

  return (
    with closed as (
      select (select coalesce(sum(i.unit_price_grosze * i.quantity), 0)
              from order_items i where i.order_id = o.id and i.status <> 'cancelled') as total
      from orders o
      where o.closed_by_member = p_member_id and o.status = 'paid' and o.closed_at >= v_start and o.closed_at < v_end
    ),
    items as (
      select name, quantity from order_items
      where created_by_member = p_member_id and status <> 'cancelled' and created_at >= v_start and created_at < v_end
    )
    select jsonb_build_object(
      'seconds', v_seconds,
      'shifts', (select count(*) from staff_shifts s
                 where s.member_id = p_member_id and coalesce(s.ended_at, now()) > v_start and s.started_at < v_end),
      'week_seconds', (
        select coalesce(sum(extract(epoch from coalesce(ended_at, now()) - greatest(started_at, v_week))), 0)
        from staff_shifts where member_id = p_member_id and coalesce(ended_at, now()) > v_week
      )::bigint,
      'open_since', (select started_at from staff_shifts where member_id = p_member_id and ended_at is null),
      'last_shift', (select max(started_at) from staff_shifts where member_id = p_member_id),
      'orders_opened', (select count(*) from orders
                        where opened_by_member = p_member_id and opened_at >= v_start and opened_at < v_end),
      'orders_closed', (select count(*) from closed),
      'revenue', (select coalesce(sum(total), 0) from closed)::bigint,
      'items', (select coalesce(sum(quantity), 0) from items)::bigint,
      'top_items', (
        select coalesce(jsonb_agg(t), '[]'::jsonb)
        from (
          select name, sum(quantity)::integer as quantity
          from items group by name order by sum(quantity) desc, name limit 5
        ) t
      ),
      'planned', (select count(*) from staff_schedule
                  where member_id = p_member_id and day >= current_date and status = 'accepted'),
      'rate', v_rate,
      'earnings', case when v_rate is null then null else round(v_seconds * v_rate / 3600.0)::bigint end
    )
  );
end;
$$;

revoke execute on function public.panel_member_stats(uuid, integer, date) from public, anon;
grant execute on function public.panel_member_stats(uuid, integer, date) to authenticated;

drop function public.panel_team_stats(uuid, integer);
create or replace function public.panel_team_stats(p_restaurant_id uuid, p_days integer default 30, p_month date default null)
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
  deliveries     integer,
  rate           integer,
  earnings       bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_start  timestamptz;
  v_end    timestamptz;
  v_pay    boolean;
begin
  perform private.require_permission(p_restaurant_id, 'stats');
  -- Stawki i zarobki tylko dla osoby z uprawnieniem „Pracownicy”.
  v_pay := private.has_permission(p_restaurant_id, 'staff');
  if p_month is null then
    v_start := now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 366)));
    v_end := now();
  else
    select m.starts, m.ends into v_start, v_end from private.month_range(p_restaurant_id, p_month) m;
  end if;

  return query
  with base as (
    select
      m.id,
      m.name,
      pos.name as position_name,
      m.active,
      (
        select coalesce(sum(extract(epoch from least(coalesce(s.ended_at, now()), v_end) - greatest(s.started_at, v_start))), 0)
        from staff_shifts s
        where s.member_id = m.id and coalesce(s.ended_at, now()) > v_start and s.started_at < v_end
      )::bigint as seconds,
      (select count(*) from staff_shifts s
       where s.member_id = m.id and coalesce(s.ended_at, now()) > v_start and s.started_at < v_end)::integer as shifts,
      (select count(*) from orders o
       where o.opened_by_member = m.id and o.opened_at >= v_start and o.opened_at < v_end)::integer as orders_opened,
      (select count(*) from orders o
       where o.closed_by_member = m.id and o.status = 'paid'
         and o.closed_at >= v_start and o.closed_at < v_end)::integer as orders_closed,
      (
        select coalesce(sum(i.unit_price_grosze * i.quantity), 0)
        from orders o
        join order_items i on i.order_id = o.id and i.status <> 'cancelled'
        where o.closed_by_member = m.id and o.status = 'paid' and o.closed_at >= v_start and o.closed_at < v_end
      )::bigint as revenue,
      (
        select coalesce(sum(i.quantity), 0)
        from order_items i
        where i.created_by_member = m.id and i.status <> 'cancelled' and i.created_at >= v_start and i.created_at < v_end
      )::bigint as items,
      (select count(*) from orders o
       where o.courier_member = m.id and o.fulfillment = 'delivered'
         and o.delivered_at >= v_start and o.delivered_at < v_end)::integer as deliveries,
      case when v_pay then sr.hourly_rate_grosze end as rate
    from staff_members m
    left join staff_positions pos on pos.id = m.position_id
    left join staff_rates sr on sr.member_id = m.id
    where m.restaurant_id = p_restaurant_id
  )
  select b.id, b.name, b.position_name, b.active, b.seconds, b.shifts, b.orders_opened, b.orders_closed,
         b.revenue, b.items, b.deliveries, b.rate,
         case when b.rate is null then null else round(b.seconds * b.rate / 3600.0)::bigint end
  from base b
  order by b.seconds desc, b.name;
end;
$$;

revoke execute on function public.panel_team_stats(uuid, integer, date) from public, anon;
grant execute on function public.panel_team_stats(uuid, integer, date) to authenticated;
