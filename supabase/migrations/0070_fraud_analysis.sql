-- Analiza oszustw (10.2026): ocena ryzyka zamówień na wynos z aplikacji Table i limity pozycji w zamówieniu.
-- Sygnały: wzorce zamówień gościa w całym Table (po koncie i numerze telefonu), nieudane płatności, wspólne IP
-- wielu kont i adres IP z ipinfo.io (kraj, VPN/proxy, odległość od lokalu; funkcja Edge fraud-ip, sekret
-- IPINFO_TOKEN). AVS i CVV dojdą z operatorem płatności (dziś płatności są testowe).

-- ---------------------------------------------------------------
-- Limity zamówień z aplikacji (null: bez limitu)
-- ---------------------------------------------------------------

alter table public.restaurants
  add column if not exists takeaway_max_items smallint check (takeaway_max_items between 1 and 999),
  add column if not exists takeaway_max_per_item smallint check (takeaway_max_per_item between 1 and 99);

grant update (takeaway_max_items, takeaway_max_per_item) on public.restaurants to authenticated;

-- ---------------------------------------------------------------
-- Ryzyko zamówienia (tylko obsługa lokalu przez funkcje panel_*)
-- ---------------------------------------------------------------

create table if not exists public.order_risks (
  order_id      uuid primary key references public.orders (id) on delete cascade,
  restaurant_id uuid not null references public.restaurants (id) on delete cascade,
  guest_id      uuid,
  client_ip     inet,
  -- ipinfo.io: city, region, country, loc, org, privacy oraz distance_km od lokalu.
  ip_info       jsonb,
  ip_checked_at timestamptz,
  score         smallint not null default 0,
  -- [{code, points, text}]
  flags         jsonb not null default '[]'::jsonb,
  created_at    timestamptz not null default now()
);

create index if not exists order_risks_restaurant_idx on public.order_risks (restaurant_id, created_at desc);
create index if not exists order_risks_ip_idx on public.order_risks (client_ip, created_at desc);

alter table public.order_risks enable row level security;
revoke all on public.order_risks from anon, authenticated;

-- Adres IP gościa z nagłówków zapytania (PostgREST).
create or replace function private.request_ip()
returns inet
language plpgsql
stable
set search_path = ''
as $$
declare
  v_headers json;
  v_ip text;
begin
  begin
    v_headers := nullif(current_setting('request.headers', true), '')::json;
  exception when others then
    return null;
  end;
  if v_headers is null then
    return null;
  end if;
  v_ip := coalesce(
    nullif(btrim(split_part(v_headers ->> 'x-forwarded-for', ',', 1)), ''),
    nullif(btrim(v_headers ->> 'cf-connecting-ip'), ''),
    nullif(btrim(v_headers ->> 'x-real-ip'), '')
  );
  begin
    return v_ip::inet;
  exception when others then
    return null;
  end;
end;
$$;

create or replace function private.fraud_flag(p_code text, p_points int, p_text text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object('code', p_code, 'points', p_points, 'text', p_text)
$$;

-- Ocena zamówienia od nowa: wzorce z bazy i wynik sprawdzenia IP (jeśli już jest).
create or replace function private.fraud_assess(p_order uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  o         public.orders%rowtype;
  r         public.order_risks%rowtype;
  v_phone   text;
  v_flags   jsonb := '[]'::jsonb;
  v_total   int;
  v_items   int;
  v_top     int;
  v_top_name text;
  v_n       int;
  v_avg     numeric;
  v_created timestamptz;
  v_km      numeric;
  v_country text;
begin
  select * into o from public.orders where id = p_order;
  if not found or o.kind = 'dine_in' or o.guest_id is null then
    return;
  end if;
  select * into r from public.order_risks where order_id = p_order;
  v_phone := private.customer_phone_key(o.customer_phone);

  select coalesce(sum(i.unit_price_grosze * i.quantity), 0), coalesce(sum(i.quantity), 0)
  into v_total, v_items
  from public.order_items i where i.order_id = p_order;
  select i.quantity, i.name into v_top, v_top_name
  from public.order_items i where i.order_id = p_order
  order by i.quantity desc limit 1;

  -- 1. Ten sam gość (konto albo telefon) w całym Table: kilka zamówień z dużą ilością jednego dania.
  select count(*) into v_n
  from public.orders x
  where x.kind <> 'dine_in'
    and x.opened_at > now() - interval '24 hours'
    and (x.guest_id = o.guest_id or (v_phone is not null and private.customer_phone_key(x.customer_phone) = v_phone))
    and exists (select 1 from public.order_items i where i.order_id = x.id and i.quantity >= 5);
  if v_n >= 3 then
    v_flags := v_flags || private.fraud_flag('repeat_bulk', 40,
      format('Ten sam gość: %s zamówień w 24 h, w każdym co najmniej 5 sztuk jednego dania.', v_n));
  end if;

  -- 2. Dużo zamówień w krótkim czasie.
  select count(*) into v_n
  from public.orders x
  where x.kind <> 'dine_in'
    and x.opened_at > now() - interval '24 hours'
    and (x.guest_id = o.guest_id or (v_phone is not null and private.customer_phone_key(x.customer_phone) = v_phone));
  if v_n >= 4 then
    v_flags := v_flags || private.fraud_flag('many_orders', 20, format('%s zamówień tego gościa w 24 h.', v_n));
  end if;

  -- 3. Duża ilość w tym zamówieniu.
  if v_top >= 8 then
    v_flags := v_flags || private.fraud_flag('bulk_dish', 15, format('Dużo jednego dania: %s × %s.', v_top, v_top_name));
  end if;
  if v_items >= 15 then
    v_flags := v_flags || private.fraud_flag('bulk_order', 10, format('%s sztuk w jednym zamówieniu.', v_items));
  end if;

  -- 4. Kwota dużo wyższa niż zwykle w tym lokalu (co najmniej 10 zamówień z 90 dni).
  select avg(t.total), count(*) into v_avg, v_n
  from (
    select sum(i.unit_price_grosze * i.quantity) as total
    from public.orders x join public.order_items i on i.order_id = x.id
    where x.restaurant_id = o.restaurant_id and x.kind <> 'dine_in' and x.fulfillment = 'delivered'
      and x.opened_at > now() - interval '90 days' and x.id <> o.id
    group by x.id
  ) t;
  if v_n >= 10 and v_total >= 15000 and v_total >= 3 * v_avg then
    v_flags := v_flags || private.fraud_flag('high_value', 15,
      format('Kwota %s zł, zwykle ok. %s zł.', round(v_total / 100.0), round(v_avg / 100.0)));
  end if;

  -- 5. Nowe konto i duża kwota.
  select u.created_at into v_created from auth.users u where u.id = o.guest_id;
  if v_created > now() - interval '24 hours' and v_total >= 15000 then
    v_flags := v_flags || private.fraud_flag('new_account', 15, 'Konto założone w ostatniej dobie, duża kwota.');
  end if;

  -- 6. Nieudane albo porzucone płatności kartą przed tym zamówieniem.
  select count(*) into v_n
  from public.orders x
  where x.guest_id = o.guest_id and x.id <> o.id
    and x.payment_choice = 'card_online' and x.payment_status <> 'paid'
    and x.fulfillment in ('awaiting_payment', 'cancelled')
    and x.opened_at > now() - interval '24 hours';
  if v_n >= 2 then
    v_flags := v_flags || private.fraud_flag('payment_attempts', 25, format('%s nieudane płatności kartą w 24 h.', v_n));
  end if;

  -- 7. Odrzucone i anulowane zamówienia z 30 dni.
  select count(*) into v_n
  from public.orders x
  where x.guest_id = o.guest_id and x.id <> o.id
    and x.fulfillment in ('rejected', 'cancelled')
    and x.opened_at > now() - interval '30 days';
  if v_n >= 2 then
    v_flags := v_flags || private.fraud_flag('bad_history', 20, format('%s odrzucone albo anulowane zamówienia w 30 dniach.', v_n));
  end if;

  -- 8. Ten numer telefonu w zamówieniach innych kont.
  if v_phone is not null then
    select count(distinct x.guest_id) into v_n
    from public.orders x
    where x.guest_id is not null and x.guest_id <> o.guest_id
      and x.kind <> 'dine_in' and x.opened_at > now() - interval '30 days'
      and private.customer_phone_key(x.customer_phone) = v_phone;
    if v_n >= 2 then
      v_flags := v_flags || private.fraud_flag('shared_phone', 15, format('Ten numer w zamówieniach %s innych kont.', v_n));
    end if;
  end if;

  -- 9. Wiele kont z jednego adresu IP.
  if r.client_ip is not null then
    select count(distinct k.guest_id) into v_n
    from public.order_risks k
    where k.client_ip = r.client_ip and k.created_at > now() - interval '24 hours';
    if v_n >= 3 then
      v_flags := v_flags || private.fraud_flag('shared_ip', 20, format('Z tego adresu IP %s różne konta w 24 h.', v_n));
    end if;
  end if;

  -- 10. Adres IP z ipinfo.io.
  if r.ip_info is not null and not coalesce((r.ip_info ->> 'bogon')::boolean, false) then
    v_country := r.ip_info ->> 'country';
    if v_country is not null and v_country <> 'PL' then
      v_flags := v_flags || private.fraud_flag('ip_country', 30, format('Adres IP z innego kraju (%s).', v_country));
    end if;
    if coalesce((r.ip_info -> 'privacy' ->> 'vpn')::boolean, false)
       or coalesce((r.ip_info -> 'privacy' ->> 'proxy')::boolean, false)
       or coalesce((r.ip_info -> 'privacy' ->> 'tor')::boolean, false)
       or coalesce((r.ip_info -> 'privacy' ->> 'relay')::boolean, false)
       or coalesce((r.ip_info -> 'privacy' ->> 'hosting')::boolean, false) then
      v_flags := v_flags || private.fraud_flag('ip_privacy', 30, 'Adres IP ukrywa położenie (VPN, proxy, Tor albo serwer).');
    end if;
    v_km := (r.ip_info ->> 'distance_km')::numeric;
    if v_km > 500 then
      v_flags := v_flags || private.fraud_flag('ip_far', 30,
        format('Adres IP %s km od lokalu (%s).', round(v_km), coalesce(r.ip_info ->> 'city', '?')));
    elsif v_km > 100 then
      v_flags := v_flags || private.fraud_flag('ip_far', 15,
        format('Adres IP %s km od lokalu (%s).', round(v_km), coalesce(r.ip_info ->> 'city', '?')));
    end if;
  end if;

  insert into public.order_risks (order_id, restaurant_id, guest_id, score, flags)
  values (
    p_order, o.restaurant_id, o.guest_id,
    least(100, (select coalesce(sum((f ->> 'points')::int), 0) from jsonb_array_elements(v_flags) f)),
    v_flags
  )
  on conflict (order_id) do update
  set score = excluded.score, flags = excluded.flags;
end;
$$;

-- ---------------------------------------------------------------
-- Zamówienie z aplikacji: limity, adres IP i ocena
-- ---------------------------------------------------------------

-- Limity lokalu sprawdza trigger (guest_place_order wstawia pozycje po kolei, więc liczymy po każdej).
create or replace function private.takeaway_limits_check()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind   text;
  v_guest  uuid;
  v_max    smallint;
  v_per    smallint;
  v_items  int;
  v_dish   int;
begin
  select o.kind, o.guest_id, r.takeaway_max_items, r.takeaway_max_per_item
  into v_kind, v_guest, v_max, v_per
  from public.orders o join public.restaurants r on r.id = o.restaurant_id
  where o.id = new.order_id;
  -- Tylko zamówienia gości z aplikacji; panel wpisuje zamówienia telefoniczne bez limitu.
  if v_kind = 'dine_in' or v_guest is null or new.created_by is distinct from v_guest then
    return new;
  end if;
  if v_per is not null then
    select coalesce(sum(i.quantity), 0) into v_dish
    from public.order_items i where i.order_id = new.order_id and i.menu_item_id = new.menu_item_id;
    if v_dish > v_per then
      raise exception 'Lokal przyjmuje najwyżej % szt. jednego dania w zamówieniu („%”).', v_per, new.name;
    end if;
  end if;
  if v_max is not null then
    select coalesce(sum(i.quantity), 0) into v_items from public.order_items i where i.order_id = new.order_id;
    if v_items > v_max then
      raise exception 'Lokal przyjmuje najwyżej % szt. w jednym zamówieniu.', v_max;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists order_items_takeaway_limits on public.order_items;
create trigger order_items_takeaway_limits
  after insert or update of quantity on public.order_items
  for each row execute function private.takeaway_limits_check();

-- Nowe zamówienie gościa: zapamiętuje IP i liczy ryzyko, gdy już ma pozycje (trigger na końcu transakcji).
create or replace function private.order_risk_new()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.kind = 'dine_in' or new.guest_id is null or new.opened_by_member is not null then
    return new;
  end if;
  insert into public.order_risks (order_id, restaurant_id, guest_id, client_ip)
  values (new.id, new.restaurant_id, new.guest_id, private.request_ip())
  on conflict (order_id) do nothing;
  -- Ocena nigdy nie blokuje zamówienia.
  begin
    perform private.fraud_assess(new.id);
  exception when others then
    raise warning 'fraud_assess %: %', new.id, sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists orders_risk on public.orders;
create constraint trigger orders_risk
  after insert on public.orders
  deferrable initially deferred
  for each row execute function private.order_risk_new();

-- ---------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------

-- Dla funkcji Edge fraud-ip: adres do sprawdzenia (tylko obsługa z uprawnieniem do zamówień).
create or replace function public.panel_fraud_ip_input(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.order_risks%rowtype;
begin
  select * into r from public.order_risks where order_id = p_order_id;
  if not found then
    return null;
  end if;
  perform private.require_permission(r.restaurant_id, 'orders');
  return jsonb_build_object('ip', host(r.client_ip), 'checked', r.ip_checked_at is not null);
end;
$$;

-- Wynik z ipinfo.io: zapis, odległość od lokalu i nowa ocena.
create or replace function public.panel_fraud_apply_ip(p_order_id uuid, p_info jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r      public.order_risks%rowtype;
  v_info jsonb := coalesce(p_info, '{}'::jsonb);
  v_lat  double precision;
  v_lng  double precision;
  v_km   numeric;
begin
  select * into r from public.order_risks where order_id = p_order_id;
  if not found then
    raise exception 'Nie znaleziono zamówienia.';
  end if;
  perform private.require_permission(r.restaurant_id, 'orders');
  if r.ip_checked_at is not null then
    return;
  end if;

  begin
    v_lat := split_part(v_info ->> 'loc', ',', 1)::double precision;
    v_lng := split_part(v_info ->> 'loc', ',', 2)::double precision;
  exception when others then
    v_lat := null;
  end;
  if v_lat is not null then
    select round((extensions.st_distance(
      rs.location, extensions.st_setsrid(extensions.st_makepoint(v_lng, v_lat), 4326)::extensions.geography
    ) / 1000)::numeric)
    into v_km
    from public.restaurants rs where rs.id = r.restaurant_id and rs.location is not null;
  end if;

  update public.order_risks
  set ip_info = jsonb_strip_nulls(jsonb_build_object(
        'city', v_info ->> 'city',
        'region', v_info ->> 'region',
        'country', v_info ->> 'country',
        'loc', v_info ->> 'loc',
        'org', v_info ->> 'org',
        'bogon', v_info -> 'bogon',
        'privacy', v_info -> 'privacy',
        'distance_km', v_km
      )),
      ip_checked_at = now()
  where order_id = p_order_id;
  perform private.fraud_assess(p_order_id);
end;
$$;

-- Ocena zamówień z aplikacji od [p_from] (Dostawy: ostatnie 2 dni, Analiza oszustw: 30 dni).
create or replace function public.panel_order_risks(p_restaurant_id uuid, p_from timestamptz)
returns table (
  order_id uuid,
  number int,
  kind text,
  fulfillment text,
  opened_at timestamptz,
  customer_name text,
  customer_phone text,
  total_grosze bigint,
  payment_choice text,
  client_ip text,
  ip_info jsonb,
  ip_checked boolean,
  score smallint,
  flags jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_permission(p_restaurant_id, 'orders');
  return query
  select o.id, o.number, o.kind, o.fulfillment, o.opened_at, o.customer_name, o.customer_phone,
         coalesce((select sum(i.unit_price_grosze * i.quantity) from public.order_items i where i.order_id = o.id), 0)
           + o.delivery_fee_grosze,
         o.payment_choice, host(k.client_ip), k.ip_info, k.ip_checked_at is not null, k.score, k.flags
  from public.order_risks k
  join public.orders o on o.id = k.order_id
  where k.restaurant_id = p_restaurant_id
    and o.opened_at >= p_from
    and o.fulfillment <> 'draft'
  order by o.opened_at desc
  limit 500;
end;
$$;

revoke all on function public.panel_fraud_ip_input(uuid) from public, anon;
revoke all on function public.panel_fraud_apply_ip(uuid, jsonb) from public, anon;
revoke all on function public.panel_order_risks(uuid, timestamptz) from public, anon;
grant execute on function public.panel_fraud_ip_input(uuid) to authenticated;
grant execute on function public.panel_fraud_apply_ip(uuid, jsonb) to authenticated;
grant execute on function public.panel_order_risks(uuid, timestamptz) to authenticated;

-- Nowe uprawnienie „Analiza oszustw” (zakładka w Management).
create or replace function private.all_permissions()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['reservations', 'floor', 'floor_edit', 'orders', 'orders_close', 'orders_cancel', 'deliveries', 'fleet',
               'kitchen', 'kitchen_settings', 'serving', 'staff', 'staff_logins', 'schedule', 'timesheet', 'positions',
               'announcements',
               'profile', 'menu', 'menu_edit', 'menu_availability', 'inventory_edit', 'inventory_count',
               'customers', 'reviews', 'stats', 'revenue', 'day_close', 'discounts', 'export', 'fraud']
$$;

update public.staff_positions
set permissions = array_append(permissions, 'fraud')
where not ('fraud' = any (permissions))
  and ('day_close' = any (permissions) or 'staff' = any (permissions));
