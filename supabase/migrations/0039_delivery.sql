-- Table · migracja 0039
-- Dostawy i odbiór osobisty.
-- 1. Lokal włącza dostawę i/lub odbiór osobisty, gotówkę (karta online jest zawsze), opłatę za dostawę,
--    minimalne zamówienie i opis obszaru dostawy („Dane lokalu”).
-- 2. Gość zamawia w aplikacji Table (orders.kind = delivery/pickup). Płatność: gotówka (u kuriera albo przy odbiorze)
--    albo karta online. Operatora płatności jeszcze nie ma: tryb testowy (private.app_settings.payments_mode = test)
--    opłaca zamówienie bez pobierania pieniędzy.
-- 3. Panel przyjmuje zamówienie z czasem przygotowania (pozycje idą na kuchnię), oznacza „gotowe”, wydaje odbiór osobisty.
-- 4. Dostawcy (stanowisko z uprawnieniem „deliveries”, np. Dostawca) w aplikacji Table for employees: kolejka według
--    czasu czekania: kto pierwszy zaczął zmianę (albo najdawniej skończył kurs), ten dostaje pierwszy kurs.
--    Kurs można oddać konkretnej osobie albo następnemu w kolejce, dopóki nie odebrało się zamówienia z lokalu.

-- ---------------------------------------------------------------
-- Ustawienia
-- ---------------------------------------------------------------

alter table public.restaurants
  add column delivery_enabled boolean not null default false,
  add column pickup_enabled boolean not null default false,
  add column takeaway_cash boolean not null default true,
  add column delivery_fee_grosze integer not null default 0 check (delivery_fee_grosze between 0 and 100000),
  add column delivery_min_grosze integer not null default 0 check (delivery_min_grosze between 0 and 1000000),
  add column delivery_area text check (char_length(delivery_area) <= 120);

create table private.app_settings (
  key    text primary key,
  value  text not null
);

-- test: bez operatora płatności karta online opłaca zamówienie od razu (bez pobierania pieniędzy).
insert into private.app_settings (key, value) values ('payments_mode', 'test');

create or replace function public.payments_test_mode()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select value = 'test' from private.app_settings where key = 'payments_mode'), true)
$$;

-- ---------------------------------------------------------------
-- Zamówienia na wynos
-- ---------------------------------------------------------------

alter table public.orders
  add column kind text not null default 'dine_in' check (kind in ('dine_in', 'delivery', 'pickup')),
  add column guest_id uuid references auth.users (id) on delete set null,
  -- Numer zamówienia na wynos w danym dniu lokalu, np. #12.
  add column number integer,
  add column customer_name text check (char_length(customer_name) <= 80),
  add column customer_phone text check (char_length(customer_phone) <= 20),
  add column delivery_address text check (char_length(delivery_address) <= 200),
  add column delivery_note text check (char_length(delivery_note) <= 300),
  add column delivery_fee_grosze integer not null default 0 check (delivery_fee_grosze >= 0),
  -- Wybór gościa: gotówka przy dostawie/odbiorze albo karta online.
  add column payment_choice text check (payment_choice in ('cash', 'card_online')),
  add column payment_status text not null default 'unpaid' check (payment_status in ('unpaid', 'pending', 'paid')),
  add column payment_test boolean not null default false,
  -- awaiting_payment → placed → accepted → ready → on_the_way (tylko dostawa) → delivered; albo rejected/cancelled.
  add column fulfillment text check (fulfillment in (
    'awaiting_payment', 'placed', 'accepted', 'ready', 'on_the_way', 'delivered', 'rejected', 'cancelled'
  )),
  add column promised_at timestamptz,
  add column accepted_at timestamptz,
  add column ready_at timestamptz,
  add column picked_up_at timestamptz,
  add column delivered_at timestamptz,
  add column courier_member uuid references public.staff_members (id) on delete set null,
  add column courier_assigned_at timestamptz,
  add column reject_reason text check (char_length(reject_reason) <= 200),
  add constraint orders_kind_fulfillment_check check ((kind = 'dine_in') = (fulfillment is null));

create index orders_takeaway_idx on public.orders (restaurant_id, fulfillment) where kind <> 'dine_in';
create index orders_guest_idx on public.orders (guest_id, opened_at desc) where guest_id is not null;
create index orders_courier_idx on public.orders (courier_member) where courier_member is not null;

-- Kiedy dostawca ostatnio wrócił do kolejki (koniec kursu albo oddanie kursu).
alter table public.staff_members add column courier_ready_at timestamptz;

create policy "Gość widzi swoje zamówienia"
  on public.orders for select to authenticated
  using (guest_id = (select auth.uid()));

create policy "Gość widzi pozycje swoich zamówień"
  on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_items.order_id and o.guest_id = (select auth.uid())));

create policy "Dostawcy widzą dostawy lokalu"
  on public.orders for select to authenticated
  using (kind = 'delivery' and private.has_permission(restaurant_id, 'deliveries'));

create policy "Dostawcy widzą pozycje dostaw"
  on public.order_items for select to authenticated
  using (
    private.has_permission(restaurant_id, 'deliveries')
    and exists (select 1 from public.orders o where o.id = order_items.order_id and o.kind = 'delivery')
  );

-- ---------------------------------------------------------------
-- Kolejka dostawców
-- ---------------------------------------------------------------

-- Dostawcy na zmianie: stanowisko z uprawnieniem „deliveries” wpisanym wprost (bez „ALL”, żeby kierownik
-- z pełnym dostępem nie dostawał kursów). Kolejność: wolni przed zajętymi, potem kto dłużej czeka.
create or replace function private.courier_queue(p_restaurant_id uuid)
returns table (member_id uuid, name text, waiting_since timestamptz, busy boolean)
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
         )
  from public.staff_members m
  join public.staff_shifts s on s.member_id = m.id and s.ended_at is null
  join public.staff_positions p on p.id = m.position_id
  where m.restaurant_id = p_restaurant_id
    and m.active
    and p.system_key is distinct from 'all'
    and 'deliveries' = any (p.permissions)
  order by 4, 3, s.started_at
$$;

-- Przydziela czekające dostawy wolnym dostawcom, od najstarszego zamówienia.
create or replace function private.dispatch_deliveries(p_restaurant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order    uuid;
  v_courier  uuid;
begin
  perform pg_advisory_xact_lock(hashtext('dispatch:' || p_restaurant_id::text));
  for v_order in
    select o.id from public.orders o
    where o.restaurant_id = p_restaurant_id
      and o.kind = 'delivery'
      and o.courier_member is null
      and o.fulfillment in ('accepted', 'ready')
    order by o.accepted_at nulls last, o.opened_at
  loop
    select q.member_id into v_courier from private.courier_queue(p_restaurant_id) q where not q.busy limit 1;
    exit when v_courier is null;
    update public.orders set courier_member = v_courier, courier_assigned_at = now() where id = v_order;
  end loop;
end;
$$;

-- Dostawa przyjęta, gotowa albo zwolniona przez dostawcę: szukamy dla niej dostawcy.
create or replace function private.orders_dispatch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.kind = 'delivery'
     and new.courier_member is null
     and new.fulfillment in ('accepted', 'ready')
     and (old.fulfillment is distinct from new.fulfillment or old.courier_member is not null) then
    perform private.dispatch_deliveries(new.restaurant_id);
  end if;
  return new;
end;
$$;

create trigger orders_dispatch
  after update of fulfillment, courier_member on public.orders
  for each row execute function private.orders_dispatch();

-- Początek zmiany: dostawca wchodzi do kolejki. Koniec zmiany: jego kursy jeszcze nieodebrane z lokalu
-- wracają do kolejki (trigger zamówień przydzieli je innym).
create or replace function private.shifts_dispatch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform private.dispatch_deliveries(new.restaurant_id);
  elsif old.ended_at is null and new.ended_at is not null then
    update public.orders
    set courier_member = null, courier_assigned_at = null
    where courier_member = new.member_id and fulfillment in ('accepted', 'ready');
  end if;
  return new;
end;
$$;

create trigger staff_shifts_dispatch
  after insert or update of ended_at on public.staff_shifts
  for each row execute function private.shifts_dispatch();

-- ---------------------------------------------------------------
-- Gość: zamówienie, płatność testowa, odwołanie
-- ---------------------------------------------------------------

create or replace function public.guest_place_order(
  p_restaurant_id  uuid,
  p_kind           text,
  p_items          jsonb,
  p_payment        text,
  p_name           text,
  p_phone          text,
  p_address        text default null,
  p_note           text default null
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
    delivery_fee_grosze, payment_choice, payment_status, fulfillment, opened_by
  )
  values (
    p_restaurant_id, p_kind, auth.uid(), v_number, left(btrim(p_name), 80), left(btrim(p_phone), 20),
    case when p_kind = 'delivery' then left(btrim(p_address), 200) end, left(nullif(btrim(p_note), ''), 300),
    v_fee, p_payment,
    case when p_payment = 'card_online' then 'pending' else 'unpaid' end,
    case when p_payment = 'card_online' then 'awaiting_payment' else 'placed' end,
    auth.uid()
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

-- Tryb testowy płatności kartą online: zamówienie jest od razu opłacone, bez pobierania pieniędzy.
-- Po podpięciu operatora płatności (payments_mode = live) opłacenie potwierdzi operator, nie aplikacja.
create or replace function public.guest_pay_order_test(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
begin
  if not public.payments_test_mode() then
    raise exception 'Płatności testowe są wyłączone.';
  end if;
  select * into v_order from orders where id = p_order_id and guest_id = auth.uid() for update;
  if not found then
    raise exception 'Nie znaleziono zamówienia.';
  end if;
  if v_order.payment_status = 'paid' then
    return;
  end if;
  if v_order.payment_choice <> 'card_online' or v_order.fulfillment <> 'awaiting_payment' then
    raise exception 'Tego zamówienia nie można już opłacić.';
  end if;
  update orders set payment_status = 'paid', payment_test = true, fulfillment = 'placed' where id = p_order_id;
end;
$$;

-- Gość odwołuje zamówienie, dopóki lokal go nie przyjął.
create or replace function public.guest_cancel_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
begin
  select * into v_order from orders where id = p_order_id and guest_id = auth.uid() for update;
  if not found then
    raise exception 'Nie znaleziono zamówienia.';
  end if;
  if v_order.fulfillment not in ('awaiting_payment', 'placed') then
    raise exception 'Lokal już przyjął zamówienie. Zadzwoń do lokalu, żeby je odwołać.';
  end if;
  update order_items set status = 'cancelled' where order_id = p_order_id;
  update orders set fulfillment = 'cancelled', status = 'cancelled', closed_at = now() where id = p_order_id;
end;
$$;

-- ---------------------------------------------------------------
-- Panel: przyjęcie, odrzucenie, gotowe, wydanie, przydział dostawcy
-- ---------------------------------------------------------------

create or replace function private.takeaway_order(p_order_id uuid)
returns public.orders
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_order  public.orders%rowtype;
begin
  select * into v_order from public.orders where id = p_order_id and kind <> 'dine_in';
  if not found then
    raise exception 'Nie znaleziono zamówienia.';
  end if;
  perform private.require_permission(v_order.restaurant_id, 'orders');
  return v_order;
end;
$$;

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
  -- Pozycje idą na kuchnię (napoje bez kuchni od razu „do wydania”), jak przy „Wyślij” w Zamówieniach.
  update order_items i
  set status = case
        when coalesce((select m.show_in_kitchen from menu_items m where m.id = i.menu_item_id), true)
          then 'sent'::order_item_status
        else 'ready'::order_item_status
      end,
      sent_at = now()
  where i.order_id = p_order_id and i.status = 'new';
  update orders
  set fulfillment = 'accepted',
      accepted_at = now(),
      promised_at = now() + make_interval(mins => greatest(5, least(coalesce(p_minutes, 30), 240))),
      opened_by_member = coalesce(opened_by_member, p_member_id)
  where id = p_order_id;
end;
$$;

create or replace function public.panel_takeaway_reject(p_order_id uuid, p_reason text default null, p_member_id uuid default null)
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
  if v_order.fulfillment not in ('placed', 'accepted', 'ready') then
    raise exception 'Tego zamówienia nie można już odrzucić.';
  end if;
  update order_items set status = 'cancelled' where order_id = p_order_id;
  update orders
  set fulfillment = 'rejected', status = 'cancelled', closed_at = now(), closed_by = auth.uid(),
      closed_by_member = p_member_id, reject_reason = left(nullif(btrim(p_reason), ''), 200),
      courier_member = null, courier_assigned_at = null
  where id = p_order_id;
end;
$$;

create or replace function public.panel_takeaway_ready(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
begin
  v_order := private.takeaway_order(p_order_id);
  if v_order.fulfillment <> 'accepted' then
    raise exception 'Zamówienie nie jest w przygotowaniu.';
  end if;
  update orders set fulfillment = 'ready', ready_at = now() where id = p_order_id;
end;
$$;

-- Odbiór osobisty: gość odebrał i zapłacił (gotówka przy ladzie albo wcześniej kartą online).
create or replace function public.panel_takeaway_handed(p_order_id uuid, p_member_id uuid default null)
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
  if v_order.kind <> 'pickup' then
    raise exception 'Dostawę zamyka dostawca w aplikacji Table for employees.';
  end if;
  if v_order.fulfillment not in ('accepted', 'ready') then
    raise exception 'Zamówienie nie czeka na odbiór.';
  end if;
  update order_items set status = 'served' where order_id = p_order_id and status in ('sent', 'ready');
  update orders
  set fulfillment = 'delivered', delivered_at = now(), status = 'paid', payment_status = 'paid',
      payment_method = case when payment_choice = 'card_online' then 'card' else 'cash' end,
      closed_at = now(), closed_by = auth.uid(), closed_by_member = p_member_id
  where id = p_order_id;
end;
$$;

-- Ręczny przydział dostawcy z panelu. Null: kurs wraca do kolejki.
create or replace function public.panel_takeaway_assign(p_order_id uuid, p_courier uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
begin
  v_order := private.takeaway_order(p_order_id);
  if v_order.kind <> 'delivery' or v_order.fulfillment not in ('accepted', 'ready') then
    raise exception 'Dostawcę zmienia się, zanim zamówienie wyjedzie z lokalu.';
  end if;
  if p_courier is not null
     and not exists (select 1 from private.courier_queue(v_order.restaurant_id) q where q.member_id = p_courier) then
    raise exception 'Ten dostawca nie jest teraz na zmianie.';
  end if;
  update orders set courier_member = p_courier, courier_assigned_at = case when p_courier is null then null else now() end
  where id = p_order_id;
end;
$$;

-- ---------------------------------------------------------------
-- Dostawca: moje kursy, odbiór, dostarczenie, oddanie kursu
-- ---------------------------------------------------------------

create or replace function private.my_member(p_member_id uuid)
returns public.staff_members
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_member  public.staff_members%rowtype;
begin
  select * into v_member from private.my_members() m where m.id = p_member_id;
  if not found then
    raise exception 'Nie ma Cię na liście pracowników tego lokalu.';
  end if;
  return v_member;
end;
$$;

create or replace function private.course_json(p_order public.orders)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_order.id,
    'number', p_order.number,
    'fulfillment', p_order.fulfillment,
    'customer_name', p_order.customer_name,
    'customer_phone', p_order.customer_phone,
    'delivery_address', p_order.delivery_address,
    'delivery_note', p_order.delivery_note,
    'payment_choice', p_order.payment_choice,
    'payment_status', p_order.payment_status,
    'payment_test', p_order.payment_test,
    'promised_at', p_order.promised_at,
    'accepted_at', p_order.accepted_at,
    'ready_at', p_order.ready_at,
    'picked_up_at', p_order.picked_up_at,
    'total_grosze', p_order.delivery_fee_grosze + coalesce((
      select sum(i.unit_price_grosze * i.quantity) from public.order_items i
      where i.order_id = p_order.id and i.status <> 'cancelled'
    ), 0),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', i.name, 'variant', i.variant, 'quantity', i.quantity, 'note', i.note,
        'addons', (select coalesce(jsonb_agg(a ->> 'name'), '[]'::jsonb) from jsonb_array_elements(i.addons) a)
      ) order by i.created_at)
      from public.order_items i where i.order_id = p_order.id and i.status <> 'cancelled'
    ), '[]'::jsonb)
  )
$$;

-- Wszystko, czego potrzebuje zakładka „Dostawy”: moje kursy, kolejka, czekające zamówienia i dzisiejsze podsumowanie.
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
    'is_courier', exists (
      select 1 from staff_positions p
      where p.id = v_member.position_id and p.system_key is distinct from 'all' and 'deliveries' = any (p.permissions)
    ),
    'queue', coalesce((
      select jsonb_agg(jsonb_build_object('member_id', q.member_id, 'name', q.name, 'busy', q.busy, 'since', q.waiting_since))
      from private.courier_queue(v_member.restaurant_id) q
    ), '[]'::jsonb),
    'waiting', (
      select count(*) from orders
      where restaurant_id = v_member.restaurant_id and kind = 'delivery' and courier_member is null
        and fulfillment in ('accepted', 'ready')
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

create or replace function public.staff_delivery_pickup(p_order_id uuid, p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member  staff_members%rowtype;
begin
  v_member := private.my_member(p_member_id);
  perform private.check_member(v_member.restaurant_id, p_member_id);
  update orders set fulfillment = 'on_the_way', picked_up_at = now()
  where id = p_order_id and courier_member = p_member_id and fulfillment in ('accepted', 'ready');
  if not found then
    raise exception 'Ten kurs nie czeka już na Ciebie w lokalu.';
  end if;
end;
$$;

create or replace function public.staff_delivery_done(p_order_id uuid, p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member  staff_members%rowtype;
  v_order   orders%rowtype;
begin
  v_member := private.my_member(p_member_id);
  select * into v_order from orders where id = p_order_id and courier_member = p_member_id for update;
  if not found or v_order.fulfillment <> 'on_the_way' then
    raise exception 'Najpierw oznacz, że odebrałeś zamówienie z lokalu.';
  end if;
  update order_items set status = 'served' where order_id = p_order_id and status in ('sent', 'ready');
  update orders
  set fulfillment = 'delivered', delivered_at = now(), status = 'paid', payment_status = 'paid',
      payment_method = case when payment_choice = 'card_online' then 'card' else 'cash' end,
      closed_at = now(), closed_by = auth.uid(), closed_by_member = p_member_id
  where id = p_order_id;
  -- Dostawca wraca na koniec kolejki i może od razu dostać kolejny kurs.
  update staff_members set courier_ready_at = now() where id = p_member_id;
  perform private.dispatch_deliveries(v_member.restaurant_id);
end;
$$;

-- Oddanie kursu: konkretnej osobie ([p_to_member]) albo następnemu wolnemu w kolejce (null).
-- Oddający trafia na koniec kolejki.
create or replace function public.staff_delivery_handover(p_order_id uuid, p_member_id uuid, p_to_member uuid default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member  staff_members%rowtype;
  v_order   orders%rowtype;
  v_to      uuid;
begin
  v_member := private.my_member(p_member_id);
  select * into v_order from orders where id = p_order_id and courier_member = p_member_id for update;
  if not found then
    raise exception 'To nie jest Twój kurs.';
  end if;
  if v_order.fulfillment not in ('accepted', 'ready') then
    raise exception 'Kurs można oddać tylko przed odebraniem zamówienia z lokalu.';
  end if;
  if p_to_member is not null then
    if p_to_member = p_member_id then
      raise exception 'Wybierz innego dostawcę.';
    end if;
    select q.member_id into v_to from private.courier_queue(v_member.restaurant_id) q where q.member_id = p_to_member;
    if v_to is null then
      raise exception 'Ten dostawca nie jest teraz na zmianie.';
    end if;
  else
    select q.member_id into v_to from private.courier_queue(v_member.restaurant_id) q
    where not q.busy and q.member_id <> p_member_id
    limit 1;
    if v_to is null then
      raise exception 'Nie ma teraz innego wolnego dostawcy. Oddaj kurs wybranej osobie albo zostaw go sobie.';
    end if;
  end if;
  update orders set courier_member = v_to, courier_assigned_at = now() where id = p_order_id;
  update staff_members set courier_ready_at = now() where id = p_member_id;
  return (select name from staff_members where id = v_to);
end;
$$;

-- ---------------------------------------------------------------
-- Uprawnienia
-- ---------------------------------------------------------------

revoke execute on function public.payments_test_mode() from public, anon;
revoke execute on function private.courier_queue(uuid) from public, anon;
revoke execute on function private.dispatch_deliveries(uuid) from public, anon, authenticated;
revoke execute on function public.guest_place_order(uuid, text, jsonb, text, text, text, text, text) from public, anon;
revoke execute on function public.guest_pay_order_test(uuid) from public, anon;
revoke execute on function public.guest_cancel_order(uuid) from public, anon;
revoke execute on function private.takeaway_order(uuid) from public, anon;
revoke execute on function public.panel_takeaway_accept(uuid, integer, uuid) from public, anon;
revoke execute on function public.panel_takeaway_reject(uuid, text, uuid) from public, anon;
revoke execute on function public.panel_takeaway_ready(uuid) from public, anon;
revoke execute on function public.panel_takeaway_handed(uuid, uuid) from public, anon;
revoke execute on function public.panel_takeaway_assign(uuid, uuid) from public, anon;
revoke execute on function private.my_member(uuid) from public, anon;
revoke execute on function private.course_json(public.orders) from public, anon;
revoke execute on function public.staff_deliveries(uuid) from public, anon;
revoke execute on function public.staff_delivery_pickup(uuid, uuid) from public, anon;
revoke execute on function public.staff_delivery_done(uuid, uuid) from public, anon;
revoke execute on function public.staff_delivery_handover(uuid, uuid, uuid) from public, anon;

grant execute on function public.payments_test_mode() to authenticated;
grant execute on function private.courier_queue(uuid) to authenticated;
grant execute on function public.guest_place_order(uuid, text, jsonb, text, text, text, text, text) to authenticated;
grant execute on function public.guest_pay_order_test(uuid) to authenticated;
grant execute on function public.guest_cancel_order(uuid) to authenticated;
grant execute on function private.takeaway_order(uuid) to authenticated;
grant execute on function public.panel_takeaway_accept(uuid, integer, uuid) to authenticated;
grant execute on function public.panel_takeaway_reject(uuid, text, uuid) to authenticated;
grant execute on function public.panel_takeaway_ready(uuid) to authenticated;
grant execute on function public.panel_takeaway_handed(uuid, uuid) to authenticated;
grant execute on function public.panel_takeaway_assign(uuid, uuid) to authenticated;
grant execute on function private.my_member(uuid) to authenticated;
grant execute on function private.course_json(public.orders) to authenticated;
grant execute on function public.staff_deliveries(uuid) to authenticated;
grant execute on function public.staff_delivery_pickup(uuid, uuid) to authenticated;
grant execute on function public.staff_delivery_done(uuid, uuid) to authenticated;
grant execute on function public.staff_delivery_handover(uuid, uuid, uuid) to authenticated;
