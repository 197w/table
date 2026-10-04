-- Zadatek przy rezerwacji w aplikacji: lokal ustawia, od ilu osób i ile za osobę. Gość płaci kartą
-- (na razie w trybie testowym), zadatek odejmuje się od rachunku stolika. Odwołanie przez gościa zwraca zadatek,
-- nieobecność go nie zwraca. Panel i aplikacja widzą kod rabatowy i zadatek przy rezerwacji.

alter table public.restaurants
  add column if not exists deposit_min_party smallint check (deposit_min_party is null or deposit_min_party between 1 and 30),
  add column if not exists deposit_per_person_grosze integer check (deposit_per_person_grosze is null or deposit_per_person_grosze between 100 and 100000);
grant select (deposit_min_party, deposit_per_person_grosze) on public.restaurants to anon, authenticated;

alter table public.reservations
  add column if not exists deposit_grosze      integer not null default 0 check (deposit_grosze >= 0),
  add column if not exists deposit_status      text not null default 'none'
    check (deposit_status in ('none', 'pending', 'paid', 'refunded')),
  add column if not exists deposit_paid_at     timestamptz,
  add column if not exists deposit_test        boolean not null default false,
  add column if not exists deposit_used_grosze integer not null default 0 check (deposit_used_grosze >= 0);

alter table public.orders
  add column if not exists deposit_grosze integer not null default 0 check (deposit_grosze >= 0);

-- Ustawienie zadatku w „Ustawienia lokalu”. Null wyłącza zadatek.
create or replace function public.panel_set_deposit(p_restaurant_id uuid, p_min_party integer, p_per_person integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.require_permission(p_restaurant_id, 'profile');
  if (p_min_party is null) <> (p_per_person is null) then
    raise exception 'Wpisz oba: od ilu osób i ile za osobę.';
  end if;
  if p_min_party is not null and (p_min_party not between 1 and 30 or p_per_person not between 100 and 100000) then
    raise exception 'Zadatek: od 1 do 30 osób, od 1 do 1000 zł za osobę.';
  end if;
  update restaurants set deposit_min_party = p_min_party, deposit_per_person_grosze = p_per_person
  where id = p_restaurant_id;
end;
$$;

-- Rezerwacja z aplikacji: kod rabatowy i zadatek (oczekuje na płatność od razu po rezerwacji).
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
  v_deposit   integer := 0;
begin
  if v_uid is null then
    raise exception 'Zaloguj się, żeby zarezerwować stolik.';
  end if;

  select id, timezone, slot_interval_min, plan, max_party_size, deposit_min_party, deposit_per_person_grosze
  into v_rest
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

  if v_rest.deposit_min_party is not null and p_party_size >= v_rest.deposit_min_party then
    v_deposit := v_rest.deposit_per_person_grosze * p_party_size;
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
    discount_code_id, discount_code, discount_kind, discount_value,
    deposit_grosze, deposit_status
  )
  values (
    p_restaurant_id, v_uid, p_party_size, p_starts_at, v_ends,
    p_occasion, nullif(btrim(p_message), ''), v_ends + interval '30 days',
    v_code.id, v_code.code, v_code.kind, v_code.value,
    v_deposit, case when v_deposit > 0 then 'pending' else 'none' end
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

-- Testowa płatność zadatku (bez operatora płatności nic nie jest pobierane).
create or replace function public.guest_pay_deposit_test(p_reservation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_res reservations%rowtype;
begin
  if not public.payments_test_mode() then
    raise exception 'Płatności testowe są wyłączone.';
  end if;
  select * into v_res from reservations where id = p_reservation_id and user_id = auth.uid() for update;
  if not found then
    raise exception 'Nie znaleziono rezerwacji.';
  end if;
  if v_res.deposit_status = 'paid' then
    return;
  end if;
  if v_res.deposit_status <> 'pending' or v_res.status <> 'confirmed' then
    raise exception 'Tej rezerwacji nie można już opłacić.';
  end if;
  update reservations set deposit_status = 'paid', deposit_paid_at = now(), deposit_test = true, updated_at = now()
  where id = p_reservation_id;
end;
$$;

-- Odwołanie przez gościa albo lokal oddaje zadatek; nieobecność go zostawia lokalowi.
create or replace function private.reservation_deposit_refund()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'cancelled' and old.status <> 'cancelled' and new.deposit_status = 'paid' then
    new.deposit_status := 'refunded';
  elsif new.status = 'cancelled' and old.status <> 'cancelled' and new.deposit_status = 'pending' then
    new.deposit_status := 'none';
  end if;
  return new;
end;
$$;
create trigger reservations_deposit_refund
  before update of status on public.reservations
  for each row execute function private.reservation_deposit_refund();

-- Zadatek do odjęcia od rachunku: opłacony i jeszcze niewykorzystany.
create or replace function private.order_deposit(p_reservation_id uuid, p_due integer)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select least(greatest(p_due, 0), greatest(r.deposit_grosze - r.deposit_used_grosze, 0))
    from public.reservations r
    where r.id = p_reservation_id and r.deposit_status = 'paid'
  ), 0)
$$;

-- Zamknięcie rachunku: rabat z kodu, potem zadatek, reszta w płatnościach.
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

  select * into v_discount from private.order_discount(v_order.reservation_id, v_total);
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

  if v_order.reservation_id is not null then
    update reservations
    set discount_used_grosze = discount_used_grosze + v_discount.amount,
        deposit_used_grosze = deposit_used_grosze + v_deposit
    where id = v_order.reservation_id and (v_discount.amount > 0 or v_deposit > 0);
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
  select * into v_discount from private.order_discount(v_order.reservation_id, v_total);
  v_deposit := private.order_deposit(v_order.reservation_id, v_total - v_discount.amount);
  return jsonb_build_object(
    'total', v_total,
    'discount', v_discount.amount,
    'discount_label', v_discount.label,
    'discount_percent', (select discount_value from reservations where id = v_order.reservation_id and discount_kind = 'percent'),
    'deposit', v_deposit,
    'due', v_total - v_discount.amount - v_deposit
  );
end;
$$;

-- Podsumowanie dnia: zadatek odjęty od rachunku liczy się jako karta online (gość zapłacił go w aplikacji).
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
      select o.id, o.kind, o.payment_method, o.payment_choice, o.discount_grosze, o.tip_grosze, o.deposit_grosze,
             (select coalesce(sum(i.unit_price_grosze * i.quantity), 0)
              from order_items i where i.order_id = o.id and i.status <> 'cancelled')
             + coalesce(o.delivery_fee_grosze, 0) - o.discount_grosze as total
      from orders o
      where o.restaurant_id = p_restaurant_id and o.status = 'paid'
        and o.closed_at >= v_start and o.closed_at < v_end
    ),
    methods as (
      select p.method, p.amount_grosze as amount, p.tip_grosze as tip
      from order_payments p join paid o on o.id = p.order_id
      union all
      select 'card_online', o.deposit_grosze, 0 from paid o where o.deposit_grosze > 0
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
      'deposits', coalesce((select sum(deposit_grosze) from paid), 0),
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

-- Rezerwacje w panelu z kodem rabatowym i zadatkiem.
drop function if exists public.panel_reservations(uuid, timestamptz, timestamptz);
create or replace function public.panel_reservations(
  p_restaurant_id  uuid,
  p_from           timestamptz,
  p_to             timestamptz
)
returns table (
  id             uuid,
  starts_at      timestamptz,
  ends_at        timestamptz,
  party_size     smallint,
  status         public.reservation_status,
  source         public.reservation_source,
  occasion       public.reservation_occasion,
  message        text,
  diet           text,
  guest_name     text,
  guest_phone    text,
  staff_note     text,
  seated_at      timestamptz,
  created_at     timestamptz,
  table_ids      uuid[],
  table_labels   text[],
  from_app       boolean,
  guest_visits   integer,
  guest_no_shows integer,
  discount_code  text,
  discount_kind  text,
  discount_value integer,
  deposit_grosze integer,
  deposit_status text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform private.require_staff(p_restaurant_id);

  if p_to <= p_from or p_to - p_from > interval '93 days' then
    raise exception 'Wybierz zakres do 3 miesięcy.';
  end if;

  return query
  select
    r.id, r.starts_at, r.ends_at, r.party_size, r.status, r.source, r.occasion,
    case when coalesce(r.message_delete_after, 'infinity') > now() then r.message end,
    case when d.delete_after > now() then d.details end,
    coalesce(
      nullif(btrim(r.guest_name), ''),
      nullif(btrim(p.full_name), ''),
      nullif(btrim(p.first_name), ''),
      case when r.source = 'block' then 'Blokada stolika' else 'Gość' end
    ),
    coalesce(r.guest_phone, case when u.phone is not null and u.phone <> '' then '+' || u.phone end),
    r.staff_note,
    r.seated_at,
    r.created_at,
    coalesce(h.ids, '{}'),
    coalesce(h.labels, '{}'),
    r.user_id is not null,
    coalesce(g.visits, 0),
    coalesce(g.no_shows, 0),
    r.discount_code,
    r.discount_kind,
    r.discount_value,
    r.deposit_grosze,
    r.deposit_status
  from reservations r
  left join reservation_diets d on d.reservation_id = r.id
  left join profiles p on p.id = r.user_id
  left join auth.users u on u.id = r.user_id
  left join lateral (
    select array_agg(t.id order by t.label) as ids, array_agg(t.label order by t.label) as labels
    from table_holds th
    join dining_tables t on t.id = th.table_id
    where th.reservation_id = r.id
  ) h on true
  left join lateral (
    select
      count(*) filter (where o.status in ('seated', 'completed'))::integer as visits,
      count(*) filter (where o.status = 'no_show')::integer as no_shows
    from reservations o
    where r.user_id is not null
      and o.user_id = r.user_id
      and o.restaurant_id = r.restaurant_id
      and o.starts_at < r.starts_at
  ) g on true
  where r.restaurant_id = p_restaurant_id
    and r.starts_at >= p_from
    and r.starts_at < p_to
  order by r.starts_at, r.created_at;
end;
$$;

-- Szczegóły rezerwacji w aplikacji z kodem rabatowym i zadatkiem.
drop function if exists public.reservation_details(uuid);
create or replace function public.reservation_details(p_reservation_id uuid)
returns table (
  id               uuid,
  restaurant_id    uuid,
  restaurant_name  text,
  address          text,
  city             text,
  phone            text,
  lat              double precision,
  lng              double precision,
  party_size       smallint,
  starts_at        timestamptz,
  ends_at          timestamptz,
  status           public.reservation_status,
  occasion         public.reservation_occasion,
  message          text,
  diet             text,
  reviewed         boolean,
  discount_code    text,
  discount_kind    text,
  discount_value   integer,
  deposit_grosze   integer,
  deposit_status   text
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select
    r.id, r.restaurant_id, s.name, s.address, s.city, s.phone,
    st_y(s.location::geometry), st_x(s.location::geometry),
    r.party_size, r.starts_at, r.ends_at, r.status, r.occasion, r.message,
    d.details,
    exists (select 1 from reviews rv where rv.reservation_id = r.id),
    r.discount_code, r.discount_kind, r.discount_value, r.deposit_grosze, r.deposit_status
  from reservations r
  join restaurants s on s.id = r.restaurant_id
  left join reservation_diets d on d.reservation_id = r.id
  where r.id = p_reservation_id
    and r.user_id = auth.uid()
$$;

revoke execute on function public.panel_set_deposit(uuid, integer, integer) from public, anon;
revoke execute on function public.guest_pay_deposit_test(uuid) from public, anon;
revoke execute on function private.reservation_deposit_refund() from public, anon;
revoke execute on function private.order_deposit(uuid, integer) from public, anon;
revoke execute on function public.panel_reservations(uuid, timestamptz, timestamptz) from public, anon;
revoke execute on function public.reservation_details(uuid) from public, anon;
grant execute on function public.panel_set_deposit(uuid, integer, integer) to authenticated;
grant execute on function public.guest_pay_deposit_test(uuid) to authenticated;
grant execute on function private.order_deposit(uuid, integer) to authenticated;
grant execute on function public.panel_reservations(uuid, timestamptz, timestamptz) to authenticated;
grant execute on function public.reservation_details(uuid) to authenticated;
