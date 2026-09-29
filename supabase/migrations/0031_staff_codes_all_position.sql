-- Table · migracja 0031
-- 1. Zamiast loginu i hasła każdy pracownik ma czterocyfrowy kod, unikalny w lokalu. Kod widać w szczegółach
--    pracownika (uprawnienie „Kody pracowników”) i w jego aplikacji. Leży zaszyfrowany w Supabase Vault,
--    do logowania służy skrót sha256 z lokalem. Kod dostaje każdy pracownik od razu przy dodaniu.
--    Na stanowisku po 10 błędnych kodach w 5 minut logowanie kodem jest wstrzymane na kilka minut.
-- 2. Stanowisko systemowe „ALL”: zawsze wszystkie uprawnienia, także te dodane w przyszłości.

-- ---------------------------------------------------------------
-- 1. Kody pracowników
-- ---------------------------------------------------------------

-- Loginy i hasła z 0029–0030 znikają razem z zaszyfrowanymi hasłami.
delete from vault.secrets where id in (select password_secret from public.staff_accounts where password_secret is not null);
drop trigger staff_accounts_drop_password on public.staff_accounts;
drop function private.drop_staff_password();
drop function public.panel_create_staff_login(uuid, text);
drop function public.panel_set_staff_password(uuid, text);
drop function public.panel_staff_logins(uuid);
drop function public.staff_my_logins();
drop function public.panel_member_login(uuid, text, text, text);
drop function private.store_staff_password(uuid, text);
drop function private.clean_staff_password(text);
drop function private.easy_password();
drop table public.staff_accounts;

create table public.staff_codes (
  member_id      uuid primary key references public.staff_members (id) on delete cascade,
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  -- sha256(lokal:kod), po nim logowanie znajduje pracownika.
  code_hash      text not null,
  -- Kod zaszyfrowany w Vault, do podglądu.
  code_secret    uuid not null,
  updated_at     timestamptz not null default now(),
  unique (restaurant_id, code_hash)
);

alter table public.staff_codes enable row level security;
revoke all on public.staff_codes from anon, authenticated;
-- Bez polityk: kody czytają i zapisują tylko funkcje poniżej.

-- Błędne kody na stanowisku (do wstrzymania zgadywania).
create table public.station_login_failures (
  id             bigint generated always as identity primary key,
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  at             timestamptz not null default now()
);

create index station_login_failures_idx on public.station_login_failures (restaurant_id, at);
alter table public.station_login_failures enable row level security;
revoke all on public.station_login_failures from anon, authenticated;

create or replace function private.staff_code_hash(p_restaurant_id uuid, p_code text)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(extensions.digest(p_restaurant_id::text || ':' || p_code, 'sha256'), 'hex')
$$;

-- Losowy kod, którego nie ma jeszcze nikt w lokalu.
create or replace function private.random_staff_code(p_restaurant_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_raw   bytea;
  v_code  text;
begin
  for i in 1 .. 200 loop
    v_raw := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
    v_code := lpad(((get_byte(v_raw, 0) * 256 + get_byte(v_raw, 1)) % 10000)::text, 4, '0');
    if not exists (
      select 1 from public.staff_codes
      where restaurant_id = p_restaurant_id and code_hash = private.staff_code_hash(p_restaurant_id, v_code)
    ) then
      return v_code;
    end if;
  end loop;
  raise exception 'Nie udało się dobrać wolnego kodu. Spróbuj jeszcze raz.';
end;
$$;

-- Zapisuje kod pracownika: skrót do logowania i zaszyfrowaną kopię do podglądu.
create or replace function private.store_staff_code(p_member_id uuid, p_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurant  uuid;
  v_hash        text;
  v_secret      uuid;
begin
  if p_code !~ '^[0-9]{4}$' then
    raise exception 'Kod to dokładnie 4 cyfry.';
  end if;
  select restaurant_id into v_restaurant from public.staff_members where id = p_member_id;
  v_hash := private.staff_code_hash(v_restaurant, p_code);
  if exists (
    select 1 from public.staff_codes
    where restaurant_id = v_restaurant and code_hash = v_hash and member_id <> p_member_id
  ) then
    raise exception 'Ten kod ma już inny pracownik. Wybierz inny.';
  end if;

  select code_secret into v_secret from public.staff_codes where member_id = p_member_id;
  if v_secret is null then
    v_secret := vault.create_secret(p_code, null, 'Kod pracownika do głównego stanowiska Table');
    insert into public.staff_codes (member_id, restaurant_id, code_hash, code_secret)
    values (p_member_id, v_restaurant, v_hash, v_secret);
  else
    perform vault.update_secret(v_secret, p_code);
    update public.staff_codes set code_hash = v_hash, updated_at = now() where member_id = p_member_id;
  end if;
end;
$$;

revoke execute on function private.staff_code_hash(uuid, text) from public, anon, authenticated;
revoke execute on function private.random_staff_code(uuid) from public, anon, authenticated;
revoke execute on function private.store_staff_code(uuid, text) from public, anon, authenticated;

-- Nowy pracownik od razu dostaje kod.
create or replace function private.give_staff_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.store_staff_code(new.id, private.random_staff_code(new.restaurant_id));
  return new;
end;
$$;

create trigger staff_members_code
after insert on public.staff_members
for each row execute function private.give_staff_code();

-- Usunięcie kodu (np. z pracownikiem) usuwa też zaszyfrowaną kopię.
create or replace function private.drop_staff_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    delete from vault.secrets where id = old.code_secret;
  exception when insufficient_privilege then
    null;
  end;
  return old;
end;
$$;

create trigger staff_codes_drop_secret
after delete on public.staff_codes
for each row execute function private.drop_staff_code();

-- Obecni pracownicy dostają kody.
do $$
declare
  m  record;
begin
  for m in select id, restaurant_id from public.staff_members loop
    perform private.store_staff_code(m.id, private.random_staff_code(m.restaurant_id));
  end loop;
end;
$$;

-- Kody pracowników lokalu dla osoby z uprawnieniem „Kody pracowników”.
create or replace function public.panel_staff_codes(p_restaurant_id uuid)
returns table (member_id uuid, code text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform private.require_permission(p_restaurant_id, 'staff_logins');
  return query
    select c.member_id, s.decrypted_secret::text
    from staff_codes c
    join vault.decrypted_secrets s on s.id = c.code_secret
    where c.restaurant_id = p_restaurant_id;
end;
$$;

-- Nowy kod pracownika: wpisany (4 cyfry) albo wylosowany (puste). Stary przestaje działać.
create or replace function public.panel_set_staff_code(p_member_id uuid, p_code text default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
  v_code        text := nullif(btrim(coalesce(p_code, '')), '');
begin
  select restaurant_id into v_restaurant from staff_members where id = p_member_id;
  if v_restaurant is null then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  perform private.require_permission(v_restaurant, 'staff_logins');
  v_code := coalesce(v_code, private.random_staff_code(v_restaurant));
  perform private.store_staff_code(p_member_id, v_code);
  return v_code;
end;
$$;

-- Aplikacja Table for employees: mój kod do głównego stanowiska.
create or replace function public.staff_my_codes()
returns table (member_id uuid, code text)
language sql
stable
security definer
set search_path = public
as $$
  select c.member_id, s.decrypted_secret::text
  from staff_codes c
  join vault.decrypted_secrets s on s.id = c.code_secret
  where c.member_id in (select id from private.my_members())
$$;

-- Logowanie kodem na głównym stanowisku. Zaczyna zmianę, jeśli jeszcze nie trwa.
-- Błędny kod nie rzuca wyjątku, tylko zwraca {error}, żeby próba się zapisała.
create or replace function public.panel_member_login(p_restaurant_id uuid, p_code text, p_device text)
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
  perform private.check_station(p_restaurant_id, p_device);

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

revoke execute on function public.panel_staff_codes(uuid) from public, anon;
revoke execute on function public.panel_set_staff_code(uuid, text) from public, anon;
revoke execute on function public.staff_my_codes() from public, anon;
revoke execute on function public.panel_member_login(uuid, text, text) from public, anon;
grant execute on function public.panel_staff_codes(uuid) to authenticated;
grant execute on function public.panel_set_staff_code(uuid, text) to authenticated;
grant execute on function public.staff_my_codes() to authenticated;
grant execute on function public.panel_member_login(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------
-- 2. Stanowisko „ALL”: wszystkie uprawnienia
-- ---------------------------------------------------------------

-- Wszystkie uprawnienia panelu. Nowe uprawnienie dopisujemy tutaj, a „ALL” i kierownik mają je od razu.
create or replace function private.all_permissions()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['reservations', 'floor', 'floor_edit', 'orders', 'orders_close', 'orders_cancel', 'deliveries',
               'kitchen', 'kitchen_settings', 'staff', 'staff_logins', 'schedule', 'timesheet', 'positions',
               'profile', 'menu', 'gift_cards', 'settings', 'reviews', 'stats']
$$;

grant execute on function private.all_permissions() to authenticated;

-- Uprawnienia stanowiska: „ALL” zawsze wszystkie.
create or replace function private.position_permissions(p_position_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select case when p.system_key = 'all' then private.all_permissions() else coalesce(p.permissions, '{}') end
  from public.staff_positions p
  where p.id = p_position_id
$$;

revoke execute on function private.position_permissions(uuid) from public, anon;
grant execute on function private.position_permissions(uuid) to authenticated;

alter table public.staff_positions drop constraint staff_positions_system_key_check;
alter table public.staff_positions
  add constraint staff_positions_system_key_check check (system_key in ('waiter', 'cook', 'courier', 'all'));

insert into public.staff_positions (restaurant_id, system_key, name, permissions, sort)
values (null, 'all', 'ALL', private.all_permissions(), 0);

create or replace function private.has_permission(p_restaurant_id uuid, p_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_staff_role(p_restaurant_id, 'manager')
    or (
      private.has_staff_role(p_restaurant_id)
      and exists (
        select 1
        from public.staff_members m
        join public.staff_positions p on p.id = m.position_id
        where m.restaurant_id = p_restaurant_id
          and m.user_id = (select auth.uid())
          and m.active
          and (p.system_key = 'all' or p_permission = any (p.permissions))
      )
    )
$$;

create or replace function public.panel_my_permissions(p_restaurant_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when private.has_staff_role(p_restaurant_id, 'manager') then private.all_permissions()
    else coalesce((
      select private.position_permissions(m.position_id)
      from public.staff_members m
      where m.restaurant_id = p_restaurant_id
        and m.user_id = (select auth.uid())
        and m.active
      limit 1
    ), '{}')
  end
$$;

create or replace function private.member_session(p_member_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'claimed', true,
    'member_id', m.id,
    'name', m.name,
    'position', p.name,
    'permissions', to_jsonb(coalesce(private.position_permissions(m.position_id), '{}')),
    'shift_started_at', (select s.started_at from public.staff_shifts s where s.member_id = m.id and s.ended_at is null)
  )
  from public.staff_members m
  left join public.staff_positions p on p.id = m.position_id
  where m.id = p_member_id
$$;

create or replace function public.staff_my_jobs()
returns table (member_id uuid, restaurant_id uuid, restaurant_name text, member_name text,
               position_name text, permissions text[], shift_id uuid, shift_started_at timestamptz,
               week_seconds bigint)
language sql
stable
security definer
set search_path = public
as $$
  select m.id, r.id, r.name, m.name, p.name, coalesce(private.position_permissions(m.position_id), '{}'),
         s.id, s.started_at,
         (select coalesce(sum(extract(epoch from coalesce(x.ended_at, now()) - x.started_at)), 0)::bigint
          from staff_shifts x
          where x.member_id = m.id and x.started_at >= date_trunc('week', now()))
  from private.my_members() m
  join restaurants r on r.id = m.restaurant_id
  left join staff_positions p on p.id = m.position_id
  left join staff_shifts s on s.member_id = m.id and s.ended_at is null
  order by r.name
$$;

-- Wiktor Godlewski (REVE) dostaje stanowisko „ALL”.
update public.staff_members
set position_id = (select id from public.staff_positions where system_key = 'all'), position = 'ALL'
where name = 'Wiktor Godlewski';
