-- Table · migracja 0023
-- Komunikat przy łączeniu pracownika z kontem bez nazw technicznych: czyta go właściciel lokalu.

create or replace function public.panel_link_staff_account(p_member_id uuid, p_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member  staff_members%rowtype;
  v_user    uuid;
begin
  select * into v_member from staff_members where id = p_member_id;
  if not found then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  perform private.require_staff(v_member.restaurant_id, 'manager');

  select id into v_user from auth.users where lower(email) = lower(btrim(p_email));
  if v_user is null then
    raise exception 'Nie ma konta Table z adresem %. Najpierw trzeba je założyć.', btrim(p_email);
  end if;

  if exists (
    select 1 from staff_members
    where restaurant_id = v_member.restaurant_id and user_id = v_user and id <> p_member_id
  ) then
    raise exception 'To konto jest już połączone z innym pracownikiem.';
  end if;

  insert into restaurant_staff (restaurant_id, user_id, role)
  values (v_member.restaurant_id, v_user, 'staff')
  on conflict do nothing;

  update staff_members set user_id = v_user where id = p_member_id;
end;
$$;
