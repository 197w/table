-- Table · migracja 0054
-- 1. Kod rabatowy wpisany przy zamykaniu rachunku (panel i Table for employees), z podpowiedziami kodów.
-- 2. Łączenie dostaw w jeden kurs: jeden dostawca zabiera kilka zamówień naraz.
-- 3. Grafik zapisywany naraz: w panelu „Edytuj” → zmiany → „Zapisz” (pracownicy widzą je dopiero po zapisie).

-- ---------------------------------------------------------------
-- 1. Kod rabatowy przy rachunku
-- ---------------------------------------------------------------

alter table public.orders
  add column if not exists discount_code_id uuid references public.discount_codes (id) on delete set null,
  add column if not exists discount_code    text,
  add column if not exists discount_kind    text check (discount_kind is null or discount_kind in ('percent', 'amount')),
  add column if not exists discount_value   integer;

-- Rabat rachunku o wartości p_total: kod wpisany przy rachunku, a bez niego kod z rezerwacji.
-- kind mówi, czy rabat jest procentowy (liczy się też od części rachunku) czy kwotowy (raz, przy zamknięciu).
create or replace function private.bill_discount(
  p_order    public.orders,
  p_total    integer,
  out amount integer,
  out label  text,
  out kind   text,
  out percent integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_res record;
begin
  amount := 0;
  label := null;
  kind := null;
  percent := null;
  if p_order.discount_kind is null then
    select * into v_res from private.order_discount(p_order.reservation_id, p_total);
    amount := v_res.amount;
    label := v_res.label;
    if label is not null then
      select r.discount_kind, case when r.discount_kind = 'percent' then r.discount_value end
      into kind, percent
      from public.reservations r where r.id = p_order.reservation_id;
    end if;
    return;
  end if;
  kind := p_order.discount_kind;
  if p_order.discount_kind = 'percent' then
    percent := p_order.discount_value;
    label := p_order.discount_code || ' (−' || p_order.discount_value || '%)';
    if p_total > 0 then
      amount := least(p_total, round(p_total * p_order.discount_value / 100.0)::integer);
    end if;
  else
    label := p_order.discount_code || ' (−' || replace(to_char(p_order.discount_value / 100.0, 'FM999990.00'), '.', ',') || ' zł)';
    if p_total > 0 then
      amount := least(p_total, p_order.discount_value);
    end if;
  end if;
end;
$$;

-- Ile do zapłaty: suma, rabat (kod przy rachunku albo z rezerwacji), zadatek i kwota po nich.
create or replace function public.panel_order_due(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_order    orders%rowtype;
  v_total    integer;
  v_discount record;
  v_deposit  integer;
begin
  select * into v_order from orders where id = p_order_id;
  if not found then
    raise exception 'Nie znaleziono rachunku.';
  end if;
  perform private.require_permission(v_order.restaurant_id, 'orders');
  select coalesce(sum(unit_price_grosze * quantity), 0) into v_total
  from order_items where order_id = p_order_id and status <> 'cancelled';
  select * into v_discount from private.bill_discount(v_order, v_total);
  v_deposit := private.order_deposit(v_order.reservation_id, v_total - v_discount.amount);
  return jsonb_build_object(
    'total', v_total,
    'discount', v_discount.amount,
    'discount_label', v_discount.label,
    'discount_percent', v_discount.percent,
    'discount_code', v_order.discount_code,
    'reservation_code', (select discount_code from reservations where id = v_order.reservation_id),
    'deposit', v_deposit,
    'due', v_total - v_discount.amount - v_deposit
  );
end;
$$;

-- Wpisanie kodu rabatowego przy rachunku (pusty kod usuwa wpisany). Kod musi działać dziś.
-- Zastępuje kod z rezerwacji; użycie kodu liczy się przy zamknięciu rachunku.
create or replace function public.panel_order_set_discount(
  p_order_id   uuid,
  p_code       text,
  p_member_id  uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
  v_code   discount_codes%rowtype;
  v_tz     text;
begin
  select * into v_order from orders where id = p_order_id for update;
  if not found then
    raise exception 'Nie znaleziono rachunku.';
  end if;
  perform private.require_permission(v_order.restaurant_id, 'orders');
  perform private.check_member(v_order.restaurant_id, p_member_id);
  if v_order.status <> 'open' then
    raise exception 'Ten rachunek jest już zamknięty.';
  end if;
  if v_order.kind <> 'dine_in' then
    raise exception 'Kod rabatowy wpisuje się przy rachunku stolika.';
  end if;
  if nullif(btrim(coalesce(p_code, '')), '') is null then
    update orders
    set discount_code_id = null, discount_code = null, discount_kind = null, discount_value = null
    where id = p_order_id;
  else
    select coalesce(timezone, 'Europe/Warsaw') into v_tz from restaurants where id = v_order.restaurant_id;
    v_code := private.valid_discount(v_order.restaurant_id, p_code, (now() at time zone v_tz)::date);
    update orders
    set discount_code_id = v_code.id, discount_code = v_code.code, discount_kind = v_code.kind,
        discount_value = v_code.value
    where id = p_order_id;
  end if;
  return panel_order_due(p_order_id);
end;
$$;

-- Podpowiedzi przy wpisywaniu kodu: aktywne kody lokalu, ważne dziś i z wolnym użyciem.
-- Najpierw kody zaczynające się od wpisanego tekstu, potem zawierające go.
create or replace function public.panel_discount_suggestions(p_restaurant_id uuid, p_query text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz   text;
  v_day  date;
  v_q    text := upper(btrim(coalesce(p_query, '')));
begin
  perform private.require_permission(p_restaurant_id, 'orders');
  select coalesce(timezone, 'Europe/Warsaw') into v_tz from restaurants where id = p_restaurant_id;
  v_day := (now() at time zone v_tz)::date;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'code', c.code, 'kind', c.kind, 'value', c.value, 'note', c.note, 'valid_until', c.valid_until,
      'uses_left', case when c.max_uses is null then null else c.max_uses - c.uses end
    ) order by (c.code like v_q || '%') desc, c.code)
    from (
      select * from discount_codes c
      where c.restaurant_id = p_restaurant_id
        and c.active
        and (c.valid_from is null or c.valid_from <= v_day)
        and (c.valid_until is null or c.valid_until >= v_day)
        and (c.max_uses is null or c.uses < c.max_uses)
        and (v_q = '' or c.code like '%' || v_q || '%' or upper(coalesce(c.note, '')) like '%' || v_q || '%')
      order by (c.code like v_q || '%') desc, c.code
      limit 8
    ) c
  ), '[]'::jsonb);
end;
$$;

-- Zamknięcie rachunku: rabat z kodu przy rachunku albo z rezerwacji, zadatek, napiwki, płatności.
create or replace function public.panel_settle_order(
  p_order_id   uuid,
  p_payments   jsonb,
  p_member_id  uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order     orders%rowtype;
  v_total     integer;
  v_discount  record;
  v_deposit   integer;
  v_tips      integer;
  v_methods   text[];
begin
  select * into v_order from orders where id = p_order_id for update;
  if not found then
    raise exception 'Nie znaleziono rachunku.';
  end if;
  perform private.require_permission(v_order.restaurant_id, 'orders');
  perform private.check_member(v_order.restaurant_id, p_member_id);
  if v_order.status <> 'open' then
    raise exception 'Ten rachunek jest już zamknięty.';
  end if;

  select coalesce(sum(unit_price_grosze * quantity), 0) into v_total
  from order_items where order_id = p_order_id and status <> 'cancelled';
  if v_total = 0 then
    raise exception 'Rachunek jest pusty. Anuluj go zamiast zamykać.';
  end if;

  select * into v_discount from private.bill_discount(v_order, v_total);
  v_deposit := private.order_deposit(v_order.reservation_id, v_total - v_discount.amount);
  v_tips := private.order_payments_insert(v_order, v_total - v_discount.amount - v_deposit, p_payments, p_member_id);
  select array_agg(distinct p->>'method') into v_methods from jsonb_array_elements(p_payments) p;

  update order_items set status = 'served' where order_id = p_order_id and status in ('new', 'sent', 'ready');
  update orders
  set status = 'paid',
      payment_method = case when array_length(v_methods, 1) = 1 then v_methods[1] else 'other' end,
      discount_grosze = v_discount.amount,
      discount_label = v_discount.label,
      deposit_grosze = v_deposit,
      tip_grosze = v_tips,
      closed_at = now(),
      closed_by = auth.uid(),
      closed_by_member = p_member_id
  where id = p_order_id;

  -- Kod wpisany przy rachunku: jedno użycie na zamknięty rachunek.
  if v_order.discount_code_id is not null then
    update discount_codes set uses = uses + 1 where id = v_order.discount_code_id;
  end if;

  if v_order.reservation_id is not null then
    update reservations
    set discount_used_grosze = discount_used_grosze
          + case when v_order.discount_kind is null then v_discount.amount else 0 end,
        deposit_used_grosze = deposit_used_grosze + v_deposit
    where id = v_order.reservation_id
      and ((v_order.discount_kind is null and v_discount.amount > 0) or v_deposit > 0);
    update reservations set status = 'completed', updated_at = now()
    where id = v_order.reservation_id and status = 'seated';
    if found then
      update table_holds
      set slot = tstzrange(lower(slot), greatest(lower(slot), now()) + interval '1 second'),
          active = false
      where reservation_id = v_order.reservation_id;
    end if;
  end if;

  return jsonb_build_object('total', v_total, 'discount', v_discount.amount, 'deposit', v_deposit,
                            'due', v_total - v_discount.amount - v_deposit, 'tip', v_tips);
end;
$$;

-- Podział po pozycjach: część płaci tylko rabat procentowy; kwotowy zostaje na zamknięcie reszty.
create or replace function public.panel_pay_items(
  p_order_id   uuid,
  p_items      jsonb,
  p_payments   jsonb,
  p_member_id  uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order     orders%rowtype;
  v_new       orders%rowtype;
  v_item      order_items%rowtype;
  v_sel       jsonb;
  v_qty       integer;
  v_part      integer := 0;
  v_left      integer;
  v_discount  record;
  v_amount    integer;
  v_label     text;
  v_tips      integer;
  v_methods   text[];
  v_new_id    uuid;
begin
  select * into v_order from orders where id = p_order_id for update;
  if not found then
    raise exception 'Nie znaleziono rachunku.';
  end if;
  perform private.require_permission(v_order.restaurant_id, 'orders');
  perform private.check_member(v_order.restaurant_id, p_member_id);
  if v_order.status <> 'open' then
    raise exception 'Ten rachunek jest już zamknięty.';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Wybierz pozycje, za które gość płaci.';
  end if;

  for v_sel in select * from jsonb_array_elements(p_items) loop
    select * into v_item from order_items
    where id = (v_sel->>'id')::uuid and order_id = p_order_id and status <> 'cancelled';
    if not found then
      raise exception 'Pozycji nie ma już na rachunku.';
    end if;
    v_qty := (v_sel->>'quantity')::integer;
    if v_qty is null or v_qty < 1 or v_qty > v_item.quantity then
      raise exception 'Nieprawidłowa ilość pozycji „%”.', v_item.name;
    end if;
    v_part := v_part + v_item.unit_price_grosze * v_qty;
  end loop;

  select coalesce(sum(unit_price_grosze * quantity), 0) - v_part into v_left
  from order_items where order_id = p_order_id and status <> 'cancelled';
  if v_left <= 0 then
    return panel_settle_order(p_order_id, p_payments, p_member_id);
  end if;

  insert into orders (restaurant_id, table_id, reservation_id, status, opened_by, opened_at, opened_by_member,
                      note, kind)
  values (v_order.restaurant_id, v_order.table_id, v_order.reservation_id, 'paid', v_order.opened_by,
          v_order.opened_at, v_order.opened_by_member, 'Część rachunku', 'dine_in')
  returning * into v_new;
  v_new_id := v_new.id;

  for v_sel in select * from jsonb_array_elements(p_items) loop
    select * into v_item from order_items where id = (v_sel->>'id')::uuid;
    v_qty := (v_sel->>'quantity')::integer;
    if v_qty = v_item.quantity then
      update order_items set order_id = v_new_id where id = v_item.id;
    else
      update order_items set quantity = quantity - v_qty where id = v_item.id;
      insert into order_items
      select * from jsonb_populate_record(
        null::order_items,
        to_jsonb(v_item) || jsonb_build_object('id', gen_random_uuid(), 'order_id', v_new_id, 'quantity', v_qty)
      );
    end if;
  end loop;

  select * into v_discount from private.bill_discount(v_order, v_part);
  v_amount := case when v_discount.kind = 'percent' then v_discount.amount else 0 end;
  v_label := case when v_amount > 0 then v_discount.label end;
  v_tips := private.order_payments_insert(v_new, v_part - v_amount, p_payments, p_member_id);
  select array_agg(distinct p->>'method') into v_methods from jsonb_array_elements(p_payments) p;

  update order_items set status = 'served' where order_id = v_new_id and status in ('new', 'sent', 'ready');
  update orders
  set payment_method = case when array_length(v_methods, 1) = 1 then v_methods[1] else 'other' end,
      discount_grosze = v_amount,
      discount_label = v_label,
      tip_grosze = v_tips,
      closed_at = now(),
      closed_by = auth.uid(),
      closed_by_member = p_member_id
  where id = v_new_id;

  return jsonb_build_object('total', v_part, 'discount', v_amount, 'due', v_part - v_amount,
                            'tip', v_tips, 'left', v_left, 'order_id', v_new_id);
end;
$$;

-- ---------------------------------------------------------------
-- 2. Kilka dostaw w jednym kursie
-- ---------------------------------------------------------------

alter table public.orders add column if not exists course_id uuid;
create index if not exists orders_course_idx on public.orders (course_id) where course_id is not null;

-- Zamówienia tego samego kursu, które jeszcze czekają w lokalu.
create or replace function private.course_waiting(p_course uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select o.id from public.orders o
  where p_course is not null and o.course_id = p_course and o.fulfillment in ('accepted', 'ready')
$$;

-- Kolejka dostawców: przydzielenie kursu daje dostawcy od razu wszystkie zamówienia z tego kursu.
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

-- Łączenie dostaw w jeden kurs (co najmniej dwie, jeszcze w lokalu). Dostawca: wskazany, a bez wskazania
-- ten, który ma już któreś z tych zamówień; bez nikogo kurs czeka w kolejce na wolnego dostawcę.
create or replace function public.panel_takeaway_merge(
  p_order_ids  uuid[],
  p_courier    uuid default null,
  p_member_id  uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
  v_count       integer;
  v_course      uuid;
  v_courier     uuid;
begin
  select count(distinct id), min(restaurant_id::text)::uuid into v_count, v_restaurant
  from orders where id = any (p_order_ids);
  if coalesce(array_length(p_order_ids, 1), 0) < 2 or v_count < 2 then
    raise exception 'Wybierz co najmniej dwa zamówienia.';
  end if;
  if (select count(distinct restaurant_id) from orders where id = any (p_order_ids)) <> 1 then
    raise exception 'Nie znaleziono zamówień.';
  end if;
  perform private.require_permission(v_restaurant, 'orders');
  perform private.check_member(v_restaurant, p_member_id);
  perform pg_advisory_xact_lock(hashtext('dispatch:' || v_restaurant::text));
  if exists (
    select 1 from orders
    where id = any (p_order_ids) and (kind <> 'delivery' or fulfillment not in ('accepted', 'ready'))
  ) then
    raise exception 'Połączyć można tylko przyjęte dostawy, które jeszcze nie wyjechały z lokalu.';
  end if;

  -- Istniejący kurs któregoś zamówienia (jeśli cały jest jeszcze w lokalu) albo nowy.
  select o.course_id into v_course
  from orders o
  where o.id = any (p_order_ids) and o.course_id is not null
    and not exists (
      select 1 from orders x where x.course_id = o.course_id and x.fulfillment not in ('accepted', 'ready')
    )
  limit 1;
  v_course := coalesce(v_course, gen_random_uuid());

  if p_courier is not null then
    if not exists (select 1 from private.courier_queue(v_restaurant) q where q.member_id = p_courier) then
      raise exception 'Ten dostawca nie jest teraz na zmianie.';
    end if;
    v_courier := p_courier;
  else
    select courier_member into v_courier from orders
    where (id = any (p_order_ids) or id in (select private.course_waiting(v_course)))
      and courier_member is not null
    order by courier_assigned_at nulls last
    limit 1;
  end if;

  update orders
  set course_id = v_course,
      courier_member = v_courier,
      courier_assigned_at = case
        when v_courier is null then null
        when courier_member is distinct from v_courier then now()
        else courier_assigned_at
      end
  where id = any (p_order_ids) or id in (select private.course_waiting(v_course));

  perform private.dispatch_deliveries(v_restaurant);
  return v_course;
end;
$$;

-- Wyjęcie zamówienia z kursu, zanim wyjedzie. Wraca do kolejki; kurs z jednym zamówieniem przestaje być łączony.
create or replace function public.panel_takeaway_split(p_order_id uuid, p_member_id uuid default null)
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
  if v_order.course_id is null then
    return;
  end if;
  if v_order.fulfillment not in ('accepted', 'ready') then
    raise exception 'Zamówienie wyjechało już z lokalu.';
  end if;
  perform pg_advisory_xact_lock(hashtext('dispatch:' || v_order.restaurant_id::text));
  update orders set course_id = null, courier_member = null, courier_assigned_at = null where id = p_order_id;
  update orders set course_id = null
  where course_id = v_order.course_id
    and (select count(*) from orders x where x.course_id = v_order.course_id) = 1;
  perform private.dispatch_deliveries(v_order.restaurant_id);
end;
$$;

-- Zmiana dostawcy z panelu: dla całego kursu.
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
  where id = p_order_id or id in (select private.course_waiting(v_order.course_id));
end;
$$;

-- Dostawca odbiera z lokalu cały kurs naraz.
create or replace function public.staff_delivery_pickup(p_order_id uuid, p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member  staff_members%rowtype;
  v_course  uuid;
begin
  v_member := private.my_member(p_member_id);
  perform private.check_member(v_member.restaurant_id, p_member_id);
  select course_id into v_course from orders where id = p_order_id and courier_member = p_member_id;
  update orders set fulfillment = 'on_the_way', picked_up_at = now()
  where courier_member = p_member_id and fulfillment in ('accepted', 'ready')
    and (id = p_order_id or id in (select private.course_waiting(v_course)));
  if not found then
    raise exception 'Ten kurs nie czeka już na Ciebie w lokalu.';
  end if;
end;
$$;

-- Oddanie kursu innemu dostawcy: razem ze wszystkimi zamówieniami z tego kursu.
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
  update orders set courier_member = v_to, courier_assigned_at = now()
  where courier_member = p_member_id
    and (id = p_order_id or id in (select private.course_waiting(v_order.course_id)));
  update staff_members set courier_ready_at = now() where id = p_member_id;
  return (select name from staff_members where id = v_to);
end;
$$;

-- Kurs dla aplikacji dostawcy: z numerem kursu, żeby zamówienia jednego kursu były razem.
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

-- ---------------------------------------------------------------
-- 3. Grafik zapisywany naraz
-- ---------------------------------------------------------------

-- Zmiany z trybu edycji grafiku w panelu, w jednej transakcji: [{action, id, member_id, day, starts, ends, answer}].
-- action: accept (przyjęcie zgłoszenia, także ze zmienionymi godzinami), reject, add (godziny wpisane przez
-- przełożonego), off (wolne), delete. Błąd w jednej zmianie cofa wszystkie.
create or replace function public.panel_save_schedule(p_restaurant_id uuid, p_changes jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c       jsonb;
  v_n       integer := 0;
  v_member  uuid;
  v_id      uuid;
  v_day     date;
begin
  perform private.require_schedule(p_restaurant_id);
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' or jsonb_array_length(p_changes) = 0 then
    raise exception 'Nie ma zmian do zapisania.';
  end if;
  if jsonb_array_length(p_changes) > 1000 then
    raise exception 'Za dużo zmian naraz. Zapisz grafik w częściach.';
  end if;
  for v_c in select * from jsonb_array_elements(p_changes) loop
    v_member := nullif(v_c->>'member_id', '')::uuid;
    v_id := nullif(v_c->>'id', '')::uuid;
    v_day := nullif(v_c->>'day', '')::date;
    if v_member is not null
       and not exists (select 1 from staff_members where id = v_member and restaurant_id = p_restaurant_id) then
      raise exception 'Nie znaleziono pracownika.';
    end if;
    if v_c->>'action' in ('accept', 'reject')
       and not exists (select 1 from staff_schedule where id = v_id and restaurant_id = p_restaurant_id) then
      raise exception 'Zgłoszenie z % zmieniło się w trakcie edycji. Sprawdź ten dzień i zapisz jeszcze raz.',
        coalesce(to_char(v_day, 'DD.MM'), 'tego dnia');
    end if;
    case v_c->>'action'
      when 'accept' then
        perform panel_decide_hours(v_id, true, nullif(v_c->>'starts', '')::time, nullif(v_c->>'ends', '')::time,
                                   v_c->>'answer');
      when 'reject' then
        perform panel_decide_hours(v_id, false, null, null, v_c->>'answer');
      when 'add' then
        perform panel_add_hours(v_member, v_day, nullif(v_c->>'starts', '')::time, nullif(v_c->>'ends', '')::time,
                                v_c->>'answer');
      when 'off' then
        perform panel_set_day_off(v_member, v_day, v_c->>'answer');
      when 'delete' then
        if exists (select 1 from staff_schedule where id = v_id and restaurant_id = p_restaurant_id) then
          perform panel_delete_hours(v_id);
        end if;
      else
        raise exception 'Nieznana zmiana w grafiku.';
    end case;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

revoke execute on function private.bill_discount(public.orders, integer) from public, anon;
revoke execute on function private.course_waiting(uuid) from public, anon;
revoke execute on function public.panel_order_set_discount(uuid, text, uuid) from public, anon;
revoke execute on function public.panel_discount_suggestions(uuid, text) from public, anon;
revoke execute on function public.panel_takeaway_merge(uuid[], uuid, uuid) from public, anon;
revoke execute on function public.panel_takeaway_split(uuid, uuid) from public, anon;
revoke execute on function public.panel_save_schedule(uuid, jsonb) from public, anon;
grant execute on function private.bill_discount(public.orders, integer) to authenticated;
grant execute on function private.course_waiting(uuid) to authenticated;
grant execute on function public.panel_order_set_discount(uuid, text, uuid) to authenticated;
grant execute on function public.panel_discount_suggestions(uuid, text) to authenticated;
grant execute on function public.panel_takeaway_merge(uuid[], uuid, uuid) to authenticated;
grant execute on function public.panel_takeaway_split(uuid, uuid) to authenticated;
grant execute on function public.panel_save_schedule(uuid, jsonb) to authenticated;

-- Kwota rabatu w nazwie z przecinkiem („−5,00 zł”), także dla kodów z rezerwacji.
create or replace function private.order_discount(p_reservation_id uuid, p_total integer, out amount integer, out label text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_res public.reservations;
begin
  amount := 0;
  label := null;
  if p_reservation_id is null or p_total <= 0 then
    return;
  end if;
  select * into v_res from public.reservations where id = p_reservation_id;
  if not found or v_res.discount_kind is null then
    return;
  end if;
  if v_res.discount_kind = 'percent' then
    amount := least(p_total, round(p_total * v_res.discount_value / 100.0)::integer);
    label := v_res.discount_code || ' (−' || v_res.discount_value || '%)';
  else
    amount := least(p_total, greatest(v_res.discount_value - v_res.discount_used_grosze, 0));
    label := v_res.discount_code || ' (−' || replace(to_char(v_res.discount_value / 100.0, 'FM999990.00'), '.', ',') || ' zł)';
  end if;
end;
$$;
