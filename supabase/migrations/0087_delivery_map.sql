-- Mapa dostawców wraca (14.11.2026, prośba użytkownika: „przywrócimy stary projekt Mapa, tylko z mapą Mapbox”).
-- Najpierw w panelu na komputerze: mapa Mapbox, cele dostaw, kursy z najszybszą trasą i czasem dojazdu oraz
-- propozycje łączenia dostaw w kursy. Adresy, trasy i czasy liczy panel w Mapbox (klucz w env.json), więc baza
-- daje tylko dane: lokal z położeniem, dostawców na zmianie (kolejka, kolor, auto na dziś, ostatnia pozycja
-- z telefonu, gdy jest) i dostawy w toku. Pozycje z telefonów (Dostawy w Table for employees, CarPlay
-- i Android Auto) dojdą w drugim etapie: `staff_locations` i `staff_share_location` zostają jak w 0068.

create or replace function public.panel_delivery_map(p_restaurant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_r   restaurants%rowtype;
  v_day date;
begin
  perform private.require_permission(p_restaurant_id, 'orders');
  select * into v_r from restaurants where id = p_restaurant_id;
  v_day := (now() at time zone coalesce(v_r.timezone, 'Europe/Warsaw'))::date;

  return jsonb_build_object(
    'restaurant', jsonb_build_object(
      'name', v_r.name,
      'address', concat_ws(', ', v_r.address, v_r.city),
      'city', v_r.city,
      'lat', case when v_r.location is null then null else st_y(v_r.location::geometry) end,
      'lng', case when v_r.location is null then null else st_x(v_r.location::geometry) end
    ),
    'couriers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'member_id', q.member_id,
        'name', q.name,
        'busy', q.busy,
        'ready', q.located,
        'since', q.waiting_since,
        'color', m.color,
        'vehicle', v.kind,
        'vehicle_name', v.name,
        'lat', l.lat,
        'lng', l.lng,
        'accuracy', l.accuracy,
        'heading', l.heading,
        'speed', l.speed,
        'updated_at', l.updated_at
      ))
      from private.courier_queue(p_restaurant_id) q
      join staff_members m on m.id = q.member_id
      left join vehicle_days vd on vd.member_id = q.member_id and vd.day = v_day
      left join vehicles v on v.id = vd.vehicle_id
      left join staff_locations l on l.member_id = q.member_id and l.updated_at > now() - interval '15 minutes'
    ), '[]'::jsonb),
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id,
        'number', o.number,
        'fulfillment', o.fulfillment,
        'courier_member', o.courier_member,
        'course_id', o.course_id,
        'address', o.delivery_address,
        'address_note', o.address_note,
        'customer_name', o.customer_name,
        'promised_at', o.promised_at,
        'scheduled_for', o.scheduled_for,
        'kitchen_at', o.kitchen_at,
        'picked_up_at', o.picked_up_at,
        'accepted_at', o.accepted_at,
        'ready_at', o.ready_at
      ) order by o.promised_at nulls last, o.number)
      from orders o
      where o.restaurant_id = p_restaurant_id
        and o.kind = 'delivery'
        and o.fulfillment in ('accepted', 'ready', 'on_the_way')
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.panel_delivery_map(uuid) from public, anon;
grant execute on function public.panel_delivery_map(uuid) to authenticated;
