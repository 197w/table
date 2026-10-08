-- Podział rachunku już przy przyjmowaniu zamówienia: pozycja może należeć do osoby przy stoliku (1, 2, 3...).
-- Null: pozycja wspólna. Przy zamykaniu rachunku „Za wybrane pozycje” zaznacza jednym kliknięciem pozycje osoby.
-- panel_pay_items kopiuje cały wiersz przy dzieleniu ilości, więc osoba zostaje przy obu częściach.

alter table public.order_items
  add column guest_no smallint check (guest_no between 1 and 30);

drop function public.panel_add_order_item(uuid, uuid, text, text[], integer, text, integer, uuid, jsonb);
create function public.panel_add_order_item(
  p_order_id      uuid,
  p_menu_item_id  uuid,
  p_variant       text default null,
  p_addons        text[] default '{}',
  p_quantity      integer default 1,
  p_note          text default null,
  p_course        integer default 1,
  p_member_id     uuid default null,
  p_changes       jsonb default '[]'::jsonb,
  p_guest         smallint default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order    orders%rowtype;
  v_item     record;
  v_option   jsonb;
  v_price    integer;
  v_variant  text;
  v_addons   jsonb := '[]';
  v_name     text;
  v_id       uuid;
begin
  select * into v_order from orders where id = p_order_id;
  if not found then
    raise exception 'Nie znaleziono rachunku.';
  end if;
  perform private.require_permission(v_order.restaurant_id, 'orders');
  perform private.check_member(v_order.restaurant_id, p_member_id);
  if v_order.status <> 'open' then
    raise exception 'Ten rachunek jest już zamknięty.';
  end if;
  if p_guest is not null and p_guest not between 1 and 30 then
    raise exception 'Osoba od 1 do 30.';
  end if;

  select i.id, i.name, i.price_grosze, i.variants, i.addons, i.vat_rate, i.available, s.restaurant_id
  into v_item
  from menu_items i
  join menu_sections s on s.id = i.section_id
  where i.id = p_menu_item_id;
  if not found or v_item.restaurant_id <> v_order.restaurant_id then
    raise exception 'Nie znaleziono pozycji w menu.';
  end if;
  if not v_item.available then
    raise exception 'Ta pozycja jest chwilowo niedostępna.';
  end if;
  if p_quantity is null or p_quantity not between 1 and 99 then
    raise exception 'Ilość od 1 do 99.';
  end if;

  if jsonb_array_length(v_item.variants) > 0 then
    select o into v_option from jsonb_array_elements(v_item.variants) o where o ->> 'name' = p_variant;
    if v_option is null then
      raise exception 'Wybierz wariant pozycji „%”.', v_item.name;
    end if;
    v_price := (v_option ->> 'price_grosze')::integer;
    v_variant := v_option ->> 'name';
  else
    v_price := v_item.price_grosze;
  end if;

  foreach v_name in array coalesce(p_addons, '{}') loop
    v_option := null;
    select o into v_option from jsonb_array_elements(v_item.addons) o where o ->> 'name' = v_name;
    if v_option is null then
      raise exception 'Pozycja „%” nie ma dodatku „%”.', v_item.name, v_name;
    end if;
    v_price := v_price + (v_option ->> 'price_grosze')::integer;
    v_addons := v_addons || jsonb_build_array(v_option);
  end loop;

  insert into order_items (
    order_id, restaurant_id, menu_item_id, name, variant, addons,
    unit_price_grosze, vat_rate, quantity, note, course, created_by, created_by_member, changes, guest_no
  )
  values (
    p_order_id, v_order.restaurant_id, v_item.id, v_item.name, v_variant, v_addons,
    v_price, v_item.vat_rate, p_quantity, nullif(btrim(p_note), ''),
    greatest(1, least(5, coalesce(p_course, 1))), auth.uid(), p_member_id,
    private.item_changes(v_item.id, p_changes), p_guest
  )
  returning id into v_id;
  return v_id;
end;
$$;

-- Przeniesienie pozycji do osoby (null: wspólne). Tylko na otwartym rachunku na sali.
create or replace function public.panel_set_items_guest(p_item_ids uuid[], p_guest smallint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
begin
  if p_guest is not null and p_guest not between 1 and 30 then
    raise exception 'Osoba od 1 do 30.';
  end if;
  select distinct o.restaurant_id into v_restaurant
  from order_items i join orders o on o.id = i.order_id
  where i.id = any (p_item_ids);
  if v_restaurant is null then
    raise exception 'Nie znaleziono pozycji.';
  end if;
  perform private.require_permission(v_restaurant, 'orders');
  if exists (
    select 1 from order_items i join orders o on o.id = i.order_id
    where i.id = any (p_item_ids) and (o.status <> 'open' or o.restaurant_id <> v_restaurant)
  ) then
    raise exception 'Ten rachunek jest już zamknięty.';
  end if;
  update order_items set guest_no = p_guest where id = any (p_item_ids);
end;
$$;

revoke execute on function public.panel_add_order_item(uuid, uuid, text, text[], integer, text, integer, uuid, jsonb, smallint) from public, anon;
revoke execute on function public.panel_set_items_guest(uuid[], smallint) from public, anon;
grant execute on function public.panel_add_order_item(uuid, uuid, text, text[], integer, text, integer, uuid, jsonb, smallint) to authenticated;
grant execute on function public.panel_set_items_guest(uuid[], smallint) to authenticated;
