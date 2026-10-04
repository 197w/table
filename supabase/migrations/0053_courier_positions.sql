-- Dostawca na mapie: aplikacja Table for employees wysyła pozycję, gdy kurs jest w drodze,
-- a gość widzi ją w szczegółach zamówienia. Pozycja znika po zakończeniu kursu.

create table public.courier_positions (
  order_id       uuid primary key references public.orders (id) on delete cascade,
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  member_id      uuid references public.staff_members (id) on delete set null,
  lat            double precision not null check (lat between -90 and 90),
  lng            double precision not null check (lng between -180 and 180),
  accuracy       real,
  updated_at     timestamptz not null default now()
);
-- Bez polityk odczytu: pozycję czyta tylko gość zamówienia przez guest_courier_position.
alter table public.courier_positions enable row level security;

create or replace function public.staff_courier_position(
  p_order_id   uuid,
  p_member_id  uuid,
  p_lat        double precision,
  p_lng        double precision,
  p_accuracy   real default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member staff_members%rowtype;
  v_order  orders%rowtype;
begin
  v_member := private.my_member(p_member_id);
  select * into v_order from orders where id = p_order_id;
  if not found or v_order.courier_member is distinct from p_member_id or v_order.fulfillment <> 'on_the_way' then
    return;
  end if;
  insert into courier_positions (order_id, restaurant_id, member_id, lat, lng, accuracy, updated_at)
  values (p_order_id, v_order.restaurant_id, p_member_id, p_lat, p_lng, p_accuracy, now())
  on conflict (order_id) do update
    set lat = excluded.lat, lng = excluded.lng, accuracy = excluded.accuracy,
        member_id = excluded.member_id, updated_at = now();
end;
$$;

-- Pozycja dostawcy dla gościa zamówienia (tylko w drodze) i położenie lokalu.
create or replace function public.guest_courier_position(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_order orders%rowtype;
begin
  select * into v_order from orders where id = p_order_id and guest_id = auth.uid();
  if not found or v_order.fulfillment <> 'on_the_way' then
    return null;
  end if;
  return (
    select jsonb_build_object(
      'lat', c.lat,
      'lng', c.lng,
      'updated_at', c.updated_at,
      'restaurant_lat', st_y(r.location::geometry),
      'restaurant_lng', st_x(r.location::geometry)
    )
    from restaurants r
    left join courier_positions c on c.order_id = p_order_id
    where r.id = v_order.restaurant_id
  );
end;
$$;

create or replace function private.courier_position_cleanup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.fulfillment is distinct from 'on_the_way' then
    delete from public.courier_positions where order_id = new.id;
  end if;
  return new;
end;
$$;
create trigger orders_courier_position_cleanup
  after update of fulfillment on public.orders
  for each row when (old.fulfillment = 'on_the_way')
  execute function private.courier_position_cleanup();

revoke execute on function public.staff_courier_position(uuid, uuid, double precision, double precision, real) from public, anon;
revoke execute on function public.guest_courier_position(uuid) from public, anon;
revoke execute on function private.courier_position_cleanup() from public, anon;
grant execute on function public.staff_courier_position(uuid, uuid, double precision, double precision, real) to authenticated;
grant execute on function public.guest_courier_position(uuid) to authenticated;
