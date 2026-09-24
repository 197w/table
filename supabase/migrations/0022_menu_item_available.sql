-- Table · migracja 0022
-- „Skończyło się”: kelner albo kuchnia oznacza danie jako chwilowo niedostępne,
-- bez prawa do zmiany reszty menu. Goście widzą to od razu w aplikacji.

create or replace function public.panel_set_menu_item_available(p_item_id uuid, p_available boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
begin
  select s.restaurant_id into v_restaurant
  from menu_items i
  join menu_sections s on s.id = i.section_id
  where i.id = p_item_id;
  if v_restaurant is null then
    raise exception 'Nie znaleziono pozycji w menu.';
  end if;

  if not (
    private.has_permission(v_restaurant, 'orders')
    or private.has_permission(v_restaurant, 'kitchen')
    or private.has_permission(v_restaurant, 'menu')
  ) then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;

  update menu_items set available = coalesce(p_available, true) where id = p_item_id;
end;
$$;

revoke execute on function public.panel_set_menu_item_available(uuid, boolean) from public, anon;
grant execute on function public.panel_set_menu_item_available(uuid, boolean) to authenticated;
