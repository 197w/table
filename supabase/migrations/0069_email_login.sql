-- Logowanie e-mailem w Table i Table for employees (10.2026).
-- Rejestracja: numer telefonu → e-mail → kod z e-maila → hasło. Logowanie: e-mail → kod z e-maila → hasło.
-- Numer telefonu konta leży w profiles.phone (bez SMS-a), jeden numer = jedno konto. Stare konta z logowania
-- SMS dostają numer z auth.users.phone; wszystkie funkcje biorą numer konta z private.account_phone.

alter table public.profiles add column if not exists phone text;

-- Numer zawsze jako 48 i 9 cyfr (jak auth.users.phone), tylko polskie numery.
create or replace function private.profiles_phone_check()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_key text;
begin
  if new.phone is not null and (tg_op = 'INSERT' or new.phone is distinct from old.phone) then
    v_key := private.customer_phone_key(new.phone);
    if v_key is null then
      raise exception 'Wpisz 9-cyfrowy numer telefonu.';
    end if;
    new.phone := '48' || v_key;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_phone_check on public.profiles;
create trigger profiles_phone_check
  before insert or update of phone on public.profiles
  for each row execute function private.profiles_phone_check();

-- Stare konta: numer z logowania SMS.
update public.profiles p
set phone = u.phone
from auth.users u
where u.id = p.id
  and p.phone is null
  and private.customer_phone_key(u.phone) is not null;

create unique index if not exists profiles_phone_unique
  on public.profiles (private.phone_key(phone))
  where phone is not null;

-- Numer telefonu konta: z profilu, a u starych kont bez profilu z logowania SMS.
create or replace function private.account_phone(p_user uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select p.phone from public.profiles p where p.id = p_user),
    (select nullif(u.phone, '') from auth.users u where u.id = p_user)
  )
$$;

-- Czy numer należy już do innego konta (profil albo stare logowanie SMS).
create or replace function private.phone_taken(p_key text, p_except uuid default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.phone is not null and private.phone_key(p.phone) = p_key
      and p.id is distinct from p_except
  ) or exists (
    select 1 from auth.users u
    where coalesce(u.phone, '') <> '' and private.phone_key(u.phone) = p_key
      and u.id is distinct from p_except
  )
$$;

-- Rejestracja bez logowania: czy numer albo e-mail ma już konto. Null: można zakładać.
create or replace function public.auth_signup_check(p_phone text default null, p_email text default null)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  if p_phone is not null then
    v_key := private.customer_phone_key(p_phone);
    if v_key is null then
      raise exception 'Wpisz 9-cyfrowy numer telefonu.';
    end if;
    if private.phone_taken(v_key) then
      return 'phone_taken';
    end if;
  end if;

  if p_email is not null then
    if btrim(p_email) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      raise exception 'Wpisz poprawny adres e-mail.';
    end if;
    -- Konto bez potwierdzonego e-maila (porzucona rejestracja) nie blokuje nowej.
    if exists (
      select 1 from auth.users u
      where lower(u.email) = lower(btrim(p_email)) and u.email_confirmed_at is not null
    ) then
      return 'email_taken';
    end if;
  end if;
  return null;
end;
$$;

revoke all on function public.auth_signup_check(text, text) from public;
grant execute on function public.auth_signup_check(text, text) to anon, authenticated;

-- Stan konta po kodzie z e-maila: numer, e-mail i czy ma hasło (czego jeszcze brakuje).
create or replace function public.account_status()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'phone', private.account_phone(u.id),
    'email', u.email,
    'has_password', coalesce(u.encrypted_password, '') <> ''
  )
  from auth.users u
  where u.id = (select auth.uid())
$$;

revoke all on function public.account_status() from public, anon;
grant execute on function public.account_status() to authenticated;

-- Numer telefonu konta (rejestracja, uzupełnienie, zmiana w ustawieniach). Zwraca numer 48XXXXXXXXX.
create or replace function public.account_set_phone(p_phone text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_key text := private.customer_phone_key(p_phone);
begin
  if v_uid is null then
    raise exception 'Zaloguj się ponownie.';
  end if;
  if v_key is null then
    raise exception 'Wpisz 9-cyfrowy numer telefonu.';
  end if;
  if private.phone_taken(v_key, v_uid) then
    raise exception 'Ten numer telefonu ma już konto Table. Zaloguj się na nie.';
  end if;

  insert into public.profiles (id, phone) values (v_uid, '48' || v_key)
  on conflict (id) do update set phone = excluded.phone;
  return '48' || v_key;
exception
  when unique_violation then
    raise exception 'Ten numer telefonu ma już konto Table. Zaloguj się na nie.';
end;
$$;

revoke all on function public.account_set_phone(text) from public, anon;
grant execute on function public.account_set_phone(text) to authenticated;

-- Pracownik po numerze konta (wcześniej tylko auth.users.phone z logowania SMS).
create or replace function private.my_members()
returns setof public.staff_members
language sql
stable
security definer
set search_path = ''
as $$
  select m.*
  from public.staff_members m,
       (select private.account_phone((select auth.uid())) as phone) a
  where a.phone is not null
    and m.active
    and private.norm_phone(m.phone) = private.norm_phone(a.phone)
$$;

create or replace function private.customer_key(p_user uuid, p_phone text, p_name text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    'tel:' || coalesce(
      private.customer_phone_key(private.account_phone(p_user)),
      private.customer_phone_key(p_phone)
    ),
    p_user::text,
    'imie:' || nullif(lower(btrim(p_name)), '')
  )
$$;

-- Pozostałe funkcje z numerem konta: u.phone → private.account_phone(u.id).
do $$
declare
  v_fn regprocedure;
  v_def text;
begin
  for v_fn in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('panel_customer_app_address', 'panel_customers', 'panel_reservations', 'panel_waitlist')
  loop
    v_def := pg_get_functiondef(v_fn);
    v_def := regexp_replace(v_def, '\mu\.phone\M', 'private.account_phone(u.id)', 'g');
    execute v_def;
  end loop;
end;
$$;
