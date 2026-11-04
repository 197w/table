-- Statystyki sprzedaży z filtrami z panelu po lewej (4.11.2026, prośba użytkownika: panel filtrów jak w Pracownikach).
-- p_kinds: rodzaje zamówień (dine_in, delivery, pickup), p_members: kto otworzył rachunek (id pracownika, '' = bez
-- przypisania); null = wszystko. 'facets' to liczby rachunków w okresie bez filtrów, do pól wyboru w panelu.
-- Stara wersja (uuid, integer) znika, bo z domyślnymi parametrami starsze panele wołają tę samą funkcję.

drop function if exists public.panel_sales_stats(uuid, integer);

create function public.panel_sales_stats(
  p_restaurant_id uuid,
  p_days integer,
  p_kinds text[] default null,
  p_members text[] default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz     text;
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
  v_start := (date_trunc('day', now() at time zone v_tz) - make_interval(days => v_days - 1)) at time zone v_tz;
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
      from generate_series((v_start at time zone v_tz)::date, (now() at time zone v_tz)::date, interval '1 day') d
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
          'revenue', coalesce((select sum(c.total) from cur c where (c.closed_at at time zone v_tz)::date = d.day), 0),
          'orders', (select count(*) from cur c where (c.closed_at at time zone v_tz)::date = d.day)
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
          select extract(isodow from c.closed_at at time zone v_tz)::integer as weekday,
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

revoke execute on function public.panel_sales_stats(uuid, integer, text[], text[]) from public, anon;
grant execute on function public.panel_sales_stats(uuid, integer, text[], text[]) to authenticated;
