-- Time Machine bez czekania (10.2026). Zamiast pytać bazę o każdą chwilę (`panel_time_machine`), panel pobiera raz
-- wszystko z przedziału (zwykle doby): rachunki z chwilami pozycji i płatności, rezerwacje, zamówienia na wynos
-- z chwilami etapów i zmiany pracowników. Stan w dowolnej chwili liczy już panel, więc przewijanie osi czasu
-- jest natychmiastowe. `panel_time_machine` zostaje dla starszych wersji panelu.

create or replace function public.panel_time_machine_day(p_restaurant_id uuid, p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_permission(p_restaurant_id, 'activity');
  if p_to - p_from > interval '3 days' then
    raise exception 'Najwyżej 3 dni naraz.';
  end if;
  return jsonb_build_object(
    'from', p_from,
    'to', p_to,
    -- Rachunki przy stolikach otwarte choć przez chwilę w przedziale.
    'bills', coalesce((
      select jsonb_agg(jsonb_build_object(
        'order_id', o.id,
        'table_id', o.table_id,
        'label', private.order_label(o),
        'opened_at', o.opened_at,
        'closed_at', o.closed_at,
        'opened_by', m.name,
        'guests', o.guests,
        'payments', coalesce((
          select jsonb_agg(jsonb_build_object('at', p.created_at, 'amount', p.amount_grosze) order by p.created_at)
          from public.order_payments p where p.order_id = o.id
        ), '[]'::jsonb),
        'items', coalesce((
          select jsonb_agg(jsonb_build_object(
            'name', i.name, 'variant', i.variant, 'quantity', i.quantity, 'price', i.unit_price_grosze,
            'created_at', i.created_at, 'sent_at', i.sent_at, 'ready_at', i.ready_at, 'served_at', i.served_at,
            'cancelled_at', i.cancelled_at,
            -- Anulowane przed 0072 nie mają chwili anulowania: liczą się jako anulowane od początku.
            'cancelled', i.status = 'cancelled' and i.cancelled_at is null
          ) order by i.created_at)
          from public.order_items i where i.order_id = o.id
        ), '[]'::jsonb)
      ) order by o.opened_at)
      from public.orders o
      left join public.staff_members m on m.id = o.opened_by_member
      where o.restaurant_id = p_restaurant_id and o.kind = 'dine_in'
        and o.opened_at < p_to and (o.closed_at is null or o.closed_at > p_from)
    ), '[]'::jsonb),
    'reservations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', coalesce(r.guest_name, 'Gość'), 'party', r.party_size, 'starts_at', r.starts_at, 'ends_at', r.ends_at,
        'created_at', r.created_at, 'seated_at', r.seated_at,
        'table_ids', coalesce((select jsonb_agg(h.table_id) from public.table_holds h where h.reservation_id = r.id),
                              '[]'::jsonb)
      ) order by r.starts_at)
      from public.reservations r
      where r.restaurant_id = p_restaurant_id and r.source <> 'block'
        and r.starts_at < p_to and r.ends_at > p_from
        and r.status not in ('cancelled', 'no_show')
    ), '[]'::jsonb),
    'takeaway', coalesce((
      select jsonb_agg(jsonb_build_object(
        'order_id', o.id, 'label', private.order_label(o), 'customer', o.customer_name, 'kind', o.kind,
        'fulfillment', o.fulfillment,
        'opened_at', o.opened_at, 'accepted_at', o.accepted_at, 'ready_at', o.ready_at,
        'picked_up_at', o.picked_up_at, 'delivered_at', o.delivered_at, 'closed_at', o.closed_at,
        'total', (select coalesce(sum(i.unit_price_grosze * i.quantity), 0) from public.order_items i
                  where i.order_id = o.id and i.status <> 'cancelled') + o.delivery_fee_grosze
      ) order by o.opened_at)
      from public.orders o
      where o.restaurant_id = p_restaurant_id and o.kind <> 'dine_in' and o.fulfillment <> 'draft'
        and o.opened_at < p_to
        and (coalesce(o.delivered_at, o.closed_at) is null or coalesce(o.delivered_at, o.closed_at) > p_from)
        and (o.fulfillment not in ('rejected', 'cancelled', 'awaiting_payment') or o.closed_at > p_from)
    ), '[]'::jsonb),
    'staff', coalesce((
      select jsonb_agg(jsonb_build_object('name', m.name, 'started_at', s.started_at, 'ended_at', s.ended_at)
                       order by s.started_at)
      from public.staff_shifts s join public.staff_members m on m.id = s.member_id
      where s.restaurant_id = p_restaurant_id and s.started_at < p_to and (s.ended_at is null or s.ended_at > p_from)
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.panel_time_machine_day(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.panel_time_machine_day(uuid, timestamptz, timestamptz) to authenticated;
