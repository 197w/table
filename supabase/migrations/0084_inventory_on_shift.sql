-- 0084: Inwentaryzacja z telefonu tylko na zmianie (10.11.2026, prośba użytkownika).
-- Pracownik w Table for employees (jego własne konto, `private.my_members()`) robi spis, dostawy i usunięcia tylko
-- w trakcie swojej zmiany w tym lokalu. Panel na komputerze bez zmian (konto lokalu z zalogowanym pracownikiem).

create or replace function private.inventory_allowed(p_restaurant_id uuid, p_member_id uuid, p_permission text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_member_id is not null
     and exists (
       select 1 from private.my_members() m
       where m.id = p_member_id and m.restaurant_id = p_restaurant_id
     )
     and not exists (
       select 1 from public.staff_shifts s
       where s.member_id = p_member_id and s.ended_at is null
     ) then
    raise exception 'Inwentaryzację robisz na zmianie. Zeskanuj kod z panelu, żeby ją zacząć.';
  end if;
  if private.has_permission(p_restaurant_id, p_permission) then
    return;
  end if;
  if p_member_id is not null and exists (
    select 1 from private.my_members() m
    where m.id = p_member_id and m.restaurant_id = p_restaurant_id
      and p_permission = any (private.member_permissions(m.id))
  ) then
    return;
  end if;
  raise exception 'Nie masz uprawnień do tej części panelu.';
end;
$$;
