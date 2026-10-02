-- Table · migracja 0047
-- 1. Rodzaj umowy przy stawce pracownika (zlecenie, zlecenie – student do 26 lat, umowa o pracę). Stawka w bazie
--    jest brutto; netto liczy panel ze składek ZUS i PIT, więc statystyki zwracają też rodzaj umowy.
-- 2. Notatki o klientach (Baza klientów → Klienci): widzą je tylko pracownicy lokalu, piszą osoby z uprawnieniem
--    „Baza klientów”. Historia wizyt i zamówień klienta. Klucz klienta w jednej funkcji private.customer_key.
-- 3. Notatki przy pojeździe (Flota): dziennik zamiast jednego pola „Uwagi” (stare uwagi przechodzą do dziennika).

-- ---------------------------------------------------------------
-- 1. Umowy
-- ---------------------------------------------------------------

alter table public.staff_rates
  add column contract text not null default 'zlecenie' check (contract in ('zlecenie', 'zlecenie_student', 'praca'));

drop function public.panel_set_staff_rate(uuid, integer);
create or replace function public.panel_set_staff_rate(p_member_id uuid, p_rate_grosze integer, p_contract text default 'zlecenie')
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
  if coalesce(p_contract, '') not in ('zlecenie', 'zlecenie_student', 'praca') then
    raise exception 'Wybierz rodzaj umowy.';
  end if;
  insert into staff_rates (member_id, restaurant_id, hourly_rate_grosze, contract, updated_by)
  values (p_member_id, v_restaurant, p_rate_grosze, p_contract, auth.uid())
  on conflict (member_id) do update
  set hourly_rate_grosze = excluded.hourly_rate_grosze, contract = excluded.contract,
      updated_at = now(), updated_by = excluded.updated_by;
end;
$$;

revoke execute on function public.panel_set_staff_rate(uuid, integer, text) from public, anon;
grant execute on function public.panel_set_staff_rate(uuid, integer, text) to authenticated;

-- Statystyki pracownika: do stawki dochodzi rodzaj umowy.
create or replace function public.panel_member_stats(p_member_id uuid, p_days integer default 30, p_month date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_member    staff_members%rowtype;
  v_start     timestamptz;
  v_end       timestamptz;
  v_week      timestamptz := date_trunc('week', now());
  v_rate      integer;
  v_contract  text;
  v_seconds   bigint;
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
  select hourly_rate_grosze, contract into v_rate, v_contract from staff_rates where member_id = p_member_id;

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
      'contract', v_contract,
      'earnings', case when v_rate is null then null else round(v_seconds * v_rate / 3600.0)::bigint end
    )
  );
end;
$$;

drop function public.panel_team_stats(uuid, integer, date);
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
  earnings       bigint,
  contract       text
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
      case when v_pay then sr.hourly_rate_grosze end as rate,
      case when v_pay then sr.contract end as contract
    from staff_members m
    left join staff_positions pos on pos.id = m.position_id
    left join staff_rates sr on sr.member_id = m.id
    where m.restaurant_id = p_restaurant_id
  )
  select b.id, b.name, b.position_name, b.active, b.seconds, b.shifts, b.orders_opened, b.orders_closed,
         b.revenue, b.items, b.deliveries, b.rate,
         case when b.rate is null then null else round(b.seconds * b.rate / 3600.0)::bigint end,
         b.contract
  from base b
  order by b.seconds desc, b.name;
end;
$$;

revoke execute on function public.panel_team_stats(uuid, integer, date) from public, anon;
grant execute on function public.panel_team_stats(uuid, integer, date) to authenticated;

-- ---------------------------------------------------------------
-- 2. Klienci: klucz, historia i notatki
-- ---------------------------------------------------------------

-- Klient lokalu: konto w aplikacji, a bez niego telefon (ostatnie 9 cyfr), a bez telefonu imię.
create or replace function private.customer_key(p_user uuid, p_phone text, p_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    p_user::text,
    'tel:' || nullif(right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9), ''),
    'imie:' || nullif(lower(btrim(p_name)), '')
  )
$$;

create table public.customer_notes (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  customer_key   text not null check (char_length(customer_key) <= 200),
  body           text not null check (char_length(btrim(body)) between 1 and 1000),
  author_member  uuid references public.staff_members (id) on delete set null,
  author_name    text,
  created_by     uuid references auth.users (id) on delete set null,
  created_at     timestamptz not null default now()
);

create index customer_notes_key_idx on public.customer_notes (restaurant_id, customer_key, created_at desc);

alter table public.customer_notes enable row level security;

create policy "Notatki o klientach widzą pracownicy lokalu"
  on public.customer_notes for select to authenticated
  using (private.has_staff_role(restaurant_id));

revoke all on public.customer_notes from anon, authenticated;
grant select on public.customer_notes to authenticated;

-- Autor notatki: pracownik zalogowany w panelu albo konto restauracji.
create or replace function private.note_author(p_restaurant_id uuid, p_member_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_name  text;
begin
  if p_member_id is null then
    return 'Konto restauracji';
  end if;
  select name into v_name from public.staff_members where id = p_member_id and restaurant_id = p_restaurant_id;
  if v_name is null then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  return v_name;
end;
$$;

create or replace function public.panel_add_customer_note(
  p_restaurant_id  uuid,
  p_key            text,
  p_body           text,
  p_member_id      uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id  uuid;
begin
  perform private.require_permission(p_restaurant_id, 'customers');
  if coalesce(btrim(p_body), '') = '' then
    raise exception 'Wpisz notatkę.';
  end if;
  insert into customer_notes (restaurant_id, customer_key, body, author_member, author_name, created_by)
  values (p_restaurant_id, p_key, left(btrim(p_body), 1000), p_member_id,
          private.note_author(p_restaurant_id, p_member_id), auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.panel_delete_customer_note(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
begin
  select restaurant_id into v_restaurant from customer_notes where id = p_id;
  if v_restaurant is null then
    raise exception 'Nie znaleziono notatki.';
  end if;
  perform private.require_permission(v_restaurant, 'customers');
  delete from customer_notes where id = p_id;
end;
$$;

-- Ostatnie wizyty i zamówienia klienta, najnowsze pierwsze.
create or replace function public.panel_customer_history(p_restaurant_id uuid, p_key text)
returns table (at timestamptz, kind text, status text, party_size integer, spent_grosze bigint)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform private.require_permission(p_restaurant_id, 'customers');
  return query
  select * from (
    select
      r.starts_at,
      'reservation'::text,
      r.status::text,
      r.party_size::integer,
      (
        select coalesce(sum(i.unit_price_grosze * i.quantity), 0)
        from orders o
        join order_items i on i.order_id = o.id and i.status <> 'cancelled'
        where o.reservation_id = r.id and o.status = 'paid'
      )::bigint
    from reservations r
    where r.restaurant_id = p_restaurant_id
      and r.source <> 'block'
      and private.customer_key(r.user_id, r.guest_phone, r.guest_name) = p_key
    union all
    select
      o.opened_at,
      o.kind,
      o.fulfillment,
      null::integer,
      (
        (select coalesce(sum(i.unit_price_grosze * i.quantity), 0)
         from order_items i where i.order_id = o.id and i.status <> 'cancelled')
        + o.delivery_fee_grosze
      )::bigint
    from orders o
    where o.restaurant_id = p_restaurant_id
      and o.kind <> 'dine_in'
      and o.fulfillment = 'delivered'
      and private.customer_key(o.guest_id, o.customer_phone, o.customer_name) = p_key
  ) h
  order by 1 desc
  limit 60;
end;
$$;

revoke execute on function public.panel_add_customer_note(uuid, text, text, uuid) from public, anon;
revoke execute on function public.panel_delete_customer_note(uuid) from public, anon;
revoke execute on function public.panel_customer_history(uuid, text) from public, anon;
grant execute on function public.panel_add_customer_note(uuid, text, text, uuid) to authenticated;
grant execute on function public.panel_delete_customer_note(uuid) to authenticated;
grant execute on function public.panel_customer_history(uuid, text) to authenticated;

-- ---------------------------------------------------------------
-- 3. Notatki przy pojeździe
-- ---------------------------------------------------------------

create table public.vehicle_notes (
  id             uuid primary key default gen_random_uuid(),
  vehicle_id     uuid not null references public.vehicles (id) on delete cascade,
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  body           text not null check (char_length(btrim(body)) between 1 and 1000),
  author_member  uuid references public.staff_members (id) on delete set null,
  author_name    text,
  created_by     uuid references auth.users (id) on delete set null,
  created_at     timestamptz not null default now()
);

create index vehicle_notes_vehicle_idx on public.vehicle_notes (vehicle_id, created_at desc);

alter table public.vehicle_notes enable row level security;

create policy "Notatki o pojazdach widzą pracownicy lokalu"
  on public.vehicle_notes for select to authenticated
  using (private.has_staff_role(restaurant_id));

revoke all on public.vehicle_notes from anon, authenticated;
grant select on public.vehicle_notes to authenticated;

insert into public.vehicle_notes (vehicle_id, restaurant_id, body, author_name, created_at)
select id, restaurant_id, note, 'Uwagi', created_at from public.vehicles where note is not null and btrim(note) <> '';
update public.vehicles set note = null where note is not null;

create or replace function public.panel_add_vehicle_note(p_vehicle_id uuid, p_body text, p_member_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
  v_id          uuid;
begin
  select restaurant_id into v_restaurant from vehicles where id = p_vehicle_id;
  if v_restaurant is null then
    raise exception 'Nie znaleziono pojazdu.';
  end if;
  perform private.require_permission(v_restaurant, 'fleet');
  if coalesce(btrim(p_body), '') = '' then
    raise exception 'Wpisz notatkę.';
  end if;
  insert into vehicle_notes (vehicle_id, restaurant_id, body, author_member, author_name, created_by)
  values (p_vehicle_id, v_restaurant, left(btrim(p_body), 1000), p_member_id,
          private.note_author(v_restaurant, p_member_id), auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.panel_delete_vehicle_note(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
begin
  select restaurant_id into v_restaurant from vehicle_notes where id = p_id;
  if v_restaurant is null then
    raise exception 'Nie znaleziono notatki.';
  end if;
  perform private.require_permission(v_restaurant, 'fleet');
  delete from vehicle_notes where id = p_id;
end;
$$;

revoke execute on function public.panel_add_vehicle_note(uuid, text, uuid) from public, anon;
revoke execute on function public.panel_delete_vehicle_note(uuid) from public, anon;
grant execute on function public.panel_add_vehicle_note(uuid, text, uuid) to authenticated;
grant execute on function public.panel_delete_vehicle_note(uuid) to authenticated;
