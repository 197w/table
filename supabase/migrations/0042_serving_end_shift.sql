-- Table · migracja 0042
-- 1. Zakładka „Wydanie” w panelu: dania gotowe z kuchni czekają, aż ktoś zaniesie je gościom.
--    Nowe uprawnienie „serving”. Stanowiska z „Zamówieniami” dostają je od razu, bo i tak mogły
--    oznaczać pozycje jako wydane w Zamówieniach.
-- 2. „Zakończ zmianę” w menu bocznym panelu: pracownik kończy pracę swoim kodem albo kodem QR.
--    Kod QR ma cel (panel_login_tokens.purpose): login zaczyna zmianę, end_shift ją kończy.

-- ---------------------------------------------------------------
-- 1. Wydanie
-- ---------------------------------------------------------------

create or replace function private.all_permissions()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['reservations', 'floor', 'floor_edit', 'orders', 'orders_close', 'orders_cancel', 'deliveries',
               'kitchen', 'kitchen_settings', 'serving', 'staff', 'staff_logins', 'schedule', 'timesheet', 'positions',
               'profile', 'menu', 'menu_edit', 'menu_availability', 'inventory_edit', 'inventory_count',
               'reviews', 'stats']
$$;

update public.staff_positions set permissions = private.all_permissions() where system_key = 'all';
update public.staff_positions
set permissions = array_append(permissions, 'serving')
where system_key is null and 'orders' = any (permissions) and not ('serving' = any (permissions));

-- Wydanie dań gotowych z kuchni (ready → served). p_undo cofa pomyłkę (served → ready).
create or replace function public.panel_serve_items(p_item_ids uuid[], p_undo boolean default false)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
  v_count       integer;
begin
  for v_restaurant in
    select distinct restaurant_id from order_items where id = any (p_item_ids)
  loop
    if not (
      private.has_permission(v_restaurant, 'serving')
      or private.has_permission(v_restaurant, 'orders')
    ) then
      raise exception 'Nie masz uprawnień do tej części panelu.';
    end if;
  end loop;

  with changed as (
    update order_items i
    set status = case when p_undo then 'ready'::order_item_status else 'served'::order_item_status end
    from orders o
    where o.id = i.order_id
      and o.status = 'open'
      and o.kind = 'dine_in'
      and i.id = any (p_item_ids)
      and i.status = case when p_undo then 'served'::order_item_status else 'ready'::order_item_status end
    returning 1
  )
  select count(*) into v_count from changed;
  return v_count;
end;
$$;

revoke execute on function public.panel_serve_items(uuid[], boolean) from public, anon;
grant execute on function public.panel_serve_items(uuid[], boolean) to authenticated;

-- ---------------------------------------------------------------
-- 2. Koniec zmiany kodem albo kodem QR
-- ---------------------------------------------------------------

alter table public.panel_login_tokens
  add column purpose text not null default 'login' check (purpose in ('login', 'end_shift'));

drop function public.panel_new_login_token(uuid, text);
create or replace function public.panel_new_login_token(
  p_restaurant_id  uuid,
  p_device         text default null,
  p_purpose        text default 'login'
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token  text := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
begin
  perform private.require_staff(p_restaurant_id);
  if coalesce(p_purpose, 'login') not in ('login', 'end_shift') then
    raise exception 'Nieznany rodzaj kodu.';
  end if;
  delete from panel_login_tokens
  where restaurant_id = p_restaurant_id and expires_at < now() - interval '1 hour';
  insert into panel_login_tokens (token, restaurant_id, created_by, purpose)
  values (v_token, p_restaurant_id, auth.uid(), coalesce(p_purpose, 'login'));
  return v_token;
end;
$$;

-- Pracownik po czterocyfrowym kodzie. Błędny kod zapisuje próbę (po 10 w 5 minut lokal wstrzymuje logowanie kodem).
-- Zwraca member_id albo error (bez wyjątku, żeby zapis próby nie przepadł).
create or replace function private.member_by_code(p_restaurant_id uuid, p_code text, out member_id uuid, out error text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code  text := btrim(coalesce(p_code, ''));
begin
  if (select count(*) from public.station_login_failures f
      where f.restaurant_id = p_restaurant_id and f.at > now() - interval '5 minutes') >= 10 then
    error := 'Za dużo błędnych kodów. Spróbuj ponownie za kilka minut.';
    return;
  end if;

  select c.member_id into member_id
  from public.staff_codes c
  join public.staff_members m on m.id = c.member_id and m.active
  where c.restaurant_id = p_restaurant_id
    and v_code ~ '^[0-9]{4}$'
    and c.code_hash = private.staff_code_hash(p_restaurant_id, v_code);

  if member_id is null then
    delete from public.station_login_failures f where f.restaurant_id = p_restaurant_id and f.at < now() - interval '1 day';
    insert into public.station_login_failures (restaurant_id) values (p_restaurant_id);
    error := 'Nieprawidłowy kod.';
  end if;
end;
$$;

revoke execute on function private.member_by_code(uuid, text) from public, anon;
grant execute on function private.member_by_code(uuid, text) to authenticated;

create or replace function public.panel_member_login(p_restaurant_id uuid, p_code text, p_device text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_found  record;
begin
  perform private.require_staff(p_restaurant_id);
  select * into v_found from private.member_by_code(p_restaurant_id, p_code);
  if v_found.error is not null then
    return jsonb_build_object('error', v_found.error);
  end if;

  insert into staff_shifts (restaurant_id, member_id, source)
  values (p_restaurant_id, v_found.member_id, 'station')
  on conflict do nothing;
  return private.member_session(v_found.member_id);
end;
$$;

-- „Zakończ zmianę” w panelu: kod pracownika kończy jego trwającą zmianę.
create or replace function public.panel_member_end_shift(p_restaurant_id uuid, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_found    record;
  v_started  timestamptz;
  v_ended    timestamptz;
begin
  perform private.require_staff(p_restaurant_id);
  select * into v_found from private.member_by_code(p_restaurant_id, p_code);
  if v_found.error is not null then
    return jsonb_build_object('error', v_found.error);
  end if;

  update staff_shifts set ended_at = now()
  where member_id = v_found.member_id and ended_at is null
  returning started_at, ended_at into v_started, v_ended;
  if v_started is null then
    return jsonb_build_object(
      'error', (select name from staff_members where id = v_found.member_id) || ' nie ma teraz zmiany.'
    );
  end if;

  return private.member_session(v_found.member_id)
    || jsonb_build_object('ended_shift_started_at', v_started, 'ended_at', v_ended);
end;
$$;

revoke execute on function public.panel_new_login_token(uuid, text, text) from public, anon;
revoke execute on function public.panel_member_login(uuid, text, text) from public, anon;
revoke execute on function public.panel_member_end_shift(uuid, text) from public, anon;
grant execute on function public.panel_new_login_token(uuid, text, text) to authenticated;
grant execute on function public.panel_member_login(uuid, text, text) to authenticated;
grant execute on function public.panel_member_end_shift(uuid, text) to authenticated;

-- Panel pyta, kto zeskanował kod. Przy kodzie „Zakończ zmianę” dokłada godziny zakończonej zmiany.
create or replace function public.panel_login_token_status(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row    panel_login_tokens%rowtype;
  v_shift  staff_shifts%rowtype;
begin
  select * into v_row from panel_login_tokens where token = p_token;
  if not found then
    return null;
  end if;
  perform private.require_staff(v_row.restaurant_id);
  if v_row.claimed_member_id is null then
    return jsonb_build_object('claimed', false, 'expired', v_row.expires_at < now());
  end if;
  if v_row.purpose = 'end_shift' then
    select * into v_shift from staff_shifts
    where member_id = v_row.claimed_member_id and ended_at is not null
    order by ended_at desc limit 1;
    return private.member_session(v_row.claimed_member_id)
      || jsonb_build_object('ended_shift_started_at', v_shift.started_at, 'ended_at', v_shift.ended_at);
  end if;
  return private.member_session(v_row.claimed_member_id);
end;
$$;

-- Skan kodu w aplikacji. Kod „Wejdź na zmianę” zaczyna zmianę i loguje w panelu,
-- kod „Zakończ zmianę” kończy trwającą zmianę.
create or replace function public.staff_scan(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row      panel_login_tokens%rowtype;
  v_member   staff_members%rowtype;
  v_started  timestamptz;
  v_ended    timestamptz;
  v_new      boolean := false;
  v_opened   boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Zaloguj się w aplikacji.';
  end if;

  select * into v_row from panel_login_tokens
  where token = regexp_replace(coalesce(p_token, ''), '^table-praca:', '')
  for update;
  if not found then
    raise exception 'To nie jest kod z panelu Table. Zeskanuj kod z ekranu „Wejdź na zmianę”.';
  end if;
  if v_row.expires_at < now() then
    raise exception 'Kod już wygasł. Zeskanuj nowy kod z panelu.';
  end if;

  select * into v_member from private.my_members() m where m.restaurant_id = v_row.restaurant_id limit 1;
  if not found then
    raise exception 'Nie ma Cię na liście pracowników tego lokalu. Poproś kierownika o dodanie.';
  end if;

  if v_member.user_id is distinct from auth.uid() then
    update staff_members set user_id = auth.uid() where id = v_member.id;
  end if;

  if v_row.purpose = 'end_shift' then
    update staff_shifts set ended_at = now()
    where member_id = v_member.id and ended_at is null
    returning started_at, ended_at into v_started, v_ended;
    if v_started is null then
      raise exception 'Nie masz teraz zmiany w tym lokalu.';
    end if;
    if v_row.claimed_member_id is null then
      update panel_login_tokens set claimed_member_id = v_member.id, claimed_at = now() where token = v_row.token;
    end if;
    return jsonb_build_object(
      'restaurant', (select name from restaurants where id = v_member.restaurant_id),
      'member', v_member.name,
      'member_id', v_member.id,
      'token', v_row.token,
      'ended_now', true,
      'ended_shift_started_at', v_started,
      'ended_at', v_ended
    );
  end if;

  select started_at into v_started from staff_shifts where member_id = v_member.id and ended_at is null;
  if v_started is null then
    insert into staff_shifts (restaurant_id, member_id, source)
    values (v_member.restaurant_id, v_member.id, 'scan')
    returning started_at into v_started;
    v_new := true;
  end if;

  if v_row.claimed_member_id is null then
    update panel_login_tokens set claimed_member_id = v_member.id, claimed_at = now() where token = v_row.token;
    v_opened := true;
  end if;

  return jsonb_build_object(
    'restaurant', (select name from restaurants where id = v_member.restaurant_id),
    'member', v_member.name,
    'member_id', v_member.id,
    'token', v_row.token,
    'shift_started_at', v_started,
    'started_now', v_new,
    'opened_panel', v_opened or v_row.claimed_member_id = v_member.id
  );
end;
$$;
