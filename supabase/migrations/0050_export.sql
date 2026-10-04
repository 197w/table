-- Eksport dla księgowej (Management → Eksport): rachunki miesiąca z podziałem na stawki VAT, płatności,
-- rabaty i napiwki, czas pracy z wynagrodzeniem oraz petty cash. Uprawnienie „Eksport”.

create or replace function public.panel_export_month(p_restaurant_id uuid, p_month date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_start timestamptz;
  v_end   timestamptz;
  v_tz    text;
begin
  perform private.require_permission(p_restaurant_id, 'export');
  select starts, ends into v_start, v_end from private.month_range(p_restaurant_id, p_month);
  select coalesce(timezone, 'Europe/Warsaw') into v_tz from restaurants where id = p_restaurant_id;

  return jsonb_build_object(
    'timezone', v_tz,
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id,
        'closed_at', o.closed_at,
        'opened_at', o.opened_at,
        'kind', o.kind,
        'number', o.number,
        'table', t.label,
        'payment_method', o.payment_method,
        'payment_choice', o.payment_choice,
        'delivery_fee', coalesce(o.delivery_fee_grosze, 0),
        'discount', o.discount_grosze,
        'tip', o.tip_grosze,
        'vat', coalesce((
          select jsonb_agg(jsonb_build_object('rate', v.vat_rate, 'gross', v.gross) order by v.vat_rate desc)
          from (
            select i.vat_rate, sum(i.unit_price_grosze * i.quantity) as gross
            from order_items i where i.order_id = o.id and i.status <> 'cancelled'
            group by i.vat_rate
          ) v
        ), '[]'::jsonb),
        'payments', coalesce((
          select jsonb_agg(jsonb_build_object('method', p.method, 'amount', p.amount_grosze, 'tip', p.tip_grosze))
          from order_payments p where p.order_id = o.id
        ), '[]'::jsonb)
      ) order by o.closed_at)
      from orders o
      left join dining_tables t on t.id = o.table_id
      where o.restaurant_id = p_restaurant_id and o.status = 'paid'
        and o.closed_at >= v_start and o.closed_at < v_end
    ), '[]'::jsonb),
    'hours', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', m.name,
        'position', sp.name,
        'contract', coalesce(r.contract, 'zlecenie'),
        'rate', r.hourly_rate_grosze,
        'shifts', x.shifts,
        'seconds', x.seconds
      ) order by m.name)
      from staff_members m
      left join staff_positions sp on sp.id = m.position_id
      left join staff_rates r on r.member_id = m.id
      join lateral (
        select count(*)::integer as shifts,
               coalesce(sum(extract(epoch from least(coalesce(s.ended_at, now()), v_end) - greatest(s.started_at, v_start))), 0)::bigint as seconds
        from staff_shifts s
        where s.member_id = m.id and s.started_at < v_end and coalesce(s.ended_at, now()) > v_start
      ) x on true
      where m.restaurant_id = p_restaurant_id and (m.active or x.shifts > 0)
    ), '[]'::jsonb),
    'petty', coalesce((
      select jsonb_agg(jsonb_build_object(
        'day', pc.day, 'kind', pc.kind, 'description', pc.description, 'amount', pc.amount_grosze,
        'author', pc.author_name, 'created_at', pc.created_at
      ) order by pc.day, pc.created_at)
      from petty_cash pc
      where pc.restaurant_id = p_restaurant_id
        and pc.day >= date_trunc('month', p_month)::date
        and pc.day < (date_trunc('month', p_month) + interval '1 month')::date
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.panel_export_month(uuid, date) from public, anon;
grant execute on function public.panel_export_month(uuid, date) to authenticated;
