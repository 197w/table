-- Table · migracja 0032
-- Bez głównego stanowiska (prośba użytkownika): pracownicy logują się kodem i kodem QR na każdym komputerze
-- z panelem lokalu. Parametr p_device zostaje w funkcjach (starsze panele go wysyłają), ale nic nie znaczy.
-- Znika też uprawnienie „Ustawienia” (zakładka miała tylko główne stanowisko).

drop function public.panel_new_login_token(uuid, text);
create or replace function public.panel_new_login_token(p_restaurant_id uuid, p_device text default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token  text := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
begin
  perform private.require_staff(p_restaurant_id);
  delete from panel_login_tokens
  where restaurant_id = p_restaurant_id and expires_at < now() - interval '1 hour';
  insert into panel_login_tokens (token, restaurant_id, created_by) values (v_token, p_restaurant_id, auth.uid());
  return v_token;
end;
$$;

drop function public.panel_member_login(uuid, text, text);
create or replace function public.panel_member_login(p_restaurant_id uuid, p_code text, p_device text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member  uuid;
  v_code    text := btrim(coalesce(p_code, ''));
begin
  perform private.require_staff(p_restaurant_id);

  if (select count(*) from station_login_failures
      where restaurant_id = p_restaurant_id and at > now() - interval '5 minutes') >= 10 then
    return jsonb_build_object('error', 'Za dużo błędnych kodów. Spróbuj ponownie za kilka minut.');
  end if;

  select c.member_id into v_member
  from staff_codes c
  join staff_members m on m.id = c.member_id and m.active
  where c.restaurant_id = p_restaurant_id
    and v_code ~ '^[0-9]{4}$'
    and c.code_hash = private.staff_code_hash(p_restaurant_id, v_code);

  if v_member is null then
    delete from station_login_failures where restaurant_id = p_restaurant_id and at < now() - interval '1 day';
    insert into station_login_failures (restaurant_id) values (p_restaurant_id);
    return jsonb_build_object('error', 'Nieprawidłowy kod.');
  end if;

  insert into staff_shifts (restaurant_id, member_id, source)
  values (p_restaurant_id, v_member, 'station')
  on conflict do nothing;
  return private.member_session(v_member);
end;
$$;

revoke execute on function public.panel_new_login_token(uuid, text) from public, anon;
revoke execute on function public.panel_member_login(uuid, text, text) from public, anon;
grant execute on function public.panel_new_login_token(uuid, text) to authenticated;
grant execute on function public.panel_member_login(uuid, text, text) to authenticated;

drop function public.panel_set_main_station(uuid, text, text, boolean, boolean);
drop function private.check_station(uuid, text);
drop table public.main_stations;

-- Uprawnienie „Ustawienia” znika.
create or replace function private.all_permissions()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['reservations', 'floor', 'floor_edit', 'orders', 'orders_close', 'orders_cancel', 'deliveries',
               'kitchen', 'kitchen_settings', 'staff', 'staff_logins', 'schedule', 'timesheet', 'positions',
               'profile', 'menu', 'gift_cards', 'reviews', 'stats']
$$;

update public.staff_positions
set permissions = case when system_key = 'all' then private.all_permissions() else array_remove(permissions, 'settings') end
where 'settings' = any (permissions) or system_key = 'all';
