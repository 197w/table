-- Zamknięcie dnia, zamówienia netto, średni rachunek, gotówka do koperty i kaucja (8.11.2026, prośby użytkownika).
--
-- 1. Zamknięcie dnia (`restaurants.day_close`, 00:00–08:00): lokal otwarty do 2 w nocy ustawia 02:00 i wtedy
--    sprzedaż do 2:00 liczy się do poprzedniego dnia: podsumowanie dnia (`private.day_range`), miesiące
--    (`private.month_range`: eksport, godziny i statystyki pracowników), statystyki sprzedaży i rezerwacji dzień
--    po dniu, dzisiejszy średni czas kuchni. `private.business_day` mówi, do którego dnia należy chwila.
-- 2. Podsumowanie dnia: zamówienia netto (bez anulowanych, bez pustych, „Część rachunku” razem z resztą rachunku
--    jako jedno), sprzedaż netto bez VAT z panelu (szacunek, gdy lokal nie wpisze netto z raportu dobowego),
--    netto z raportu dobowego kasy fiskalnej (`day_reports.fiscal_net_grosze`) do średniego rachunku.
-- 3. Kaucja przy składniku (`inventory_items.deposit_grosze`, np. 50 gr za butelkę albo puszkę): w podsumowaniu
--    dnia kaucja ze sprzedanych dań (ruchy sprzedaży z receptur, sztuka = jedna kaucja, inne jednostki: opakowanie).

alter table public.restaurants
  add column day_close time not null default '00:00' check (day_close <= time '08:00');
grant update (day_close) on public.restaurants to authenticated;

alter table public.day_reports
  add column fiscal_net_grosze integer check (fiscal_net_grosze is null or fiscal_net_grosze >= 0);

alter table public.inventory_items
  add column deposit_grosze integer check (deposit_grosze is null or deposit_grosze between 1 and 10000);
grant select (deposit_grosze), insert (deposit_grosze), update (deposit_grosze) on public.inventory_items to authenticated;

-- ---------------------------------------------------------------
-- Dzień lokalu
-- ---------------------------------------------------------------

-- Przesunięcie początku dnia lokalu (00:00 = północ).
create or replace function private.day_close(p_restaurant_id uuid)
returns interval
language sql
stable
set search_path = ''
as $$
  select coalesce((select r.day_close - time '00:00' from public.restaurants r where r.id = p_restaurant_id), interval '0')
$$;

-- Dzień lokalu dla chwili: przy zamknięciu 02:00 sprzedaż o 01:30 należy do poprzedniego dnia.
create or replace function private.business_day(p_restaurant_id uuid, p_at timestamptz)
returns date
language sql
stable
set search_path = ''
as $$
  select ((p_at at time zone coalesce(r.timezone, 'Europe/Warsaw')) - (r.day_close - time '00:00'))::date
  from public.restaurants r
  where r.id = p_restaurant_id
$$;

create or replace function private.day_range(p_restaurant_id uuid, p_day date, out starts timestamptz, out ends timestamptz)
language sql
stable
set search_path = ''
as $$
  select
    ((p_day + (r.day_close - time '00:00')) at time zone coalesce(r.timezone, 'Europe/Warsaw')),
    ((p_day + 1 + (r.day_close - time '00:00')) at time zone coalesce(r.timezone, 'Europe/Warsaw'))
  from public.restaurants r
  where r.id = p_restaurant_id
$$;

create or replace function private.month_range(p_restaurant_id uuid, p_month date, out starts timestamptz, out ends timestamptz)
language sql
stable
set search_path = ''
as $$
  select
    ((date_trunc('month', p_month::timestamp) + (r.day_close - time '00:00'))
       at time zone coalesce(r.timezone, 'Europe/Warsaw')),
    ((date_trunc('month', p_month::timestamp) + interval '1 month' + (r.day_close - time '00:00'))
       at time zone coalesce(r.timezone, 'Europe/Warsaw'))
  from public.restaurants r
  where r.id = p_restaurant_id
$$;

revoke execute on function private.day_close(uuid) from public, anon;
revoke execute on function private.business_day(uuid, timestamptz) from public, anon;
grant execute on function private.day_close(uuid) to authenticated;
grant execute on function private.business_day(uuid, timestamptz) to authenticated;

-- Lokale konta z godziną zamknięcia dnia (panel liczy „dziś” i Historię zamówień od niej).
drop function if exists public.panel_my_restaurants();
create function public.panel_my_restaurants()
returns table(id uuid, name text, city text, plan restaurant_plan, role staff_role, timezone text, logo_url text,
              listed boolean, day_close text)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.name, r.city, r.plan, s.role, r.timezone, r.logo_url, r.listed, to_char(r.day_close, 'HH24:MI')
  from restaurant_staff s
  join restaurants r on r.id = s.restaurant_id
  where s.user_id = auth.uid()
  order by r.name
$$;
revoke execute on function public.panel_my_restaurants() from public, anon;
grant execute on function public.panel_my_restaurants() to authenticated;

-- ---------------------------------------------------------------
-- Statystyki dzień po dniu według dnia lokalu
-- ---------------------------------------------------------------

create or replace function public.panel_sales_stats(p_restaurant_id uuid, p_days integer, p_kinds text[] default null,
  p_members text[] default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz     text;
  v_close  interval;
  v_days   integer := greatest(1, least(coalesce(p_days, 30), 366));
  v_start  timestamptz;
  v_prev   timestamptz;
begin
  if not (
    private.has_permission(p_restaurant_id, 'stats')
    or private.has_permission(p_restaurant_id, 'orders')
  ) then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;

  select timezone into v_tz from restaurants where id = p_restaurant_id;
  v_tz := coalesce(v_tz, 'Europe/Warsaw');
  v_close := private.day_close(p_restaurant_id);
  v_start := (((now() at time zone v_tz) - v_close)::date - (v_days - 1) + v_close) at time zone v_tz;
  v_prev := v_start - make_interval(days => v_days);

  return (
    with chosen as (
      select o.*
      from orders o
      where o.restaurant_id = p_restaurant_id
        and (p_kinds is null or o.kind = any(p_kinds))
        and (p_members is null or coalesce(o.opened_by_member::text, '') = any(p_members))
    ),
    paid as (
      select o.*,
             (select coalesce(sum(i.unit_price_grosze * i.quantity), 0)
              from order_items i where i.order_id = o.id and i.status <> 'cancelled') as total
      from chosen o
      where o.status = 'paid' and o.closed_at >= v_prev
    ),
    cur as (select * from paid where closed_at >= v_start),
    prev as (select * from paid where closed_at < v_start),
    items as (
      select i.* from order_items i
      join cur o on o.id = i.order_id
      where i.status <> 'cancelled'
    ),
    days as (
      select d::date as day
      from generate_series(((v_start at time zone v_tz) - v_close)::date, ((now() at time zone v_tz) - v_close)::date,
                           interval '1 day') d
    ),
    -- Wszystkie rachunki okresu bez filtrów: liczby przy polach wyboru.
    everything as (
      select o.kind, o.opened_by_member
      from orders o
      where o.restaurant_id = p_restaurant_id and o.status = 'paid' and o.closed_at >= v_start
    )
    select jsonb_build_object(
      'revenue', coalesce((select sum(total) from cur), 0),
      'orders', (select count(*) from cur),
      'items', coalesce((select sum(quantity) from items), 0),
      'gift_cards', coalesce((select sum(gift_card_grosze) from cur), 0),
      'cancelled', (select count(*) from chosen o where o.status = 'cancelled' and o.closed_at >= v_start),
      'avg_table_minutes', (select round(avg(extract(epoch from closed_at - opened_at)) / 60) from cur),
      'prev_revenue', coalesce((select sum(total) from prev), 0),
      'prev_orders', (select count(*) from prev),
      'daily', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'day', d.day,
          'revenue', coalesce((select sum(c.total) from cur c where ((c.closed_at at time zone v_tz) - v_close)::date = d.day), 0),
          'orders', (select count(*) from cur c where ((c.closed_at at time zone v_tz) - v_close)::date = d.day)
        ) order by d.day), '[]'::jsonb)
        from days d
      ),
      -- Godzina złożenia (otwarcia) zamówienia: kwota, liczba i podział na salę, dostawę i odbiór.
      'hourly', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'hour', h,
          'revenue', coalesce(x.revenue, 0),
          'orders', coalesce(x.orders, 0),
          'dine_in', coalesce(x.dine_in, 0),
          'delivery', coalesce(x.delivery, 0),
          'pickup', coalesce(x.pickup, 0)
        ) order by h), '[]'::jsonb)
        from generate_series(0, 23) h
        left join (
          select extract(hour from c.opened_at at time zone v_tz)::integer as hour,
                 sum(c.total) as revenue, count(*) as orders,
                 count(*) filter (where c.kind = 'delivery') as delivery,
                 count(*) filter (where c.kind = 'pickup') as pickup,
                 count(*) filter (where c.kind is distinct from 'delivery' and c.kind is distinct from 'pickup') as dine_in
          from cur c group by 1
        ) x on x.hour = h
      ),
      'weekdays', (
        select coalesce(jsonb_agg(jsonb_build_object('weekday', w, 'revenue', coalesce(x.revenue, 0), 'orders', coalesce(x.orders, 0)) order by w), '[]'::jsonb)
        from generate_series(1, 7) w
        left join (
          select extract(isodow from (c.closed_at at time zone v_tz) - v_close)::integer as weekday,
                 sum(c.total) as revenue, count(*) as orders
          from cur c group by 1
        ) x on x.weekday = w
      ),
      'top_items', (
        select coalesce(jsonb_agg(t order by t.quantity desc, t.revenue desc), '[]'::jsonb)
        from (
          select name, sum(quantity)::integer as quantity, sum(unit_price_grosze * quantity)::integer as revenue
          from items group by name order by sum(quantity) desc, sum(unit_price_grosze * quantity) desc limit 10
        ) t
      ),
      'payments', (
        select coalesce(jsonb_agg(p), '[]'::jsonb)
        from (
          select method, sum(amount)::integer as amount, count(*)::integer as orders from (
            select payment_method as method, total - coalesce(gift_card_grosze, 0) as amount
            from cur where payment_method <> 'gift_card'
            union all
            select 'gift_card', coalesce(gift_card_grosze, total) from cur
            where gift_card_grosze is not null or payment_method = 'gift_card'
          ) a
          group by method order by sum(amount) desc
        ) p
      ),
      'vat', (
        select coalesce(jsonb_agg(v order by v.rate desc), '[]'::jsonb)
        from (
          select vat_rate as rate, sum(unit_price_grosze * quantity)::integer as gross
          from items group by vat_rate
        ) v
      ),
      'staff', (
        select coalesce(jsonb_agg(s order by s.revenue desc), '[]'::jsonb)
        from (
          select coalesce(m.name, 'Bez przypisania') as name, sum(c.total)::integer as revenue,
                 count(*)::integer as orders
          from cur c
          left join staff_members m on m.id = c.opened_by_member
          group by m.name
        ) s
      ),
      'kitchen_seconds', (
        select round(avg(extract(epoch from done - sent)))
        from (
          select i.sent_at as sent, max(i.ready_at) as done
          from order_items i
          join chosen o on o.id = i.order_id
          where i.restaurant_id = p_restaurant_id and i.sent_at >= v_start and i.ready_at is not null
          group by i.order_id, i.sent_at
        ) k
      ),
      'facets', jsonb_build_object(
        'kinds', (
          select coalesce(jsonb_agg(jsonb_build_object('kind', k.kind, 'orders', k.orders) order by k.kind), '[]'::jsonb)
          from (select kind, count(*)::integer as orders from everything group by kind) k
        ),
        'members', (
          select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'orders', x.orders)
                                    order by x.name), '[]'::jsonb)
          from (
            select coalesce(e.opened_by_member::text, '') as id, coalesce(m.name, 'Bez przypisania') as name,
                   count(*)::integer as orders
            from everything e
            left join staff_members m on m.id = e.opened_by_member
            group by 1, 2
          ) x
        )
      )
    )
  );
end;
$$;

create or replace function public.panel_stats(p_restaurant_id uuid, p_days integer default 30)
returns table(day date, views integer, call_clicks integer, reservations integer, covers integer, cancellations integer,
              no_shows integer, likes integer, likes_total integer)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz    text;
  v_close interval;
  v_days  integer := least(greatest(coalesce(p_days, 30), 1), 366);
begin
  perform private.require_staff(p_restaurant_id);

  select coalesce(timezone, 'Europe/Warsaw') into v_tz from restaurants where id = p_restaurant_id;
  v_close := private.day_close(p_restaurant_id);

  return query
  with days as (
    select generate_series(
      ((now() at time zone v_tz) - v_close)::date - (v_days - 1),
      ((now() at time zone v_tz) - v_close)::date,
      interval '1 day'
    )::date as day
  ),
  ev as (
    select ((e.created_at at time zone v_tz) - v_close)::date as day,
           count(*) filter (where e.kind = 'view') as views,
           count(*) filter (where e.kind = 'call_click') as calls
    from restaurant_events e
    where e.restaurant_id = p_restaurant_id
      and e.created_at >= now() - make_interval(days => v_days + 1)
    group by 1
  ),
  rs as (
    select ((r.starts_at at time zone v_tz) - v_close)::date as day,
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
    select ((l.created_at at time zone v_tz) - v_close)::date as day, count(*) as likes
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

create or replace function public.panel_kitchen_stats(p_restaurant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with allowed as (
    select private.has_permission(p_restaurant_id, 'kitchen')
        or private.has_permission(p_restaurant_id, 'orders') as ok
  ),
  day_start as (
    -- Początek dzisiejszego dnia lokalu (z godziną zamknięcia dnia).
    select r.starts as t from private.day_range(p_restaurant_id, private.business_day(p_restaurant_id, now())) r
  ),
  tickets as (
    select i.order_id, i.sent_at, max(i.ready_at) as done_at
    from order_items i, day_start d
    where i.restaurant_id = p_restaurant_id
      and i.sent_at >= d.t
      and i.ready_at is not null
      -- Bilecik liczy się dopiero, gdy kuchnia zbiła z niego wszystko.
      and not exists (
        select 1 from order_items y
        where y.order_id = i.order_id and y.sent_at = i.sent_at and y.status = 'sent'
      )
    group by i.order_id, i.sent_at
  )
  select case when (select ok from allowed) then jsonb_build_object(
    'today_seconds', (select round(avg(extract(epoch from done_at - sent_at))) from tickets),
    'today_count', (select count(*) from tickets),
    'hour_seconds', (select round(avg(extract(epoch from done_at - sent_at))) from tickets
                     where done_at >= now() - interval '1 hour'),
    'hour_count', (select count(*) from tickets where done_at >= now() - interval '1 hour')
  ) else null end
$$;

-- ---------------------------------------------------------------
-- Podsumowanie dnia
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
      select o.id, o.kind, o.payment_method, o.payment_choice, o.discount_grosze, o.tip_grosze, o.deposit_grosze,
             o.table_id, o.opened_at, coalesce(o.delivery_fee_grosze, 0) as fee, g.gross, g.net,
             g.gross + coalesce(o.delivery_fee_grosze, 0) - o.discount_grosze as total
      from orders o
      cross join lateral (
        select coalesce(sum(i.unit_price_grosze * i.quantity), 0) as gross,
               coalesce(sum(i.unit_price_grosze * i.quantity * 100.0 / (100 + i.vat_rate)), 0) as net
        from order_items i where i.order_id = o.id and i.status <> 'cancelled'
      ) g
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
    -- Kaucja ze sprzedanych dań: ruchy sprzedaży składników z kaucją (sztuka = jedna kaucja, inne jednostki: opakowanie).
    kaucja as (
      select ii.deposit_grosze,
             round(case when ii.unit = 'szt' then -sum(m.amount) else -sum(m.amount) / nullif(ii.capacity, 0) end) as units
      from inventory_movements m
      join order_items oi on oi.id = m.order_item_id
      join paid o on o.id = oi.order_id
      join inventory_items ii on ii.id = m.item_id
      where m.kind = 'sale' and coalesce(ii.deposit_grosze, 0) > 0
      group by ii.id, ii.deposit_grosze, ii.unit, ii.capacity
    ),
    petty as (
      select * from petty_cash where restaurant_id = p_restaurant_id and day = p_day
    )
    select jsonb_build_object(
      'day', p_day,
      'day_close', to_char((select r.day_close from restaurants r where r.id = p_restaurant_id), 'HH24:MI'),
      'revenue', coalesce((select sum(total) from paid), 0),
      -- Netto bez VAT z panelu: pozycje ze stawką z menu, dostawa jak 8%, rabat rozłożony proporcjonalnie.
      'revenue_net', coalesce((
        select round(sum(case when gross + fee > 0 then (net + fee * 100.0 / 108) * total / (gross + fee) else 0 end))
        from paid
      ), 0),
      'orders', (select count(*) from paid),
      -- Zamówienia netto: bez anulowanych i pustych; „Część rachunku” to ten sam stolik i chwila otwarcia, więc jedno.
      'orders_net', (
        select count(distinct o.kind || ':' || coalesce(o.table_id::text, o.id::text) || ':' || o.opened_at::text)
        from paid o where o.total > 0
      ),
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
      'kaucja_grosze', coalesce((select sum(units * deposit_grosze) from kaucja), 0),
      'kaucja_count', coalesce((select sum(units) from kaucja), 0),
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
          'fiscal_grosze', r.fiscal_grosze, 'fiscal_net_grosze', r.fiscal_net_grosze, 'terminals', r.terminals,
          'cash_counted_grosze', r.cash_counted_grosze, 'note', r.note, 'platforms', r.platforms,
          'updated_at', r.updated_at, 'updated_by_name', r.updated_by_name
        )
        from day_reports r where r.restaurant_id = p_restaurant_id and r.day = p_day
      )
    )
  );
end;
$$;

-- Zapis raportu dnia z netto z raportu dobowego. Stara wersja bez [p_fiscal_net] usunięta (z domyślnym parametrem
-- wywołanie bez niego byłoby niejednoznaczne).
drop function if exists public.panel_save_day_report(uuid, date, integer, jsonb, integer, text, uuid, jsonb);
create function public.panel_save_day_report(
  p_restaurant_id uuid,
  p_day date,
  p_fiscal integer,
  p_terminals jsonb,
  p_cash_counted integer,
  p_note text,
  p_member_id uuid default null,
  p_platforms jsonb default null,
  p_fiscal_net integer default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_terminals jsonb;
  v_platforms jsonb;
begin
  perform private.require_permission(p_restaurant_id, 'day_close');
  perform private.check_inventory_member(p_restaurant_id, p_member_id);
  if p_day > (now() at time zone 'Europe/Warsaw')::date + 1 then
    raise exception 'Nie można wpisać raportu na przyszły dzień.';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'name', left(coalesce(nullif(trim(t->>'name'), ''), 'Terminal'), 60),
           'grosze', greatest(0, least((t->>'grosze')::integer, 100000000))
         )), '[]'::jsonb)
  into v_terminals
  from jsonb_array_elements(coalesce(p_terminals, '[]'::jsonb)) t
  where (t->>'grosze') is not null;

  if p_platforms is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
             'name', left(coalesce(nullif(trim(t->>'name'), ''), 'Platforma'), 40),
             'grosze', greatest(0, least((t->>'grosze')::integer, 100000000))
           )), '[]'::jsonb)
    into v_platforms
    from jsonb_array_elements(p_platforms) t
    where (t->>'grosze') is not null;
  end if;

  insert into day_reports (restaurant_id, day, fiscal_grosze, fiscal_net_grosze, terminals, cash_counted_grosze, note,
                           platforms, updated_at, updated_by_member, updated_by_name)
  values (p_restaurant_id, p_day, p_fiscal, p_fiscal_net, v_terminals, p_cash_counted, nullif(trim(p_note), ''),
          coalesce(v_platforms, '[]'::jsonb), now(), p_member_id, private.note_author(p_restaurant_id, p_member_id))
  on conflict (restaurant_id, day) do update
    set fiscal_grosze = excluded.fiscal_grosze, fiscal_net_grosze = excluded.fiscal_net_grosze,
        terminals = excluded.terminals,
        cash_counted_grosze = excluded.cash_counted_grosze, note = excluded.note,
        platforms = coalesce(v_platforms, day_reports.platforms),
        updated_at = now(), updated_by_member = excluded.updated_by_member, updated_by_name = excluded.updated_by_name;
end;
$$;

revoke execute on function public.panel_save_day_report(uuid, date, integer, jsonb, integer, text, uuid, jsonb, integer)
  from public, anon;
grant execute on function public.panel_save_day_report(uuid, date, integer, jsonb, integer, text, uuid, jsonb, integer)
  to authenticated;
