-- Zniżki na działy menu w wydarzeniach (20.11.2026, prośba użytkownika: „w wydarzeniach dodaj też możliwość, dla
-- gości oczywiście, dodawania zniżek na daną sekcję”).
--
-- Wydarzenie specjalne z Kalendarza (0080) może mieć zniżkę procentową na dowolny dział menu lokalu (nie tylko na dział
-- przypięty do wydarzenia): w czasie wydarzenia (od początku do końca) pozycje tego działu są tańsze o ten procent
-- dla gości zamawiających w aplikacji Table (dostawa i odbiór). Cenę liczy baza w `guest_place_order`, więc cena
-- w zamówieniu zgadza się z tą, którą gość widzi w zaktualizowanej aplikacji (starsza aplikacja pokazuje pełną cenę,
-- a zamówienie dostaje cenę ze zniżką). Dwie zniżki na ten sam dział w nakładających się wydarzeniach: działa
-- większa. Zniżka liczy się od ceny pozycji razem z wariantem i dodatkami, zaokrąglona do grosza.
-- Zamówienia obsługi (Zamówienia w panelu i kelner) są bez zniżki.

create table public.event_section_discounts (
  event_id    uuid not null references public.calendar_events (id) on delete cascade,
  section_id  uuid not null references public.menu_sections (id) on delete cascade,
  percent     smallint not null check (percent between 1 and 90),
  primary key (event_id, section_id)
);

create index event_section_discounts_section on public.event_section_discounts (section_id);

alter table public.event_section_discounts enable row level security;

-- Goście czytają zniżki wydarzeń specjalnych (jak same wydarzenia), obsługa wszystkie z wydarzeń swojego lokalu.
create policy event_section_discounts_public on public.event_section_discounts
  for select to anon, authenticated
  using (exists (select 1 from public.calendar_events e where e.id = event_id and e.kind = 'special'));

create policy event_section_discounts_staff on public.event_section_discounts
  for select to authenticated
  using (exists (
    select 1 from public.calendar_events e
    where e.id = event_id and private.has_staff_role(e.restaurant_id, 'staff')
  ));

grant select on public.event_section_discounts to anon, authenticated;

-- Procent zniżki na dział w chwili [p_at]: największy z trwających wydarzeń specjalnych. 0: bez zniżki.
create or replace function private.section_discount_percent(p_section_id uuid, p_at timestamptz)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(max(d.percent), 0)::integer
  from public.event_section_discounts d
  join public.calendar_events e on e.id = d.event_id
  where d.section_id = p_section_id
    and e.kind = 'special'
    and p_at >= e.starts_at
    and p_at < e.ends_at
$$;
revoke execute on function private.section_discount_percent(uuid, timestamptz) from public, anon;

-- Zniżki wydarzenia: lista {section_id, percent} zastępuje dotychczasową (pusta: bez zniżek). Wydarzenie specjalne,
-- działy z tego samego lokalu, procent 1–90, każdy dział raz. Uprawnienia „Kalendarz” i „Edytowanie menu”.
create or replace function public.panel_set_event_discounts(p_event_id uuid, p_discounts jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event  calendar_events%rowtype;
  v_line   jsonb;
  v_sec    uuid;
  v_pct    integer;
  v_seen   uuid[] := '{}';
begin
  select * into v_event from calendar_events where id = p_event_id;
  if not found then
    raise exception 'Nie znaleziono wydarzenia.';
  end if;
  perform private.require_permission(v_event.restaurant_id, 'calendar');
  perform private.require_permission(v_event.restaurant_id, 'menu_edit');
  if v_event.kind <> 'special' then
    raise exception 'Zniżki są tylko przy wydarzeniach specjalnych, które widzą goście.';
  end if;
  p_discounts := coalesce(p_discounts, '[]'::jsonb);
  if jsonb_typeof(p_discounts) <> 'array' then
    raise exception 'Zniżki mają być listą.';
  end if;
  if jsonb_array_length(p_discounts) > 40 then
    raise exception 'Za dużo zniżek w jednym wydarzeniu.';
  end if;

  delete from event_section_discounts where event_id = p_event_id;
  for v_line in select * from jsonb_array_elements(p_discounts) loop
    v_sec := (v_line ->> 'section_id')::uuid;
    v_pct := (v_line ->> 'percent')::integer;
    if v_sec is null or not exists (
      select 1 from menu_sections where id = v_sec and restaurant_id = v_event.restaurant_id
    ) then
      raise exception 'Nie znaleziono działu menu.';
    end if;
    if v_pct is null or v_pct not between 1 and 90 then
      raise exception 'Zniżka od 1 do 90%%.';
    end if;
    if v_sec = any (v_seen) then
      raise exception 'Każdy dział tylko raz.';
    end if;
    v_seen := v_seen || v_sec;
    insert into event_section_discounts (event_id, section_id, percent) values (p_event_id, v_sec, v_pct);
  end loop;
end;
$$;

revoke execute on function public.panel_set_event_discounts(uuid, jsonb) from public, anon;
grant execute on function public.panel_set_event_discounts(uuid, jsonb) to authenticated;

-- Zamówienie gościa z aplikacji (dostawa, odbiór): cena pozycji ze zniżką na dział, jeśli trwa wydarzenie ze zniżką
-- (dla zamówienia na godzinę liczy się ta godzina). Reszta bez zmian względem 0074.
create or replace function public.guest_place_order(
  p_restaurant_id uuid,
  p_kind text,
  p_items jsonb,
  p_payment text,
  p_name text,
  p_phone text,
  p_address text default null,
  p_note text default null,
  p_scheduled_for timestamptz default null,
  p_address_note text default null
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
  v_pct      integer;
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
  if p_payment is null or p_payment not in ('cash', 'card_online', 'card_on_delivery') then
    raise exception 'Wybierz formę płatności.';
  end if;
  if p_payment = 'cash' and not v_r.takeaway_cash then
    raise exception 'Ten lokal nie przyjmuje płatności gotówką.';
  end if;
  if p_payment = 'card_on_delivery' and not v_r.takeaway_card then
    raise exception 'Ten lokal nie przyjmuje płatności kartą przy odbiorze.';
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
    restaurant_id, kind, guest_id, number, customer_name, customer_phone, delivery_address, delivery_note, address_note,
    delivery_fee_grosze, payment_choice, payment_status, fulfillment, opened_by, scheduled_for
  )
  values (
    p_restaurant_id, p_kind, auth.uid(), v_number, left(btrim(p_name), 80), left(btrim(p_phone), 20),
    case when p_kind = 'delivery' then left(btrim(p_address), 200) end, left(nullif(btrim(p_note), ''), 300),
    case when p_kind = 'delivery' then left(nullif(btrim(p_address_note), ''), 300) end,
    v_fee, p_payment,
    case when p_payment = 'card_online' then 'pending' else 'unpaid' end,
    case when p_payment = 'card_online' then 'awaiting_payment' else 'placed' end,
    auth.uid(), v_when
  )
  returning id into v_order;

  for v_line in select * from jsonb_array_elements(p_items) loop
    select i.id, i.section_id, i.name, i.price_grosze, i.variants, i.addons, i.vat_rate, i.available, s.restaurant_id
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

    -- Zniżka na dział w czasie wydarzenia (0092).
    v_pct := private.section_discount_percent(v_item.section_id, coalesce(v_when, now()));
    if v_pct > 0 then
      v_price := round(v_price * (100 - v_pct) / 100.0)::integer;
    end if;

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
