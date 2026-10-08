-- Zamówienia na godzinę (na wynos i z dostawą), z aplikacji gościa i z panelu.
-- Kuchnia dostaje takie zamówienie z wyprzedzeniem ustawionym w „Kuchnia” → ustawienia, osobno dla odbioru
-- osobistego i dostawy. Do tego czasu bilecik czeka w pasku „Zaplanowane” na ekranie kuchni, dostawca nie jest
-- przydzielany, a zamówienie nie liczy się w kolejce dostawców.
--
-- orders.scheduled_for: godzina, na którą gość chce zamówienie (odbiór albo dostawa). Null: jak najszybciej.
-- orders.kitchen_at: przyjęte zamówienie na godzinę, które jeszcze nie weszło do kuchni (pozycje mają sent_at
-- równe tej chwili). Co minutę private.release_scheduled() czyści je po czasie, co odpala przydział dostawcy.

alter table public.orders
  add column scheduled_for timestamptz,
  add column kitchen_at timestamptz;

create index orders_kitchen_at on public.orders (kitchen_at) where kitchen_at is not null;

alter table public.restaurants
  add column kitchen_lead_pickup_min smallint not null default 20 check (kitchen_lead_pickup_min between 0 and 240),
  add column kitchen_lead_delivery_min smallint not null default 40 check (kitchen_lead_delivery_min between 0 and 240);

grant select (kitchen_lead_pickup_min, kitchen_lead_delivery_min) on public.restaurants to anon, authenticated;

-- ---------------------------------------------------------------
-- Sprawdzenie godziny
-- ---------------------------------------------------------------

-- Gość: nie wcześniej niż za czas wyprzedzenia kuchni (co najmniej 15 minut), w godzinach otwarcia, do 7 dni.
-- Panel: dowolna chwila w przyszłości, do 7 dni (pracownik wie, co ustalił z klientem).
create or replace function private.check_scheduled(
  p_restaurant_id  uuid,
  p_kind           text,
  p_when           timestamptz,
  p_guest          boolean
)
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_r      public.restaurants%rowtype;
  v_when   timestamptz := date_trunc('minute', p_when);
  v_min    timestamptz;
  v_local  timestamp;
begin
  if p_when is null then
    return null;
  end if;
  if p_kind not in ('delivery', 'pickup') then
    raise exception 'Na godzinę można zamówić tylko na wynos albo z dostawą.';
  end if;
  select * into v_r from public.restaurants where id = p_restaurant_id;
  if v_when > now() + interval '7 days' then
    raise exception 'Na godzinę można zamówić najwyżej 7 dni naprzód.';
  end if;
  if not p_guest then
    if v_when <= now() then
      raise exception 'Wybierz godzinę, która jeszcze nie minęła.';
    end if;
    return v_when;
  end if;

  v_min := now() + make_interval(mins => greatest(15,
    case when p_kind = 'delivery' then v_r.kitchen_lead_delivery_min else v_r.kitchen_lead_pickup_min end));
  if v_when < v_min then
    raise exception 'Na tę godzinę lokal nie zdąży. Najwcześniej na %.',
      to_char(v_min at time zone coalesce(v_r.timezone, 'Europe/Warsaw'), 'HH24:MI');
  end if;
  v_local := v_when at time zone coalesce(v_r.timezone, 'Europe/Warsaw');
  if exists (select 1 from public.opening_hours where restaurant_id = p_restaurant_id)
     and not exists (
       select 1 from public.opening_hours h
       where h.restaurant_id = p_restaurant_id
         and h.weekday = extract(isodow from v_local)
         and v_local::time between h.opens and h.closes
     ) then
    raise exception 'Lokal jest wtedy zamknięty. Wybierz godzinę otwarcia.';
  end if;
  return v_when;
end;
$$;

-- Wysłanie pozycji na kuchnię przy przyjęciu: od razu albo (na godzinę) o scheduled_for minus wyprzedzenie.
-- Przy zmianie godziny przyjętego, a jeszcze czekającego zamówienia przesuwa też już zaplanowane pozycje.
create or replace function private.takeaway_plan(p_order_id uuid, p_minutes integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order  public.orders%rowtype;
  v_lead   integer;
  v_at     timestamptz;
begin
  select * into v_order from public.orders where id = p_order_id;
  select case when v_order.kind = 'delivery' then r.kitchen_lead_delivery_min else r.kitchen_lead_pickup_min end
  into v_lead
  from public.restaurants r where r.id = v_order.restaurant_id;
  if v_order.scheduled_for is not null and v_order.scheduled_for - make_interval(mins => v_lead) > now() then
    v_at := v_order.scheduled_for - make_interval(mins => v_lead);
  end if;

  update public.order_items i
  set status = case
        when i.status <> 'new' then i.status
        when coalesce((select m.show_in_kitchen from public.menu_items m where m.id = i.menu_item_id), true)
          then 'sent'::public.order_item_status
        else 'ready'::public.order_item_status
      end,
      sent_at = coalesce(v_at, now())
  where i.order_id = p_order_id
    and (i.status = 'new' or (v_order.kitchen_at is not null and i.status in ('sent', 'ready')));

  update public.orders
  set kitchen_at = v_at,
      promised_at = case
        when v_order.scheduled_for > now() then v_order.scheduled_for
        else now() + make_interval(mins => greatest(5, least(coalesce(p_minutes, 30), 240)))
      end
  where id = p_order_id;
end;
$$;

-- Co minutę (pg_cron): zaplanowane zamówienia, których czas wejścia do kuchni minął. Wyczyszczenie kitchen_at
-- odświeża ekrany panelu i przez trigger orders_dispatch przydziela dostawcę.
create or replace function private.release_scheduled()
returns void
language sql
security definer
set search_path = ''
as $$
  update public.orders set kitchen_at = null where kitchen_at is not null and kitchen_at <= now();
$$;

-- ---------------------------------------------------------------
-- Gość
-- ---------------------------------------------------------------

drop function public.guest_place_order(uuid, text, jsonb, text, text, text, text, text);

create function public.guest_place_order(
  p_restaurant_id  uuid,
  p_kind           text,
  p_items          jsonb,
  p_payment        text,
  p_name           text,
  p_phone          text,
  p_address        text default null,
  p_note           text default null,
  p_scheduled_for  timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r        restaurants%rowtype;
  v_order    uuid;
  v_line     jsonb;
  v_item     record;
  v_option   jsonb;
  v_price    integer;
  v_variant  text;
  v_addons   jsonb;
  v_name     text;
  v_qty      integer;
  v_total    integer := 0;
  v_fee      integer := 0;
  v_number   integer;
  v_when     timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Zaloguj się, żeby zamówić.';
  end if;
  select * into v_r from restaurants where id = p_restaurant_id and listed;
  if not found then
    raise exception 'Nie znaleziono lokalu.';
  end if;
  if v_r.plan <> 'pro' then
    raise exception 'Ten lokal nie przyjmuje zamówień w aplikacji.';
  end if;
  if p_kind not in ('delivery', 'pickup') then
    raise exception 'Wybierz dostawę albo odbiór osobisty.';
  end if;
  if p_kind = 'delivery' and not v_r.delivery_enabled then
    raise exception 'Ten lokal nie dowozi zamówień.';
  end if;
  if p_kind = 'pickup' and not v_r.pickup_enabled then
    raise exception 'Ten lokal nie przyjmuje zamówień z odbiorem osobistym.';
  end if;
  if p_payment is null or p_payment not in ('cash', 'card_online') then
    raise exception 'Wybierz formę płatności.';
  end if;
  if p_payment = 'cash' and not v_r.takeaway_cash then
    raise exception 'Ten lokal przyjmuje tylko płatność kartą online.';
  end if;
  if nullif(btrim(p_name), '') is null then
    raise exception 'Podaj imię.';
  end if;
  if nullif(btrim(p_phone), '') is null then
    raise exception 'Podaj numer telefonu.';
  end if;
  if p_kind = 'delivery' and nullif(btrim(p_address), '') is null then
    raise exception 'Podaj adres dostawy.';
  end if;
  v_when := private.check_scheduled(p_restaurant_id, p_kind, p_scheduled_for, true);
  p_items := coalesce(p_items, '[]'::jsonb);
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Koszyk jest pusty.';
  end if;
  if jsonb_array_length(p_items) > 50 then
    raise exception 'Za dużo pozycji w jednym zamówieniu.';
  end if;

  perform pg_advisory_xact_lock(hashtext('order-number:' || p_restaurant_id::text));
  select coalesce(max(number), 0) + 1 into v_number
  from orders
  where restaurant_id = p_restaurant_id
    and kind <> 'dine_in'
    and (opened_at at time zone v_r.timezone)::date = (now() at time zone v_r.timezone)::date;

  v_fee := case when p_kind = 'delivery' then v_r.delivery_fee_grosze else 0 end;

  insert into orders (
    restaurant_id, kind, guest_id, number, customer_name, customer_phone, delivery_address, delivery_note,
    delivery_fee_grosze, payment_choice, payment_status, fulfillment, opened_by, scheduled_for
  )
  values (
    p_restaurant_id, p_kind, auth.uid(), v_number, left(btrim(p_name), 80), left(btrim(p_phone), 20),
    case when p_kind = 'delivery' then left(btrim(p_address), 200) end, left(nullif(btrim(p_note), ''), 300),
    v_fee, p_payment,
    case when p_payment = 'card_online' then 'pending' else 'unpaid' end,
    case when p_payment = 'card_online' then 'awaiting_payment' else 'placed' end,
    auth.uid(), v_when
  )
  returning id into v_order;

  for v_line in select * from jsonb_array_elements(p_items) loop
    select i.id, i.name, i.price_grosze, i.variants, i.addons, i.vat_rate, i.available, s.restaurant_id
    into v_item
    from menu_items i
    join menu_sections s on s.id = i.section_id
    where i.id = (v_line ->> 'menu_item_id')::uuid;
    if not found or v_item.restaurant_id <> p_restaurant_id then
      raise exception 'Nie znaleziono pozycji w menu.';
    end if;
    if not v_item.available then
      raise exception '„%” jest chwilowo niedostępne.', v_item.name;
    end if;
    v_qty := coalesce((v_line ->> 'quantity')::integer, 1);
    if v_qty not between 1 and 99 then
      raise exception 'Ilość od 1 do 99.';
    end if;

    v_variant := null;
    v_addons := '[]'::jsonb;
    if jsonb_array_length(v_item.variants) > 0 then
      select o into v_option from jsonb_array_elements(v_item.variants) o where o ->> 'name' = v_line ->> 'variant';
      if v_option is null then
        raise exception 'Wybierz wariant pozycji „%”.', v_item.name;
      end if;
      v_price := (v_option ->> 'price_grosze')::integer;
      v_variant := v_option ->> 'name';
    else
      v_price := v_item.price_grosze;
    end if;

    for v_name in select jsonb_array_elements_text(coalesce(v_line -> 'addons', '[]'::jsonb)) loop
      v_option := null;
      select o into v_option from jsonb_array_elements(v_item.addons) o where o ->> 'name' = v_name;
      if v_option is null then
        raise exception 'Pozycja „%” nie ma dodatku „%”.', v_item.name, v_name;
      end if;
      v_price := v_price + (v_option ->> 'price_grosze')::integer;
      v_addons := v_addons || jsonb_build_array(v_option);
    end loop;

    insert into order_items (
      order_id, restaurant_id, menu_item_id, name, variant, addons, unit_price_grosze, vat_rate, quantity, note, course, created_by
    )
    values (
      v_order, p_restaurant_id, v_item.id, v_item.name, v_variant, v_addons, v_price, v_item.vat_rate, v_qty,
      left(nullif(btrim(v_line ->> 'note'), ''), 200), 1, auth.uid()
    );
    v_total := v_total + v_price * v_qty;
  end loop;

  if p_kind = 'delivery' and v_total < v_r.delivery_min_grosze then
    raise exception 'Minimalne zamówienie z dostawą to % zł.',
      replace(to_char(v_r.delivery_min_grosze / 100.0, 'FM999990.00'), '.', ',');
  end if;

  return jsonb_build_object('id', v_order, 'number', v_number, 'total_grosze', v_total + v_fee);
end;
$$;

-- ---------------------------------------------------------------
-- Panel: przyjęcie, nowe zamówienie, zmiana danych
-- ---------------------------------------------------------------

create or replace function public.panel_takeaway_accept(p_order_id uuid, p_minutes integer, p_member_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
begin
  v_order := private.takeaway_order(p_order_id);
  perform private.check_member(v_order.restaurant_id, p_member_id);
  if v_order.fulfillment <> 'placed' then
    raise exception 'To zamówienie jest już przyjęte albo odwołane.';
  end if;
  -- Najpierw plan (kitchen_at), potem stan: trigger przydziału dostawcy pomija zamówienia czekające na kuchnię.
  perform private.takeaway_plan(p_order_id, p_minutes);
  update orders
  set fulfillment = 'accepted',
      accepted_at = now(),
      opened_by_member = coalesce(opened_by_member, p_member_id)
  where id = p_order_id;
end;
$$;

create or replace function public.panel_takeaway_submit(p_order_id uuid, p_minutes integer, p_member_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
begin
  v_order := private.takeaway_order(p_order_id);
  perform private.check_member(v_order.restaurant_id, p_member_id);
  if v_order.fulfillment <> 'draft' then
    raise exception 'To zamówienie jest już przyjęte.';
  end if;
  if not exists (select 1 from order_items where order_id = p_order_id and status <> 'cancelled') then
    raise exception 'Dodaj dania z menu.';
  end if;
  if v_order.scheduled_for is not null and v_order.scheduled_for <= now() then
    raise exception 'Godzina zamówienia już minęła. Zmień ją w danych zamówienia.';
  end if;
  perform private.takeaway_plan(p_order_id, p_minutes);
  update orders
  set fulfillment = 'accepted',
      accepted_at = now(),
      opened_by_member = coalesce(opened_by_member, p_member_id)
  where id = p_order_id;
end;
$$;

-- p_customer może mieć „scheduled_for” (ISO, null = jak najszybciej).
create or replace function public.panel_takeaway_create(
  p_restaurant_id  uuid,
  p_kind           text,
  p_customer       jsonb,
  p_member_id      uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r       restaurants%rowtype;
  v_c       record;
  v_number  integer;
  v_id      uuid;
  v_when    timestamptz;
begin
  perform private.require_permission(p_restaurant_id, 'orders');
  perform private.check_member(p_restaurant_id, p_member_id);
  select * into v_r from restaurants where id = p_restaurant_id;
  if not found then
    raise exception 'Nie znaleziono lokalu.';
  end if;
  if v_r.plan <> 'pro' then
    raise exception 'Zamówienia na wynos są w planie Pro.';
  end if;
  if p_kind not in ('delivery', 'pickup') then
    raise exception 'Wybierz dostawę albo odbiór osobisty.';
  end if;
  select * into v_c from private.takeaway_customer(p_kind, p_customer);
  v_when := private.check_scheduled(p_restaurant_id, p_kind, nullif(p_customer ->> 'scheduled_for', '')::timestamptz, false);

  perform pg_advisory_xact_lock(hashtext('order-number:' || p_restaurant_id::text));
  select coalesce(max(number), 0) + 1 into v_number
  from orders
  where restaurant_id = p_restaurant_id
    and kind <> 'dine_in'
    and (opened_at at time zone v_r.timezone)::date = (now() at time zone v_r.timezone)::date;

  insert into orders (
    restaurant_id, kind, number, customer_name, customer_company, customer_nip, customer_phone,
    address_street, address_house, address_city, delivery_address, delivery_note, staff_note,
    delivery_fee_grosze, payment_choice, payment_status, fulfillment, opened_by, opened_by_member, scheduled_for
  )
  values (
    p_restaurant_id, p_kind, v_number, left(coalesce(v_c.name, v_c.company), 80), v_c.company, v_c.nip, v_c.phone,
    v_c.street, v_c.house, v_c.city,
    case when p_kind = 'delivery' then left(v_c.street || ' ' || v_c.house || ', ' || v_c.city, 200) end,
    v_c.note, v_c.staff_note,
    case when p_kind = 'delivery' then v_r.delivery_fee_grosze else 0 end,
    case when v_c.paid then 'prepaid' else 'cash' end,
    case when v_c.paid then 'paid' else 'unpaid' end,
    'draft', auth.uid(), p_member_id, v_when
  )
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'number', v_number);
end;
$$;

-- Godzinę zmienia się, dopóki zamówienie nie weszło do kuchni. Bez klucza „scheduled_for” (starszy panel)
-- godzina zostaje bez zmian.
create or replace function public.panel_takeaway_update(p_order_id uuid, p_customer jsonb, p_member_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
  v_c      record;
  v_when   timestamptz;
begin
  v_order := private.takeaway_order(p_order_id);
  perform private.check_member(v_order.restaurant_id, p_member_id);
  if v_order.guest_id is not null then
    raise exception 'Dane zamówienia z aplikacji Table zmienia gość.';
  end if;
  if v_order.status <> 'open' or v_order.fulfillment not in ('draft', 'placed', 'accepted', 'ready') then
    raise exception 'Zamówienie wyjechało już z lokalu.';
  end if;
  select * into v_c from private.takeaway_customer(v_order.kind, p_customer);
  update orders
  set customer_name = left(coalesce(v_c.name, v_c.company), 80),
      customer_company = v_c.company,
      customer_nip = v_c.nip,
      customer_phone = v_c.phone,
      address_street = v_c.street,
      address_house = v_c.house,
      address_city = v_c.city,
      delivery_address = case when kind = 'delivery' then left(v_c.street || ' ' || v_c.house || ', ' || v_c.city, 200) end,
      delivery_note = v_c.note,
      staff_note = v_c.staff_note,
      payment_choice = case when v_c.paid then 'prepaid' else 'cash' end,
      payment_status = case when v_c.paid then 'paid' else 'unpaid' end
  where id = p_order_id;

  if p_customer ? 'scheduled_for' then
    v_when := date_trunc('minute', nullif(p_customer ->> 'scheduled_for', '')::timestamptz);
    if v_when is distinct from v_order.scheduled_for then
      if v_order.fulfillment not in ('draft', 'placed')
         and not (v_order.fulfillment = 'accepted' and coalesce(v_order.kitchen_at > now(), false)) then
        raise exception 'Zamówienie jest już w kuchni. Godziny nie da się zmienić.';
      end if;
      v_when := private.check_scheduled(v_order.restaurant_id, v_order.kind, v_when, false);
      update orders set scheduled_for = v_when where id = p_order_id;
      -- Przyjęte: przesuwa pozycje. „Jak najszybciej” czyści kitchen_at, a trigger przydziela dostawcę.
      if v_order.fulfillment = 'accepted' then
        perform private.takeaway_plan(p_order_id, null);
      end if;
    end if;
  end if;
end;
$$;

-- ---------------------------------------------------------------
-- Ustawienia kuchni: wyprzedzenie zamówień na godzinę
-- ---------------------------------------------------------------

drop function public.panel_set_kitchen_config(uuid, integer, integer, uuid[]);

create function public.panel_set_kitchen_config(
  p_restaurant_id    uuid,
  p_warn_minutes     integer,
  p_late_minutes     integer,
  p_hidden_items     uuid[],
  p_lead_pickup      integer default null,
  p_lead_delivery    integer default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (
    private.has_staff_role(p_restaurant_id, 'manager')
    or private.has_permission(p_restaurant_id, 'kitchen')
  ) then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;
  if p_warn_minutes is null or p_late_minutes is null or p_late_minutes <= p_warn_minutes then
    raise exception 'Czas „czerwony” musi być dłuższy niż „żółty”.';
  end if;
  if p_lead_pickup not between 0 and 240 or p_lead_delivery not between 0 and 240 then
    raise exception 'Wyprzedzenie od 0 do 240 minut.';
  end if;

  update restaurants
  set kitchen_warn_minutes = p_warn_minutes,
      kitchen_late_minutes = p_late_minutes,
      kitchen_lead_pickup_min = coalesce(p_lead_pickup, kitchen_lead_pickup_min),
      kitchen_lead_delivery_min = coalesce(p_lead_delivery, kitchen_lead_delivery_min)
  where id = p_restaurant_id;

  update menu_items i
  set show_in_kitchen = not (i.id = any (coalesce(p_hidden_items, '{}')))
  from menu_sections s
  where s.id = i.section_id and s.restaurant_id = p_restaurant_id;
end;
$$;

-- ---------------------------------------------------------------
-- Dostawcy: zamówienie czekające na kuchnię nie dostaje dostawcy
-- ---------------------------------------------------------------

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
    select q.member_id into v_courier from private.courier_queue(p_restaurant_id) q where not q.busy limit 1;
    exit when v_courier is null;
    update public.orders set courier_member = v_courier, courier_assigned_at = now()
    where courier_member is null
      and (id = v_order.id or id in (select private.course_waiting(v_order.course_id)));
  end loop;
end;
$$;

create or replace function private.orders_dispatch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.kind = 'delivery'
     and new.courier_member is null
     and new.kitchen_at is null
     and new.fulfillment in ('accepted', 'ready')
     and (old.fulfillment is distinct from new.fulfillment
          or old.courier_member is not null
          or old.kitchen_at is not null) then
    perform private.dispatch_deliveries(new.restaurant_id);
  end if;
  return new;
end;
$$;

drop trigger orders_dispatch on public.orders;
create trigger orders_dispatch
  after update of fulfillment, courier_member, kitchen_at on public.orders
  for each row execute function private.orders_dispatch();

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
    'queue', coalesce((
      select jsonb_agg(jsonb_build_object('member_id', q.member_id, 'name', q.name, 'busy', q.busy, 'since', q.waiting_since))
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

-- ---------------------------------------------------------------
-- Co minutę: zaplanowane zamówienia wchodzą do kuchni
-- ---------------------------------------------------------------

create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule('table_release_scheduled', '* * * * *', 'select private.release_scheduled()');

-- ---------------------------------------------------------------
-- Uprawnienia
-- ---------------------------------------------------------------

revoke execute on function private.check_scheduled(uuid, text, timestamptz, boolean) from public, anon;
revoke execute on function private.takeaway_plan(uuid, integer) from public, anon, authenticated;
revoke execute on function private.release_scheduled() from public, anon, authenticated;
revoke execute on function public.guest_place_order(uuid, text, jsonb, text, text, text, text, text, timestamptz) from public, anon;
revoke execute on function public.panel_set_kitchen_config(uuid, integer, integer, uuid[], integer, integer) from public, anon;

grant execute on function private.check_scheduled(uuid, text, timestamptz, boolean) to authenticated;
grant execute on function public.guest_place_order(uuid, text, jsonb, text, text, text, text, text, timestamptz) to authenticated;
grant execute on function public.panel_set_kitchen_config(uuid, integer, integer, uuid[], integer, integer) to authenticated;
