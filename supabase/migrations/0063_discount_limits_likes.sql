-- 0063: kody rabatowe z minimalną kwotą rachunku i limitem użyć na jednego gościa;
-- polubione lokale w aplikacji Table i polubienia w statystykach panelu.

-- ---------------------------------------------------------------
-- 1. Kody rabatowe: minimalna kwota i limit na gościa
-- ---------------------------------------------------------------

alter table public.discount_codes
  -- Rabat działa dopiero od tej kwoty rachunku (przed rabatem). Null: od każdej kwoty.
  add column if not exists min_total_grosze integer check (min_total_grosze is null or min_total_grosze > 0),
  -- Ile razy jeden gość (konto w aplikacji) może użyć kodu. Null: bez limitu. Limit łączny to max_uses.
  add column if not exists max_uses_per_guest integer check (max_uses_per_guest is null or max_uses_per_guest > 0);

-- Minimalna kwota z chwili użycia kodu (jak rodzaj i wartość rabatu), żeby zmiana kodu nie zmieniała starych rachunków.
alter table public.reservations add column if not exists discount_min_grosze integer;
alter table public.orders add column if not exists discount_min_grosze integer;

-- Gość z kontem przekroczył limit użyć kodu na osobę (rezerwacje bez odwołanych). [p_exclude]: ta sama rezerwacja.
create or replace function private.check_guest_discount(
  p_code public.discount_codes,
  p_user uuid,
  p_exclude uuid default null
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_used integer;
begin
  if p_code.max_uses_per_guest is null or p_user is null then
    return;
  end if;
  select count(*) into v_used
  from public.reservations r
  where r.discount_code_id = p_code.id
    and r.user_id = p_user
    and r.status <> 'cancelled'
    and (p_exclude is null or r.id <> p_exclude);
  if v_used >= p_code.max_uses_per_guest then
    if p_code.max_uses_per_guest = 1 then
      raise exception 'Ten kod można użyć tylko raz, a już go użyłeś.';
    end if;
    raise exception 'Ten kod można użyć najwyżej % razy na osobę.', p_code.max_uses_per_guest;
  end if;
end;
$$;

-- Rezerwacja z kodem: limit na gościa i minimalna kwota z kodu.
create or replace function private.reservation_discount_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code public.discount_codes;
begin
  if new.discount_code_id is null then
    new.discount_min_grosze := null;
    return new;
  end if;
  if tg_op = 'UPDATE' and new.discount_code_id is not distinct from old.discount_code_id then
    return new;
  end if;
  select * into v_code from public.discount_codes where id = new.discount_code_id;
  if found then
    perform private.check_guest_discount(v_code, new.user_id, new.id);
    new.discount_min_grosze := v_code.min_total_grosze;
  end if;
  return new;
end;
$$;

drop trigger if exists reservations_discount_guard on public.reservations;
create trigger reservations_discount_guard
  before insert or update of discount_code_id on public.reservations
  for each row execute function private.reservation_discount_guard();

-- Kod wpisany przy rachunku: minimalna kwota z kodu.
create or replace function private.order_discount_min()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.discount_code_id is null then
    new.discount_min_grosze := null;
  elsif tg_op = 'INSERT' or new.discount_code_id is distinct from old.discount_code_id then
    new.discount_min_grosze := (select c.min_total_grosze from public.discount_codes c where c.id = new.discount_code_id);
  end if;
  return new;
end;
$$;

drop trigger if exists orders_discount_min on public.orders;
create trigger orders_discount_min
  before insert or update of discount_code_id on public.orders
  for each row execute function private.order_discount_min();

-- Rabat rachunku z progiem: poniżej minimalnej kwoty rabatu nie ma, a [min_missing] mówi, ile brakuje.
-- [p_basis]: kwota, od której liczy się próg (przy płatności za część: cały rachunek). Domyślnie [p_total].
drop function if exists private.bill_discount(public.orders, integer);
create function private.bill_discount(
  p_order public.orders,
  p_total integer,
  p_basis integer default null,
  out amount integer,
  out label text,
  out kind text,
  out percent integer,
  out min_total integer,
  out min_missing integer
)
returns record
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_res   record;
  v_basis integer := coalesce(p_basis, p_total);
begin
  amount := 0;
  label := null;
  kind := null;
  percent := null;
  min_total := null;
  min_missing := null;
  if p_order.discount_kind is null then
    select r.discount_min_grosze into min_total
    from public.reservations r
    where r.id = p_order.reservation_id and r.discount_kind is not null;
    if min_total is not null and v_basis < min_total then
      min_missing := min_total - v_basis;
      return;
    end if;
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
  min_total := p_order.discount_min_grosze;
  if min_total is not null and v_basis < min_total then
    min_missing := min_total - v_basis;
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

-- Kwota do zapłaty z informacją o progu kodu.
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
    'discount_min', v_discount.min_total,
    'discount_missing', v_discount.min_missing,
    'deposit', v_deposit,
    'due', v_total - v_discount.amount - v_deposit
  );
end;
$$;

-- Zamknięcie rachunku: użycie kodu liczy się tylko, gdy rabat naprawdę był (kwota powyżej progu).
create or replace function public.panel_settle_order(p_order_id uuid, p_payments jsonb, p_member_id uuid default null)
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

  if v_order.discount_code_id is not null and v_discount.amount > 0 then
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

-- Płatność za część rachunku: próg kodu liczy się od całego rachunku, nie od części.
create or replace function public.panel_pay_items(p_order_id uuid, p_items jsonb, p_payments jsonb, p_member_id uuid default null)
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

  select * into v_discount from private.bill_discount(v_order, v_part, v_part + v_left);
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

-- Gość sprawdza kod przed rezerwacją: też limit na osobę; odpowiedź z minimalną kwotą.
create or replace function public.guest_check_discount(
  p_restaurant_id uuid,
  p_code text,
  p_starts_at timestamptz default null
)
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
  perform private.check_guest_discount(v_code, auth.uid());
  return jsonb_build_object(
    'code', v_code.code,
    'kind', v_code.kind,
    'value', v_code.value,
    'min_total', v_code.min_total_grosze
  );
end;
$$;

-- Podpowiedzi kodów przy rachunku: z minimalną kwotą.
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
      'uses_left', case when c.max_uses is null then null else c.max_uses - c.uses end,
      'min_total', c.min_total_grosze
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

-- Zapis kodu z minimalną kwotą i limitem na gościa.
drop function if exists public.panel_save_discount_code(uuid, uuid, text, text, integer, date, date, integer, boolean, text, uuid);
create function public.panel_save_discount_code(
  p_restaurant_id   uuid,
  p_id              uuid,
  p_code            text,
  p_kind            text,
  p_value           integer,
  p_valid_from      date,
  p_valid_until     date,
  p_max_uses        integer,
  p_active          boolean,
  p_note            text,
  p_member_id       uuid default null,
  p_min_total       integer default null,
  p_max_per_guest   integer default null
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
  if p_max_uses is not null and p_max_uses <= 0 then
    raise exception 'Limit użyć musi być większy od zera.';
  end if;
  if p_max_per_guest is not null and p_max_per_guest <= 0 then
    raise exception 'Limit na gościa musi być większy od zera.';
  end if;
  if p_max_per_guest is not null and p_max_uses is not null and p_max_per_guest > p_max_uses then
    raise exception 'Limit na gościa nie może być większy niż limit użyć łącznie.';
  end if;
  if p_min_total is not null and p_min_total <= 0 then
    raise exception 'Minimalna kwota musi być większa od zera.';
  end if;
  if p_kind = 'amount' and p_min_total is not null and p_min_total < p_value then
    raise exception 'Minimalna kwota rachunku nie może być mniejsza niż rabat.';
  end if;

  if p_id is null then
    insert into discount_codes (restaurant_id, code, kind, value, valid_from, valid_until, max_uses, active, note,
                                created_by_name, min_total_grosze, max_uses_per_guest)
    values (p_restaurant_id, v_code, p_kind, p_value, p_valid_from, p_valid_until, p_max_uses,
            coalesce(p_active, true), nullif(btrim(p_note), ''), private.note_author(p_restaurant_id, p_member_id),
            p_min_total, p_max_per_guest)
    returning id into v_id;
  else
    update discount_codes
    set code = v_code, kind = p_kind, value = p_value, valid_from = p_valid_from, valid_until = p_valid_until,
        max_uses = p_max_uses, active = coalesce(p_active, true), note = nullif(btrim(p_note), ''),
        min_total_grosze = p_min_total, max_uses_per_guest = p_max_per_guest
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

-- ---------------------------------------------------------------
-- 2. Polubione lokale
-- ---------------------------------------------------------------

create table if not exists public.restaurant_likes (
  user_id        uuid not null references auth.users (id) on delete cascade,
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  created_at     timestamptz not null default now(),
  primary key (user_id, restaurant_id)
);
create index if not exists restaurant_likes_restaurant on public.restaurant_likes (restaurant_id, created_at);
alter table public.restaurant_likes enable row level security;
-- Gość widzi tylko swoje polubienia; zapis przez guest_set_like. Lokal widzi same liczby (panel_stats).
drop policy if exists restaurant_likes_own on public.restaurant_likes;
create policy restaurant_likes_own on public.restaurant_likes
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.restaurant_likes from anon;
grant select on public.restaurant_likes to authenticated;

-- Polub albo przestań lubić lokal. Zwraca stan po zmianie.
create or replace function public.guest_set_like(p_restaurant_id uuid, p_liked boolean)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Zaloguj się, żeby polubić lokal.';
  end if;
  if p_liked then
    if not exists (select 1 from restaurants where id = p_restaurant_id and listed) then
      raise exception 'Nie znaleziono lokalu.';
    end if;
    insert into restaurant_likes (user_id, restaurant_id) values (auth.uid(), p_restaurant_id)
    on conflict do nothing;
  else
    delete from restaurant_likes where user_id = auth.uid() and restaurant_id = p_restaurant_id;
  end if;
  return p_liked;
end;
$$;

-- Moje polubione lokale jako karty (te same pola co search_restaurants), ostatnio polubione pierwsze.
create or replace function public.guest_liked_restaurants(p_lat double precision default null, p_lng double precision default null)
returns table (
  id uuid, name text, cuisine text, price_level smallint, address text, city text, plan restaurant_plan,
  is_example boolean, logo_url text, distance_m double precision, verified_reviews integer,
  unverified_reviews integer, food_avg numeric, service_avg numeric, ambience_avg numeric, food_score numeric,
  cover_url text, delivery_enabled boolean, pickup_enabled boolean, matched_dish text, liked_at timestamptz
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with liked as (
    select l.restaurant_id, l.created_at
    from restaurant_likes l
    where l.user_id = auth.uid()
  ),
  stats as (
    select
      rv.restaurant_id,
      count(*) filter (where rv.verification <> 'none')          as verified,
      count(*) filter (where rv.verification = 'none')           as unverified,
      avg(rv.food) filter (where rv.verification <> 'none')      as food_avg,
      avg(rv.service) filter (where rv.verification <> 'none')   as service_avg,
      avg(rv.ambience) filter (where rv.verification <> 'none')  as ambience_avg
    from reviews rv
    join liked l on l.restaurant_id = rv.restaurant_id
    group by rv.restaurant_id
  )
  select
    r.id, r.name, r.cuisine, r.price_level, r.address, r.city, r.plan, r.is_example, r.logo_url,
    case
      when p_lat is null or p_lng is null then 0
      else st_distance(r.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography)
    end,
    coalesce(s.verified, 0)::integer,
    coalesce(s.unverified, 0)::integer,
    round(s.food_avg, 2), round(s.service_avg, 2), round(s.ambience_avg, 2),
    case
      when coalesce(s.verified, 0) = 0 then null
      else round((s.verified::numeric / (s.verified + 10)) * s.food_avg + (10::numeric / (s.verified + 10)) * 4.0, 3)
    end,
    coalesce(
      r.cover_url,
      (
        select i.photo_url
        from menu_items i
        join menu_sections ms on ms.id = i.section_id
        where ms.restaurant_id = r.id and i.photo_url is not null and i.available
        order by ms.position, i.position
        limit 1
      )
    ),
    r.delivery_enabled, r.pickup_enabled, null::text, l.created_at
  from liked l
  join restaurants r on r.id = l.restaurant_id and r.listed
  left join stats s on s.restaurant_id = r.id
  order by l.created_at desc
$$;

-- Statystyki dzienne panelu z polubieniami: nowe tego dnia i wszystkie do końca dnia.
drop function if exists public.panel_stats(uuid, integer);
create function public.panel_stats(p_restaurant_id uuid, p_days integer default 30)
returns table (
  day date, views integer, call_clicks integer, reservations integer, covers integer, cancellations integer,
  no_shows integer, likes integer, likes_total integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz    text;
  v_days  integer := least(greatest(coalesce(p_days, 30), 1), 366);
begin
  perform private.require_staff(p_restaurant_id);

  select timezone into v_tz from restaurants where id = p_restaurant_id;

  return query
  with days as (
    select generate_series(
      (now() at time zone v_tz)::date - (v_days - 1),
      (now() at time zone v_tz)::date,
      interval '1 day'
    )::date as day
  ),
  ev as (
    select (e.created_at at time zone v_tz)::date as day,
           count(*) filter (where e.kind = 'view') as views,
           count(*) filter (where e.kind = 'call_click') as calls
    from restaurant_events e
    where e.restaurant_id = p_restaurant_id
      and e.created_at >= now() - make_interval(days => v_days + 1)
    group by 1
  ),
  rs as (
    select (r.starts_at at time zone v_tz)::date as day,
           count(*) filter (where r.status not in ('cancelled')) as res,
           coalesce(sum(r.party_size) filter (where r.status in ('confirmed', 'seated', 'completed')), 0) as covers,
           count(*) filter (where r.status = 'cancelled') as cancels,
           count(*) filter (where r.status = 'no_show') as no_shows
    from reservations r
    where r.restaurant_id = p_restaurant_id
      and r.source <> 'block'
      and r.starts_at >= now() - make_interval(days => v_days + 1)
      and r.starts_at < now() + interval '1 day'
    group by 1
  ),
  lk as (
    select (l.created_at at time zone v_tz)::date as day, count(*) as likes
    from restaurant_likes l
    where l.restaurant_id = p_restaurant_id
    group by 1
  )
  select d.day,
         coalesce(ev.views, 0)::integer,
         coalesce(ev.calls, 0)::integer,
         coalesce(rs.res, 0)::integer,
         coalesce(rs.covers, 0)::integer,
         coalesce(rs.cancels, 0)::integer,
         coalesce(rs.no_shows, 0)::integer,
         coalesce((select lk.likes from lk where lk.day = d.day), 0)::integer,
         coalesce((select sum(lk.likes) from lk where lk.day <= d.day), 0)::integer
  from days d
  left join ev on ev.day = d.day
  left join rs on rs.day = d.day
  order by d.day;
end;
$$;

-- ---------------------------------------------------------------
-- 3. Uprawnienia funkcji
-- ---------------------------------------------------------------

revoke execute on function private.check_guest_discount(public.discount_codes, uuid, uuid) from public, anon, authenticated;
revoke execute on function private.reservation_discount_guard() from public, anon, authenticated;
revoke execute on function private.order_discount_min() from public, anon, authenticated;
revoke execute on function private.bill_discount(public.orders, integer, integer) from public, anon;
grant execute on function private.bill_discount(public.orders, integer, integer) to authenticated;

revoke execute on function public.panel_order_due(uuid) from public, anon;
revoke execute on function public.panel_settle_order(uuid, jsonb, uuid) from public, anon;
revoke execute on function public.panel_pay_items(uuid, jsonb, jsonb, uuid) from public, anon;
revoke execute on function public.guest_check_discount(uuid, text, timestamptz) from public, anon;
revoke execute on function public.panel_discount_suggestions(uuid, text) from public, anon;
revoke execute on function public.panel_save_discount_code(uuid, uuid, text, text, integer, date, date, integer, boolean, text, uuid, integer, integer) from public, anon;
revoke execute on function public.guest_set_like(uuid, boolean) from public, anon;
revoke execute on function public.guest_liked_restaurants(double precision, double precision) from public, anon;
revoke execute on function public.panel_stats(uuid, integer) from public, anon;

grant execute on function public.panel_order_due(uuid) to authenticated;
grant execute on function public.panel_settle_order(uuid, jsonb, uuid) to authenticated;
grant execute on function public.panel_pay_items(uuid, jsonb, jsonb, uuid) to authenticated;
grant execute on function public.guest_check_discount(uuid, text, timestamptz) to authenticated;
grant execute on function public.panel_discount_suggestions(uuid, text) to authenticated;
grant execute on function public.panel_save_discount_code(uuid, uuid, text, text, integer, date, date, integer, boolean, text, uuid, integer, integer) to authenticated;
grant execute on function public.guest_set_like(uuid, boolean) to authenticated;
grant execute on function public.guest_liked_restaurants(double precision, double precision) to authenticated;
grant execute on function public.panel_stats(uuid, integer) to authenticated;
