-- Kody rabatowe (Management, wpisywane przy rezerwacji w aplikacji Table), napiwki, płatności rachunku
-- (także kilka na jeden rachunek) i podział rachunku po pozycjach.

-- ---------------------------------------------------------------
-- 1. Kody rabatowe
-- ---------------------------------------------------------------

create table public.discount_codes (
  id               uuid primary key default gen_random_uuid(),
  restaurant_id    uuid not null references public.restaurants (id) on delete cascade,
  code             text not null check (code ~ '^[A-Z0-9-]{3,20}$'),
  kind             text not null check (kind in ('percent', 'amount')),
  value            integer not null check (value > 0),
  valid_from       date,
  valid_until      date,
  max_uses         integer check (max_uses is null or max_uses > 0),
  uses             integer not null default 0 check (uses >= 0),
  active           boolean not null default true,
  note             text check (note is null or char_length(note) <= 200),
  created_by_name  text,
  created_at       timestamptz not null default now(),
  unique (restaurant_id, code),
  check (kind <> 'percent' or value between 1 and 100),
  check (valid_until is null or valid_from is null or valid_until >= valid_from)
);
alter table public.discount_codes enable row level security;
create policy discount_codes_read on public.discount_codes
  for select to authenticated using (private.has_permission(restaurant_id, 'discounts'));

alter table public.reservations
  add column if not exists discount_code_id   uuid references public.discount_codes (id) on delete set null,
  add column if not exists discount_code      text,
  add column if not exists discount_kind      text check (discount_kind is null or discount_kind in ('percent', 'amount')),
  add column if not exists discount_value     integer,
  add column if not exists discount_used_grosze integer not null default 0;

-- Kod ważny w dniu wizyty: aktywny, w terminie i z wolnym użyciem. Zwraca wiersz kodu albo błąd.
create or replace function private.valid_discount(p_restaurant_id uuid, p_code text, p_day date)
returns public.discount_codes
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_code public.discount_codes;
begin
  select * into v_code from public.discount_codes
  where restaurant_id = p_restaurant_id and code = upper(btrim(p_code));
  if not found or not v_code.active then
    raise exception 'Ten kod rabatowy nie działa w tym lokalu.';
  end if;
  if v_code.valid_from is not null and p_day < v_code.valid_from then
    raise exception 'Kod działa od %.', to_char(v_code.valid_from, 'DD.MM.YYYY');
  end if;
  if v_code.valid_until is not null and p_day > v_code.valid_until then
    raise exception 'Kod był ważny do %.', to_char(v_code.valid_until, 'DD.MM.YYYY');
  end if;
  if v_code.max_uses is not null and v_code.uses >= v_code.max_uses then
    raise exception 'Ten kod został już wykorzystany.';
  end if;
  return v_code;
end;
$$;

-- Sprawdzenie kodu w aplikacji Table przed rezerwacją: rodzaj i wartość rabatu.
create or replace function public.guest_check_discount(p_restaurant_id uuid, p_code text, p_starts_at timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_code discount_codes;
  v_tz   text;
begin
  if auth.uid() is null then
    raise exception 'Zaloguj się, żeby użyć kodu rabatowego.';
  end if;
  select coalesce(timezone, 'Europe/Warsaw') into v_tz from restaurants where id = p_restaurant_id;
  v_code := private.valid_discount(p_restaurant_id, p_code, (coalesce(p_starts_at, now()) at time zone v_tz)::date);
  return jsonb_build_object('code', v_code.code, 'kind', v_code.kind, 'value', v_code.value);
end;
$$;

create or replace function public.panel_save_discount_code(
  p_restaurant_id  uuid,
  p_id             uuid,
  p_code           text,
  p_kind           text,
  p_value          integer,
  p_valid_from     date,
  p_valid_until    date,
  p_max_uses       integer,
  p_active         boolean,
  p_note           text,
  p_member_id      uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id   uuid;
  v_code text := upper(btrim(coalesce(p_code, '')));
begin
  perform private.require_permission(p_restaurant_id, 'discounts');
  perform private.check_inventory_member(p_restaurant_id, p_member_id);
  if v_code !~ '^[A-Z0-9-]{3,20}$' then
    raise exception 'Kod ma od 3 do 20 znaków: litery bez polskich znaków, cyfry i myślnik.';
  end if;
  if p_kind not in ('percent', 'amount') then
    raise exception 'Wybierz rodzaj rabatu.';
  end if;
  if p_value is null or p_value <= 0 or (p_kind = 'percent' and p_value > 100) then
    raise exception 'Wpisz rabat: procent od 1 do 100 albo kwotę większą od zera.';
  end if;
  if p_valid_until is not null and p_valid_from is not null and p_valid_until < p_valid_from then
    raise exception 'Koniec ważności musi być po początku.';
  end if;

  if p_id is null then
    insert into discount_codes (restaurant_id, code, kind, value, valid_from, valid_until, max_uses, active, note,
                                created_by_name)
    values (p_restaurant_id, v_code, p_kind, p_value, p_valid_from, p_valid_until, p_max_uses,
            coalesce(p_active, true), nullif(btrim(p_note), ''), private.note_author(p_restaurant_id, p_member_id))
    returning id into v_id;
  else
    update discount_codes
    set code = v_code, kind = p_kind, value = p_value, valid_from = p_valid_from, valid_until = p_valid_until,
        max_uses = p_max_uses, active = coalesce(p_active, true), note = nullif(btrim(p_note), '')
    where id = p_id and restaurant_id = p_restaurant_id
    returning id into v_id;
    if v_id is null then
      raise exception 'Nie znaleziono kodu.';
    end if;
  end if;
  return v_id;
exception
  when unique_violation then
    raise exception 'Kod % już jest w tym lokalu.', v_code;
end;
$$;

create or replace function public.panel_delete_discount_code(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code discount_codes%rowtype;
begin
  select * into v_code from discount_codes where id = p_id;
  if not found then
    raise exception 'Nie znaleziono kodu.';
  end if;
  perform private.require_permission(v_code.restaurant_id, 'discounts');
  delete from discount_codes where id = p_id;
end;
$$;

-- Rezerwacja z aplikacji z kodem rabatowym. Kod jest sprawdzany na dzień wizyty i zapisany przy rezerwacji;
-- rabat odejmuje się od rachunku stolika przy zamknięciu.
drop function if exists public.book_table(uuid, timestamptz, integer, public.reservation_occasion, text, text, boolean);
create or replace function public.book_table(
  p_restaurant_id  uuid,
  p_starts_at      timestamptz,
  p_party_size     integer,
  p_occasion       public.reservation_occasion default null,
  p_message        text default null,
  p_diet           text default null,
  p_diet_consent   boolean default false,
  p_discount_code  text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_rest      record;
  v_hours     record;
  v_local     timestamp;
  v_visit     integer;
  v_cleanup   integer;
  v_ends      timestamptz;
  v_slot      tstzrange;
  v_ids       uuid[];
  v_res_id    uuid;
  v_attempt   integer := 0;
  v_upcoming  integer;
  v_code      discount_codes;
begin
  if v_uid is null then
    raise exception 'Zaloguj się, żeby zarezerwować stolik.';
  end if;

  select id, timezone, slot_interval_min, plan, max_party_size into v_rest
  from restaurants where id = p_restaurant_id;

  if not found then
    raise exception 'Nie znaleziono restauracji.';
  end if;

  if p_party_size is null or p_party_size not between 1 and v_rest.max_party_size then
    raise exception 'Rezerwacja w aplikacji obejmuje od 1 do % osób. Większą grupę umów telefonicznie.', v_rest.max_party_size;
  end if;

  if v_rest.plan <> 'pro' then
    raise exception 'Ta restauracja przyjmuje rezerwacje tylko telefonicznie.';
  end if;

  if p_starts_at < now() + interval '30 minutes' or p_starts_at > now() + interval '60 days' then
    raise exception 'Wybierz termin od 30 minut do 60 dni od teraz.';
  end if;

  v_visit   := private.visit_minutes(p_party_size);
  v_cleanup := private.cleanup_minutes(p_party_size);
  v_local   := p_starts_at at time zone v_rest.timezone;

  if extract(minute from v_local)::integer % v_rest.slot_interval_min <> 0
     or extract(second from v_local) <> 0 then
    raise exception 'Wybierz godzinę z listy wolnych terminów.';
  end if;

  select x.opens, x.closes into v_hours
  from private.hours_on(p_restaurant_id, v_local::date) as x;

  if not found
     or v_local::time < v_hours.opens
     or v_local + make_interval(mins => v_visit) > v_local::date + v_hours.closes then
    raise exception 'Restauracja jest wtedy zamknięta.';
  end if;

  if nullif(btrim(p_diet), '') is not null and not coalesce(p_diet_consent, false) then
    raise exception 'Zaznacz zgodę, żeby przekazać restauracji informację o alergiach.';
  end if;

  if nullif(btrim(p_discount_code), '') is not null then
    v_code := private.valid_discount(p_restaurant_id, p_discount_code, v_local::date);
  end if;

  select count(*) into v_upcoming
  from reservations
  where user_id = v_uid and status = 'confirmed' and starts_at > now();

  if v_upcoming >= 5 then
    raise exception 'Masz już 5 nadchodzących rezerwacji. Odwołaj jedną, żeby dodać kolejną.';
  end if;

  v_ends := p_starts_at + make_interval(mins => v_visit);
  v_slot := tstzrange(p_starts_at, v_ends + make_interval(mins => v_cleanup));

  insert into reservations (
    restaurant_id, user_id, party_size, starts_at, ends_at,
    occasion, message, message_delete_after,
    discount_code_id, discount_code, discount_kind, discount_value
  )
  values (
    p_restaurant_id, v_uid, p_party_size, p_starts_at, v_ends,
    p_occasion, nullif(btrim(p_message), ''), v_ends + interval '30 days',
    v_code.id, v_code.code, v_code.kind, v_code.value
  )
  returning id into v_res_id;

  if v_code.id is not null then
    update discount_codes set uses = uses + 1 where id = v_code.id;
  end if;

  loop
    v_attempt := v_attempt + 1;
    v_ids := private.find_tables(p_restaurant_id, p_party_size, v_slot);

    if v_ids is null then
      raise exception 'Ten termin właśnie się zajął. Wybierz inną godzinę.';
    end if;

    begin
      insert into table_holds (reservation_id, table_id, slot)
      select v_res_id, t.table_id, v_slot
      from unnest(v_ids) as t(table_id);
      exit;
    exception
      when exclusion_violation then
        if v_attempt >= 5 then
          raise exception 'Ten termin właśnie się zajął. Wybierz inną godzinę.';
        end if;
    end;
  end loop;

  if nullif(btrim(p_diet), '') is not null then
    insert into reservation_diets (reservation_id, details, delete_after)
    values (v_res_id, btrim(p_diet), v_ends + interval '30 days');
  end if;

  return v_res_id;
end;
$$;

-- Odwołana rezerwacja oddaje użycie kodu.
create or replace function private.reservation_discount_release()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.discount_code_id is not null and new.status = 'cancelled' and old.status <> 'cancelled' then
    update public.discount_codes set uses = greatest(uses - 1, 0) where id = new.discount_code_id;
  end if;
  return new;
end;
$$;
create trigger reservations_discount_release
  after update of status on public.reservations
  for each row execute function private.reservation_discount_release();

-- ---------------------------------------------------------------
-- 2. Płatności rachunku i napiwki
-- ---------------------------------------------------------------

alter table public.orders
  add column if not exists discount_grosze integer not null default 0 check (discount_grosze >= 0),
  add column if not exists discount_label  text,
  add column if not exists tip_grosze      integer not null default 0 check (tip_grosze >= 0);

create table public.order_payments (
  id             uuid primary key default gen_random_uuid(),
  order_id       uuid not null references public.orders (id) on delete cascade,
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  method         text not null check (method in ('cash', 'card', 'other')),
  amount_grosze  integer not null check (amount_grosze >= 0),
  tip_grosze     integer not null default 0 check (tip_grosze >= 0),
  member_id      uuid references public.staff_members (id) on delete set null,
  created_at     timestamptz not null default now()
);
create index order_payments_order_idx on public.order_payments (order_id);
create index order_payments_restaurant_idx on public.order_payments (restaurant_id, created_at);
alter table public.order_payments enable row level security;
create policy order_payments_read on public.order_payments
  for select to authenticated using (
    private.has_permission(restaurant_id, 'orders')
    or private.has_permission(restaurant_id, 'stats')
    or private.has_permission(restaurant_id, 'day_close')
  );

-- Rabat z kodu rezerwacji dla części rachunku o wartości p_total. Procent liczy się od każdej części,
-- kwota tylko raz na rezerwację (reszta zostaje na kolejne części).
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
    label := v_res.discount_code || ' (−' || to_char(v_res.discount_value / 100.0, 'FM999990.00') || ' zł)';
  end if;
end;
$$;

-- Płatności z aplikacji albo panelu: [{method, amount, tip}]. Suma kwot musi równać się kwocie do zapłaty.
create or replace function private.order_payments_insert(
  p_order        public.orders,
  p_due          integer,
  p_payments     jsonb,
  p_member_id    uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sum  integer := 0;
  v_tips integer := 0;
  v_p    jsonb;
begin
  if p_payments is null or jsonb_typeof(p_payments) <> 'array' or jsonb_array_length(p_payments) = 0 then
    raise exception 'Wybierz, jak gość płaci.';
  end if;
  if jsonb_array_length(p_payments) > 30 then
    raise exception 'Najwyżej 30 płatności na jeden rachunek.';
  end if;
  for v_p in select * from jsonb_array_elements(p_payments) loop
    if coalesce(v_p->>'method', '') not in ('cash', 'card', 'other') then
      raise exception 'Wybierz formę płatności.';
    end if;
    if coalesce((v_p->>'amount')::integer, -1) < 0 or coalesce((v_p->>'tip')::integer, 0) < 0 then
      raise exception 'Kwota płatności nie może być ujemna.';
    end if;
    v_sum := v_sum + (v_p->>'amount')::integer;
    v_tips := v_tips + coalesce((v_p->>'tip')::integer, 0);
  end loop;
  if v_sum <> p_due then
    raise exception 'Płatności dają %, a do zapłaty jest % zł.',
      to_char(v_sum / 100.0, 'FM999990.00'), to_char(p_due / 100.0, 'FM999990.00');
  end if;
  insert into public.order_payments (order_id, restaurant_id, method, amount_grosze, tip_grosze, member_id)
  select p_order.id, p_order.restaurant_id, p->>'method', (p->>'amount')::integer, coalesce((p->>'tip')::integer, 0), p_member_id
  from jsonb_array_elements(p_payments) p;
  return v_tips;
end;
$$;

-- Zamknięcie rachunku z rabatem z kodu, napiwkami i jedną albo kilkoma płatnościami (np. równy podział).
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

  select * into v_discount from private.order_discount(v_order.reservation_id, v_total);
  v_tips := private.order_payments_insert(v_order, v_total - v_discount.amount, p_payments, p_member_id);
  select array_agg(distinct p->>'method') into v_methods from jsonb_array_elements(p_payments) p;

  update order_items set status = 'served' where order_id = p_order_id and status in ('new', 'sent', 'ready');
  update orders
  set status = 'paid',
      payment_method = case when array_length(v_methods, 1) = 1 then v_methods[1] else 'other' end,
      discount_grosze = v_discount.amount,
      discount_label = v_discount.label,
      tip_grosze = v_tips,
      closed_at = now(),
      closed_by = auth.uid(),
      closed_by_member = p_member_id
  where id = p_order_id;

  if v_order.reservation_id is not null then
    if v_discount.amount > 0 then
      update reservations set discount_used_grosze = discount_used_grosze + v_discount.amount
      where id = v_order.reservation_id;
    end if;
    update reservations set status = 'completed', updated_at = now()
    where id = v_order.reservation_id and status = 'seated';
    if found then
      update table_holds
      set slot = tstzrange(lower(slot), greatest(lower(slot), now()) + interval '1 second'),
          active = false
      where reservation_id = v_order.reservation_id;
    end if;
  end if;

  return jsonb_build_object('total', v_total, 'discount', v_discount.amount, 'due', v_total - v_discount.amount,
                            'tip', v_tips);
end;
$$;

-- Podział po pozycjach: gość płaci za wybrane pozycje [{id, quantity}], które przechodzą na osobny,
-- od razu opłacony rachunek. Reszta zostaje na stoliku. Wybór wszystkiego zamyka cały rachunek.
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

  -- Wartość wybranych pozycji i sprawdzenie ilości.
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

  -- Część płaci tylko rabat procentowy; rabat kwotowy zostaje na zamknięcie reszty rachunku.
  select * into v_discount from private.order_discount(v_order.reservation_id, v_part);
  if exists (select 1 from reservations where id = v_order.reservation_id and discount_kind = 'amount') then
    v_discount.amount := 0;
    v_discount.label := null;
  end if;
  v_tips := private.order_payments_insert(v_new, v_part - v_discount.amount, p_payments, p_member_id);
  select array_agg(distinct p->>'method') into v_methods from jsonb_array_elements(p_payments) p;

  update order_items set status = 'served' where order_id = v_new_id and status in ('new', 'sent', 'ready');
  update orders
  set payment_method = case when array_length(v_methods, 1) = 1 then v_methods[1] else 'other' end,
      discount_grosze = v_discount.amount,
      discount_label = v_discount.label,
      tip_grosze = v_tips,
      closed_at = now(),
      closed_by = auth.uid(),
      closed_by_member = p_member_id
  where id = v_new_id;

  return jsonb_build_object('total', v_part, 'discount', v_discount.amount, 'due', v_part - v_discount.amount,
                            'tip', v_tips, 'left', v_left, 'order_id', v_new_id);
end;
$$;

-- Ile do zapłaty przed zamknięciem: suma, rabat z kodu rezerwacji i kwota po rabacie.
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
begin
  select * into v_order from orders where id = p_order_id;
  if not found then
    raise exception 'Nie znaleziono rachunku.';
  end if;
  perform private.require_permission(v_order.restaurant_id, 'orders');
  select coalesce(sum(unit_price_grosze * quantity), 0) into v_total
  from order_items where order_id = p_order_id and status <> 'cancelled';
  select * into v_discount from private.order_discount(v_order.reservation_id, v_total);
  return jsonb_build_object(
    'total', v_total,
    'discount', v_discount.amount,
    'discount_label', v_discount.label,
    'discount_percent', (select discount_value from reservations where id = v_order.reservation_id and discount_kind = 'percent'),
    'due', v_total - v_discount.amount
  );
end;
$$;

-- ---------------------------------------------------------------
-- 3. Podsumowanie dnia z płatnościami, rabatami i napiwkami
-- ---------------------------------------------------------------

create or replace function public.panel_day_summary(p_restaurant_id uuid, p_day date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_start timestamptz;
  v_end   timestamptz;
begin
  perform private.require_permission(p_restaurant_id, 'day_close');
  select starts, ends into v_start, v_end from private.day_range(p_restaurant_id, p_day);
  return (
    with paid as (
      select o.id, o.kind, o.payment_method, o.payment_choice, o.discount_grosze, o.tip_grosze,
             (select coalesce(sum(i.unit_price_grosze * i.quantity), 0)
              from order_items i where i.order_id = o.id and i.status <> 'cancelled')
             + coalesce(o.delivery_fee_grosze, 0) - o.discount_grosze as total
      from orders o
      where o.restaurant_id = p_restaurant_id and o.status = 'paid'
        and o.closed_at >= v_start and o.closed_at < v_end
    ),
    -- Płatności z tabeli; starsze rachunki i zamówienia na wynos mają jedną płatność w samym zamówieniu.
    methods as (
      select p.method, p.amount_grosze as amount, p.tip_grosze as tip
      from order_payments p join paid o on o.id = p.order_id
      union all
      select case
               when o.payment_choice = 'card_online' then 'card_online'
               when o.payment_method in ('cash', 'card') then o.payment_method
               else 'other'
             end,
             o.total, o.tip_grosze
      from paid o
      where not exists (select 1 from order_payments p where p.order_id = o.id)
    ),
    petty as (
      select * from petty_cash where restaurant_id = p_restaurant_id and day = p_day
    )
    select jsonb_build_object(
      'day', p_day,
      'revenue', coalesce((select sum(total) from paid), 0),
      'orders', (select count(*) from paid),
      'dine_in', (select count(*) from paid where kind = 'dine_in'),
      'takeaway', (select count(*) from paid where kind <> 'dine_in'),
      'cash', coalesce((select sum(amount) from methods where method = 'cash'), 0),
      'card', coalesce((select sum(amount) from methods where method = 'card'), 0),
      'card_online', coalesce((select sum(amount) from methods where method = 'card_online'), 0),
      'other', coalesce((select sum(amount) from methods where method = 'other'), 0),
      'tips', coalesce((select sum(tip) from methods), 0),
      'tips_cash', coalesce((select sum(tip) from methods where method = 'cash'), 0),
      'tips_card', coalesce((select sum(tip) from methods where method = 'card'), 0),
      'discounts', coalesce((select sum(discount_grosze) from paid), 0),
      'cancelled', (select count(*) from orders o where o.restaurant_id = p_restaurant_id and o.status = 'cancelled'
                    and o.closed_at >= v_start and o.closed_at < v_end),
      'petty_out', coalesce((select sum(amount_grosze) from petty where kind = 'out'), 0),
      'petty_in', coalesce((select sum(amount_grosze) from petty where kind = 'in'), 0),
      'petty', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', id, 'kind', kind, 'description', description, 'amount_grosze', amount_grosze,
          'author_name', author_name, 'created_at', created_at
        ) order by created_at)
        from petty
      ), '[]'::jsonb),
      'report', (
        select jsonb_build_object(
          'fiscal_grosze', r.fiscal_grosze, 'terminals', r.terminals, 'cash_counted_grosze', r.cash_counted_grosze,
          'note', r.note, 'updated_at', r.updated_at, 'updated_by_name', r.updated_by_name
        )
        from day_reports r where r.restaurant_id = p_restaurant_id and r.day = p_day
      )
    )
  );
end;
$$;

revoke execute on function private.valid_discount(uuid, text, date) from public, anon;
revoke execute on function private.reservation_discount_release() from public, anon;
revoke execute on function private.order_discount(uuid, integer) from public, anon;
revoke execute on function private.order_payments_insert(public.orders, integer, jsonb, uuid) from public, anon;
revoke execute on function public.guest_check_discount(uuid, text, timestamptz) from public, anon;
revoke execute on function public.panel_save_discount_code(uuid, uuid, text, text, integer, date, date, integer, boolean, text, uuid) from public, anon;
revoke execute on function public.panel_delete_discount_code(uuid) from public, anon;
revoke execute on function public.book_table(uuid, timestamptz, integer, public.reservation_occasion, text, text, boolean, text) from public, anon;
revoke execute on function public.panel_settle_order(uuid, jsonb, uuid) from public, anon;
revoke execute on function public.panel_pay_items(uuid, jsonb, jsonb, uuid) from public, anon;
revoke execute on function public.panel_order_due(uuid) from public, anon;
grant execute on function private.valid_discount(uuid, text, date) to authenticated;
grant execute on function private.order_discount(uuid, integer) to authenticated;
grant execute on function private.order_payments_insert(public.orders, integer, jsonb, uuid) to authenticated;
grant execute on function public.guest_check_discount(uuid, text, timestamptz) to authenticated;
grant execute on function public.panel_save_discount_code(uuid, uuid, text, text, integer, date, date, integer, boolean, text, uuid) to authenticated;
grant execute on function public.panel_delete_discount_code(uuid) to authenticated;
grant execute on function public.book_table(uuid, timestamptz, integer, public.reservation_occasion, text, text, boolean, text) to authenticated;
grant execute on function public.panel_settle_order(uuid, jsonb, uuid) to authenticated;
grant execute on function public.panel_pay_items(uuid, jsonb, jsonb, uuid) to authenticated;
grant execute on function public.panel_order_due(uuid) to authenticated;
