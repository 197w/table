-- Table · migracja 0033
-- 1. Zdjęcia dań: menu_items.photo_url i publiczny bucket menu-photos (plik w folderze lokalu).
--    Zdjęcie wgrywa osoba z uprawnieniem „Edycja menu”, goście widzą je w aplikacji Table.
-- 2. Uprawnienia menu: „Edycja menu” (menu_edit: dania, ceny, sekcje, zdjęcia) i „Dostępność dań”
--    (menu_availability: „Skończyło się”). Stanowiska z „Menu” dostają oba, Kelner i Kucharz dostępność.

alter table public.menu_items add column photo_url text check (char_length(photo_url) <= 500);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('menu-photos', 'menu-photos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp']);

-- Plik „<lokal>/<nazwa>”: zapis tylko z uprawnieniem „Edycja menu” w tym lokalu.
create or replace function private.can_edit_menu_files(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id  uuid;
begin
  begin
    v_id := split_part(p_name, '/', 1)::uuid;
  exception
    when others then return false;
  end;
  return private.has_permission(v_id, 'menu_edit');
end;
$$;

revoke execute on function private.can_edit_menu_files(text) from public, anon;
grant execute on function private.can_edit_menu_files(text) to authenticated;

create policy "Edycja menu dodaje zdjęcia dań"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'menu-photos' and private.can_edit_menu_files(name));

create policy "Edycja menu zmienia zdjęcia dań"
  on storage.objects for update to authenticated
  using (bucket_id = 'menu-photos' and private.can_edit_menu_files(name))
  with check (bucket_id = 'menu-photos' and private.can_edit_menu_files(name));

create policy "Edycja menu usuwa zdjęcia dań"
  on storage.objects for delete to authenticated
  using (bucket_id = 'menu-photos' and private.can_edit_menu_files(name));

create policy "Edycja menu widzi zdjęcia dań"
  on storage.objects for select to authenticated
  using (bucket_id = 'menu-photos' and private.can_edit_menu_files(name));

-- Uprawnienia
create or replace function private.all_permissions()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['reservations', 'floor', 'floor_edit', 'orders', 'orders_close', 'orders_cancel', 'deliveries',
               'kitchen', 'kitchen_settings', 'staff', 'staff_logins', 'schedule', 'timesheet', 'positions',
               'profile', 'menu', 'menu_edit', 'menu_availability', 'gift_cards', 'reviews', 'stats']
$$;

update public.staff_positions
set permissions = case
  when system_key = 'all' then private.all_permissions()
  when system_key in ('waiter', 'cook') then array(select distinct unnest(permissions || array['menu_availability']))
  when 'menu' = any (permissions) then array(select distinct unnest(permissions || array['menu_edit', 'menu_availability']))
  else permissions
end;

-- Edycja menu także dla kont pracowników z uprawnieniem (kierownik ma je zawsze).
create policy "Edycja menu z uprawnieniem zmienia sekcje"
  on public.menu_sections for all to authenticated
  using (private.has_permission(restaurant_id, 'menu_edit'))
  with check (private.has_permission(restaurant_id, 'menu_edit'));

create policy "Edycja menu z uprawnieniem zmienia pozycje"
  on public.menu_items for all to authenticated
  using (exists (
    select 1 from public.menu_sections s
    where s.id = menu_items.section_id and private.has_permission(s.restaurant_id, 'menu_edit')
  ))
  with check (exists (
    select 1 from public.menu_sections s
    where s.id = menu_items.section_id and private.has_permission(s.restaurant_id, 'menu_edit')
  ));

-- „Skończyło się”: dostępność dań, a jak dotąd także zamówienia i kuchnia.
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
    private.has_permission(v_restaurant, 'menu_availability')
    or private.has_permission(v_restaurant, 'menu_edit')
    or private.has_permission(v_restaurant, 'orders')
    or private.has_permission(v_restaurant, 'kitchen')
  ) then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;

  update menu_items set available = coalesce(p_available, true) where id = p_item_id;
end;
$$;
