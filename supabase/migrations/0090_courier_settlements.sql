-- Management → Rozliczenia dostawców (20.11.2026, prośba użytkownika): wszystkie kursy dostawców z numerem
-- zamówienia, adresem, dostawcą, autem i formą płatności. Zamówienia jednego kursu mają ten sam `course_id`.
-- Opłacone zamówienie to karta online albo przyjęte w panelu z góry (`payment_choice` card_online, prepaid);
-- gotówka i karta przy odbiorze to dla systemu zamówienie nieopłacone, bo dostawca pobiera pieniądze od gościa
-- (po dowiezieniu `payment_status` jest „paid”, ale to nadal pieniądze do rozliczenia z dostawcą).

-- Zamówienia z dostawą, które wyjechały albo są gotowe do wyjazdu (od dnia [p_from] do [p_to] włącznie, dzień lokalu
-- z godziną zamknięcia dnia): jeden wiersz na zamówienie z dostawcą i autem dostawcy z tego dnia (Flota).
create or replace function public.panel_courier_settlements(p_restaurant_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform private.require_permission(p_restaurant_id, 'day_close');
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'Wybierz poprawny okres.';
  end if;
  if p_to - p_from > 366 then
    raise exception 'Okres może mieć najwyżej rok.';
  end if;
  return coalesce((
    select jsonb_agg(r.payload order by r.at desc, r.number desc)
    from (
      select
        coalesce(o.delivered_at, o.picked_up_at, o.opened_at) as at,
        o.number,
        jsonb_build_object(
          'id', o.id,
          'number', o.number,
          'course_id', o.course_id,
          'fulfillment', o.fulfillment,
          'at', coalesce(o.delivered_at, o.picked_up_at, o.opened_at),
          'delivery_address', o.delivery_address,
          'customer_name', coalesce(o.customer_company, o.customer_name),
          'payment_choice', o.payment_choice,
          'payment_status', o.payment_status,
          'payment_method', o.payment_method,
          'total_grosze', o.delivery_fee_grosze + coalesce((
            select sum(i.unit_price_grosze * i.quantity) from order_items i
            where i.order_id = o.id and i.status <> 'cancelled'
          ), 0),
          'courier_member', o.courier_member,
          'courier_name', m.name,
          'vehicle_id', v.id,
          'vehicle_name', v.name,
          'vehicle_plate', v.plate
        ) as payload
      from orders o
      left join staff_members m on m.id = o.courier_member
      left join lateral (
        select vv.id, vv.name, vv.plate
        from vehicle_days d
        join vehicles vv on vv.id = d.vehicle_id
        where d.member_id = o.courier_member
          and d.day = private.business_day(o.restaurant_id, coalesce(o.picked_up_at, o.accepted_at, o.opened_at))
        limit 1
      ) v on true
      where o.restaurant_id = p_restaurant_id
        and o.kind = 'delivery'
        and o.status <> 'cancelled'
        and o.fulfillment in ('ready', 'on_the_way', 'delivered')
        and private.business_day(o.restaurant_id, coalesce(o.delivered_at, o.picked_up_at, o.opened_at))
            between p_from and p_to
      order by 1 desc, 2 desc
      limit 3000
    ) r
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.panel_courier_settlements(uuid, date, date) from public, anon;
grant execute on function public.panel_courier_settlements(uuid, date, date) to authenticated;
