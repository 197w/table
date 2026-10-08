-- Table · migracja 0055
-- 1. Zamówienie na dostawę albo odbiór przyjmowane w panelu (np. przez telefon): dane klienta, firma i NIP,
--    komentarz do zamówienia i komentarz tylko dla pracowników, opłacone albo do opłacenia. Najpierw szkic
--    (`fulfillment = 'draft'`, tylko w Zamówieniach), potem „Przyjmij” wysyła je na kuchnię i do Dostaw.
-- 2. Historia klienta po numerze telefonu: liczba i kwota wcześniejszych zamówień, ostatnie dane do uzupełnienia.
-- 3. Zmiana składników przy nabijaniu dania: „bez” albo „więcej” (`order_items.changes`), także w zużyciu magazynu.

-- ---------------------------------------------------------------
-- 1. Zamówienia z panelu
-- ---------------------------------------------------------------

alter table public.orders drop constraint orders_fulfillment_check;
alter table public.orders add constraint orders_fulfillment_check check (fulfillment = any (array[
  'draft', 'awaiting_payment', 'placed', 'accepted', 'ready', 'on_the_way', 'delivered', 'rejected', 'cancelled'
]));
alter table public.orders drop constraint orders_payment_choice_check;
alter table public.orders add constraint orders_payment_choice_check
  check (payment_choice = any (array['cash', 'card_online', 'prepaid']));

alter table public.orders
  add column if not exists customer_company text check (char_length(customer_company) <= 120),
  add column if not exists customer_nip     text check (customer_nip ~ '^[0-9]{10}$'),
  add column if not exists staff_note       text check (char_length(staff_note) <= 300),
  add column if not exists address_street   text check (char_length(address_street) <= 120),
  add column if not exists address_house    text check (char_length(address_house) <= 20),
  add column if not exists address_city     text check (char_length(address_city) <= 80);

-- Zmiany składników pozycji (część 3), już tutaj, bo czyta je kurs dostawcy.
alter table public.order_items add column if not exists changes jsonb not null default '[]'::jsonb;

-- Ostatnie 9 cyfr telefonu: ten sam klient niezależnie od zapisu (+48, spacje, myślniki).
create or replace function private.phone_key(p_phone text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9), '')
$$;

-- Dane klienta z formularza panelu, sprawdzone. Rodzaj: delivery albo pickup.
create or replace function private.takeaway_customer(p_kind text, p_customer jsonb, out name text, out company text,
  out nip text, out phone text, out street text, out house text, out city text, out note text, out staff_note text,
  out paid boolean)
language plpgsql
immutable
set search_path = ''
as $$
begin
  name := nullif(btrim(p_customer ->> 'name'), '');
  company := nullif(btrim(p_customer ->> 'company'), '');
  nip := nullif(regexp_replace(coalesce(p_customer ->> 'nip', ''), '[^0-9]', '', 'g'), '');
  phone := nullif(btrim(p_customer ->> 'phone'), '');
  street := nullif(btrim(p_customer ->> 'street'), '');
  house := nullif(btrim(p_customer ->> 'house'), '');
  city := nullif(btrim(p_customer ->> 'city'), '');
  note := nullif(btrim(p_customer ->> 'note'), '');
  staff_note := nullif(btrim(p_customer ->> 'staff_note'), '');
  paid := (p_customer ->> 'paid')::boolean;

  if name is null and company is null then
    raise exception 'Podaj imię i nazwisko albo nazwę lokalu.';
  end if;
  if char_length(coalesce(name, '')) > 80 or char_length(coalesce(company, '')) > 120 then
    raise exception 'Imię i nazwisko do 80 znaków, nazwa lokalu do 120.';
  end if;
  if char_length(regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g')) < 9 or char_length(phone) > 20 then
    raise exception 'Podaj numer telefonu (co najmniej 9 cyfr).';
  end if;
  if nip is not null and nip !~ '^[0-9]{10}$' then
    raise exception 'NIP ma 10 cyfr.';
  end if;
  if paid is null then
    raise exception 'Zaznacz, czy zamówienie jest opłacone, czy do opłacenia.';
  end if;
  if p_kind = 'delivery' then
    if street is null or house is null or city is null then
      raise exception 'Podaj ulicę, numer domu albo lokalu i miasto.';
    end if;
    if char_length(street) > 120 or char_length(house) > 20 or char_length(city) > 80 then
      raise exception 'Adres jest za długi.';
    end if;
  else
    street := null;
    house := null;
    city := null;
  end if;
  if char_length(coalesce(note, '')) > 300 or char_length(coalesce(staff_note, '')) > 300 then
    raise exception 'Komentarz do 300 znaków.';
  end if;
end;
$$;

-- Nowe zamówienie na dostawę albo odbiór z panelu. Powstaje jako szkic: dania dokłada się z menu, a dopiero
-- „Przyjmij” (`panel_takeaway_submit`) wysyła je na kuchnię i do Dostaw. Numer dnia jak w aplikacji.
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

  perform pg_advisory_xact_lock(hashtext('order-number:' || p_restaurant_id::text));
  select coalesce(max(number), 0) + 1 into v_number
  from orders
  where restaurant_id = p_restaurant_id
    and kind <> 'dine_in'
    and (opened_at at time zone v_r.timezone)::date = (now() at time zone v_r.timezone)::date;

  insert into orders (
    restaurant_id, kind, number, customer_name, customer_company, customer_nip, customer_phone,
    address_street, address_house, address_city, delivery_address, delivery_note, staff_note,
    delivery_fee_grosze, payment_choice, payment_status, fulfillment, opened_by, opened_by_member
  )
  values (
    p_restaurant_id, p_kind, v_number, left(coalesce(v_c.name, v_c.company), 80), v_c.company, v_c.nip, v_c.phone,
    v_c.street, v_c.house, v_c.city,
    case when p_kind = 'delivery' then left(v_c.street || ' ' || v_c.house || ', ' || v_c.city, 200) end,
    v_c.note, v_c.staff_note,
    case when p_kind = 'delivery' then v_r.delivery_fee_grosze else 0 end,
    case when v_c.paid then 'prepaid' else 'cash' end,
    case when v_c.paid then 'paid' else 'unpaid' end,
    'draft', auth.uid(), p_member_id
  )
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'number', v_number);
end;
$$;

-- Zmiana danych klienta zamówienia z panelu, dopóki nie wyjechało z lokalu.
create or replace function public.panel_takeaway_update(p_order_id uuid, p_customer jsonb, p_member_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
  v_c      record;
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
end;
$$;

-- „Przyjmij”: szkic idzie na kuchnię i do Dostaw z czasem przygotowania (jak przyjęcie zamówienia z aplikacji).
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

-- Porzucenie szkicu: znika razem z pozycjami (nic nie poszło na kuchnię).
create or replace function public.panel_takeaway_discard(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
begin
  v_order := private.takeaway_order(p_order_id);
  if v_order.fulfillment <> 'draft' then
    raise exception 'Przyjęte zamówienie odrzuca się w Dostawach.';
  end if;
  delete from order_items where order_id = p_order_id;
  delete from orders where id = p_order_id;
end;
$$;

-- Historia klienta po telefonie: zakończone zamówienia na wynos (liczba i kwota) i dane z ostatniego zamówienia.
create or replace function public.panel_customer_lookup(p_restaurant_id uuid, p_phone text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_key   text := private.phone_key(p_phone);
  v_last  orders%rowtype;
begin
  perform private.require_permission(p_restaurant_id, 'orders');
  if v_key is null or char_length(v_key) < 9 then
    return jsonb_build_object('orders', 0, 'spent_grosze', 0);
  end if;
  select * into v_last from orders
  where restaurant_id = p_restaurant_id and kind <> 'dine_in' and fulfillment <> 'draft'
    and private.phone_key(customer_phone) = v_key
  order by opened_at desc
  limit 1;
  return (
    select jsonb_build_object(
      'orders', count(*),
      'spent_grosze', coalesce(sum(
        o.delivery_fee_grosze - o.discount_grosze + coalesce((
          select sum(i.unit_price_grosze * i.quantity) from order_items i
          where i.order_id = o.id and i.status <> 'cancelled'
        ), 0)
      ), 0),
      'last_at', max(o.closed_at),
      'name', case when v_last.customer_company is null or v_last.customer_name <> v_last.customer_company
                   then v_last.customer_name end,
      'company', v_last.customer_company,
      'nip', v_last.customer_nip,
      'street', v_last.address_street,
      'house', v_last.address_house,
      'city', v_last.address_city,
      'address', v_last.delivery_address
    )
    from orders o
    where o.restaurant_id = p_restaurant_id and o.kind <> 'dine_in' and o.status = 'paid'
      and private.phone_key(o.customer_phone) = v_key
  );
end;
$$;

-- Zamknięcie dostawy i odbioru: zamówienie opłacone wcześniej (przyjęte w panelu) to płatność „inne”.
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
      payment_method = case payment_choice when 'card_online' then 'card' when 'prepaid' then 'other' else 'cash' end,
      closed_at = now(), closed_by = auth.uid(), closed_by_member = p_member_id
  where id = p_order_id;
  update staff_members set courier_ready_at = now() where id = p_member_id;
  perform private.dispatch_deliveries(v_member.restaurant_id);
end;
$$;

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
      payment_method = case payment_choice when 'card_online' then 'card' when 'prepaid' then 'other' else 'cash' end,
      closed_at = now(), closed_by = auth.uid(), closed_by_member = p_member_id
  where id = p_order_id;
end;
$$;

-- Kurs dla dostawcy: z firmą i komentarzem tylko dla pracowników.
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
    'course_id', p_order.course_id,
    'fulfillment', p_order.fulfillment,
    'customer_name', p_order.customer_name,
    'customer_company', p_order.customer_company,
    'customer_phone', p_order.customer_phone,
    'delivery_address', p_order.delivery_address,
    'delivery_note', p_order.delivery_note,
    'staff_note', p_order.staff_note,
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
        'name', i.name, 'variant', i.variant, 'quantity', i.quantity, 'note', i.note, 'changes', i.changes,
        'addons', (select coalesce(jsonb_agg(a ->> 'name'), '[]'::jsonb) from jsonb_array_elements(i.addons) a)
      ) order by i.created_at)
      from public.order_items i where i.order_id = p_order.id and i.status <> 'cancelled'
    ), '[]'::jsonb)
  )
$$;

-- ---------------------------------------------------------------
-- 3. Zmiana składników: „bez cebuli”, „więcej sera”
-- ---------------------------------------------------------------

-- Zmiany składników sprawdzone: [{name, kind: without|extra, item_id?}]. item_id tylko ze składników receptury dania.
create or replace function private.item_changes(p_menu_item_id uuid, p_changes jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_c       jsonb;
  v_out     jsonb := '[]'::jsonb;
  v_name    text;
  v_item    uuid;
begin
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then
    return '[]'::jsonb;
  end if;
  if jsonb_array_length(p_changes) > 20 then
    raise exception 'Najwyżej 20 zmian składników w jednej pozycji.';
  end if;
  for v_c in select * from jsonb_array_elements(p_changes) loop
    v_name := nullif(btrim(v_c ->> 'name'), '');
    if v_name is null or char_length(v_name) > 40 then
      raise exception 'Nazwa składnika ma od 1 do 40 znaków.';
    end if;
    if coalesce(v_c ->> 'kind', '') not in ('without', 'extra') then
      raise exception 'Składnik można usunąć albo dodać.';
    end if;
    v_item := null;
    if nullif(v_c ->> 'item_id', '') is not null then
      select r.item_id into v_item from public.menu_item_ingredients r
      where r.menu_item_id = p_menu_item_id and r.item_id = (v_c ->> 'item_id')::uuid;
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('name', v_name, 'kind', v_c ->> 'kind', 'item_id', v_item));
  end loop;
  return v_out;
end;
$$;

drop function public.panel_add_order_item(uuid, uuid, text, text[], integer, text, integer, uuid);
create function public.panel_add_order_item(
  p_order_id      uuid,
  p_menu_item_id  uuid,
  p_variant       text default null,
  p_addons        text[] default '{}',
  p_quantity      integer default 1,
  p_note          text default null,
  p_course        integer default 1,
  p_member_id     uuid default null,
  p_changes       jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order    orders%rowtype;
  v_item     record;
  v_option   jsonb;
  v_price    integer;
  v_variant  text;
  v_addons   jsonb := '[]';
  v_name     text;
  v_id       uuid;
begin
  select * into v_order from orders where id = p_order_id;
  if not found then
    raise exception 'Nie znaleziono rachunku.';
  end if;
  perform private.require_permission(v_order.restaurant_id, 'orders');
  perform private.check_member(v_order.restaurant_id, p_member_id);
  if v_order.status <> 'open' then
    raise exception 'Ten rachunek jest już zamknięty.';
  end if;

  select i.id, i.name, i.price_grosze, i.variants, i.addons, i.vat_rate, i.available, s.restaurant_id
  into v_item
  from menu_items i
  join menu_sections s on s.id = i.section_id
  where i.id = p_menu_item_id;
  if not found or v_item.restaurant_id <> v_order.restaurant_id then
    raise exception 'Nie znaleziono pozycji w menu.';
  end if;
  if not v_item.available then
    raise exception 'Ta pozycja jest chwilowo niedostępna.';
  end if;
  if p_quantity is null or p_quantity not between 1 and 99 then
    raise exception 'Ilość od 1 do 99.';
  end if;

  if jsonb_array_length(v_item.variants) > 0 then
    select o into v_option from jsonb_array_elements(v_item.variants) o where o ->> 'name' = p_variant;
    if v_option is null then
      raise exception 'Wybierz wariant pozycji „%”.', v_item.name;
    end if;
    v_price := (v_option ->> 'price_grosze')::integer;
    v_variant := v_option ->> 'name';
  else
    v_price := v_item.price_grosze;
  end if;

  foreach v_name in array coalesce(p_addons, '{}') loop
    v_option := null;
    select o into v_option from jsonb_array_elements(v_item.addons) o where o ->> 'name' = v_name;
    if v_option is null then
      raise exception 'Pozycja „%” nie ma dodatku „%”.', v_item.name, v_name;
    end if;
    v_price := v_price + (v_option ->> 'price_grosze')::integer;
    v_addons := v_addons || jsonb_build_array(v_option);
  end loop;

  insert into order_items (
    order_id, restaurant_id, menu_item_id, name, variant, addons,
    unit_price_grosze, vat_rate, quantity, note, course, created_by, created_by_member, changes
  )
  values (
    p_order_id, v_order.restaurant_id, v_item.id, v_item.name, v_variant, v_addons,
    v_price, v_item.vat_rate, p_quantity, nullif(btrim(p_note), ''),
    greatest(1, least(5, coalesce(p_course, 1))), auth.uid(), p_member_id,
    private.item_changes(v_item.id, p_changes)
  )
  returning id into v_id;
  return v_id;
end;
$$;

-- Zużycie z magazynu: składnik „bez” nie schodzi, „więcej” schodzi podwójnie.
create or replace function private.order_item_inventory()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.status = old.status and new.quantity = old.quantity then
    return new;
  end if;

  if new.status in ('sent', 'ready', 'served') then
    if tg_op = 'INSERT' or old.status in ('new', 'cancelled') or old.quantity <> new.quantity then
      delete from public.inventory_movements where order_item_id = new.id;
      insert into public.inventory_movements (restaurant_id, item_id, amount, kind, order_item_id)
      select new.restaurant_id, r.item_id, -(new.quantity * r.amount * private.inventory_factor(r.unit, i.unit) * m.factor),
             'sale', new.id
      from public.menu_item_ingredients r
      join public.inventory_items i on i.id = r.item_id and i.deleted_at is null
      cross join lateral (
        select case
          when exists (select 1 from jsonb_array_elements(coalesce(new.changes, '[]'::jsonb)) c
                       where c ->> 'item_id' = r.item_id::text and c ->> 'kind' = 'without') then 0
          when exists (select 1 from jsonb_array_elements(coalesce(new.changes, '[]'::jsonb)) c
                       where c ->> 'item_id' = r.item_id::text and c ->> 'kind' = 'extra') then 2
          else 1
        end as factor
      ) m
      where r.menu_item_id = new.menu_item_id
        and m.factor > 0
        and private.inventory_factor(r.unit, i.unit) is not null;
    end if;
  else
    delete from public.inventory_movements where order_item_id = new.id;
  end if;
  return new;
end;
$$;

revoke execute on function private.phone_key(text) from public, anon;
revoke execute on function private.takeaway_customer(text, jsonb) from public, anon;
revoke execute on function private.item_changes(uuid, jsonb) from public, anon;
revoke execute on function public.panel_takeaway_create(uuid, text, jsonb, uuid) from public, anon;
revoke execute on function public.panel_takeaway_update(uuid, jsonb, uuid) from public, anon;
revoke execute on function public.panel_takeaway_submit(uuid, integer, uuid) from public, anon;
revoke execute on function public.panel_takeaway_discard(uuid) from public, anon;
revoke execute on function public.panel_customer_lookup(uuid, text) from public, anon;
revoke execute on function public.panel_add_order_item(uuid, uuid, text, text[], integer, text, integer, uuid, jsonb) from public, anon;
grant execute on function private.phone_key(text) to authenticated;
grant execute on function private.takeaway_customer(text, jsonb) to authenticated;
grant execute on function private.item_changes(uuid, jsonb) to authenticated;
grant execute on function public.panel_takeaway_create(uuid, text, jsonb, uuid) to authenticated;
grant execute on function public.panel_takeaway_update(uuid, jsonb, uuid) to authenticated;
grant execute on function public.panel_takeaway_submit(uuid, integer, uuid) to authenticated;
grant execute on function public.panel_takeaway_discard(uuid) to authenticated;
grant execute on function public.panel_customer_lookup(uuid, text) to authenticated;
grant execute on function public.panel_add_order_item(uuid, uuid, text, text[], integer, text, integer, uuid, jsonb) to authenticated;
