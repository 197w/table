-- Table · migracja 0038
-- Karty podarunkowe usunięte z panelu i z aplikacji Table. Dane kart i rachunki opłacone kartą zostają w bazie
-- (historia zamówień i sprzedaż pokazują stare płatności), ale nowej karty nie da się kupić,
-- a uprawnienie gift_cards znika ze stanowisk.

create or replace function public.purchase_gift_card(
  p_restaurant_id   uuid,
  p_amount_grosze   integer,
  p_recipient_name  text default null,
  p_message         text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'Karty podarunkowe nie są już dostępne.';
end;
$$;

update public.staff_positions
set permissions = array_remove(permissions, 'gift_cards')
where 'gift_cards' = any (permissions);

create or replace function private.all_permissions()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['reservations', 'floor', 'floor_edit', 'orders', 'orders_close', 'orders_cancel', 'deliveries',
               'kitchen', 'kitchen_settings', 'staff', 'staff_logins', 'schedule', 'timesheet', 'positions',
               'profile', 'menu', 'menu_edit', 'menu_availability', 'inventory_edit', 'inventory_count',
               'reviews', 'stats']
$$;

update public.staff_positions set permissions = private.all_permissions() where system_key = 'all';
