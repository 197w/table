-- Table · migracja 0043
-- 1. Dane właściciela w „Dane lokalu”: osobna tabela, którą czyta i zmienia tylko kierownik i właściciel lokalu.
--    Goście (aplikacja Table) i pracownicy (Table for employees) jej nie widzą. NIP przechodzi tu z restaurants,
--    bo kolumny restaurants są publiczne dla gości.
-- 2. „Zakończ zmianę” z paska nad zakładką potwierdza kod albo kod QR tej samej osoby (p_member_id, for_member).

-- ---------------------------------------------------------------
-- 1. Dane właściciela
-- ---------------------------------------------------------------

create table public.restaurant_owner_details (
  restaurant_id    uuid primary key references public.restaurants (id) on delete cascade,
  owner_name       text check (char_length(owner_name) <= 120),
  owner_phone      text check (char_length(owner_phone) <= 20),
  owner_email      text check (char_length(owner_email) <= 200),
  company_name     text check (char_length(company_name) <= 200),
  nip              text check (nip ~ '^[0-9]{10}$'),
  company_address  text check (char_length(company_address) <= 300),
  updated_at       timestamptz not null default now(),
  updated_by       uuid references auth.users (id) on delete set null
);

alter table public.restaurant_owner_details enable row level security;

create policy "Kierownik i właściciel widzą dane właściciela"
  on public.restaurant_owner_details for select to authenticated
  using (private.has_staff_role(restaurant_id, 'manager'));

revoke all on public.restaurant_owner_details from anon, authenticated;
grant select on public.restaurant_owner_details to authenticated;

insert into public.restaurant_owner_details (restaurant_id, nip)
select id, case when nip ~ '^[0-9]{10}$' then nip end from public.restaurants;

alter table public.restaurants alter column nip drop not null;
update public.restaurants set nip = null where nip is not null;

-- Zapis danych właściciela. Puste pole czyści wpis.
create or replace function public.panel_set_owner_details(
  p_restaurant_id    uuid,
  p_owner_name       text,
  p_owner_phone      text,
  p_owner_email      text,
  p_company_name     text,
  p_nip              text,
  p_company_address  text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nip    text := nullif(regexp_replace(coalesce(p_nip, ''), '[^0-9]', '', 'g'), '');
  v_email  text := nullif(lower(btrim(coalesce(p_owner_email, ''))), '');
  v_phone  text := nullif(regexp_replace(coalesce(p_owner_phone, ''), '[^0-9+]', '', 'g'), '');
begin
  perform private.require_staff(p_restaurant_id, 'manager');
  if v_nip is not null and length(v_nip) <> 10 then
    raise exception 'NIP ma 10 cyfr.';
  end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Sprawdź adres e-mail właściciela.';
  end if;
  if v_phone is not null and length(regexp_replace(v_phone, '[^0-9]', '', 'g')) < 9 then
    raise exception 'Telefon właściciela ma co najmniej 9 cyfr.';
  end if;

  insert into restaurant_owner_details as d (
    restaurant_id, owner_name, owner_phone, owner_email, company_name, nip, company_address, updated_at, updated_by
  )
  values (
    p_restaurant_id,
    nullif(btrim(coalesce(p_owner_name, '')), ''),
    v_phone,
    v_email,
    nullif(btrim(coalesce(p_company_name, '')), ''),
    v_nip,
    nullif(btrim(coalesce(p_company_address, '')), ''),
    now(),
    auth.uid()
  )
  on conflict (restaurant_id) do update
  set owner_name = excluded.owner_name,
      owner_phone = excluded.owner_phone,
      owner_email = excluded.owner_email,
      company_name = excluded.company_name,
      nip = excluded.nip,
      company_address = excluded.company_address,
      updated_at = excluded.updated_at,
      updated_by = excluded.updated_by;
end;
$$;

revoke execute on function public.panel_set_owner_details(uuid, text, text, text, text, text, text) from public, anon;
grant execute on function public.panel_set_owner_details(uuid, text, text, text, text, text, text) to authenticated;

-- Nowy lokal: NIP trafia do danych właściciela, e-mail właściciela to e-mail konta, które zakłada lokal.
create or replace function public.panel_create_restaurant(
  p_name text, p_nip text, p_city text, p_address text, p_phone text, p_cuisine text
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid       uuid := auth.uid();
  v_nip       text := regexp_replace(coalesce(p_nip, ''), '[^0-9]', '', 'g');
  v_location  geography;
  v_id        uuid;
begin
  if v_uid is null then
    raise exception 'Zaloguj się, żeby utworzyć lokal.';
  end if;
  if coalesce(btrim(p_name), '') = '' or coalesce(btrim(p_city), '') = ''
     or coalesce(btrim(p_address), '') = '' or coalesce(btrim(p_cuisine), '') = '' then
    raise exception 'Uzupełnij nazwę, miasto, adres i rodzaj kuchni.';
  end if;
  if length(v_nip) <> 10 then
    raise exception 'NIP ma 10 cyfr.';
  end if;
  if length(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')) < 9 then
    raise exception 'Wpisz numer telefonu lokalu, co najmniej 9 cyfr.';
  end if;
  if (select count(*) from restaurant_staff where user_id = v_uid and role = 'owner') >= 5 then
    raise exception 'Jedno konto może mieć najwyżej 5 lokali. Napisz do nas, jeśli potrzebujesz więcej.';
  end if;

  select st_centroid(st_collect(r.location::geometry))::geography into v_location
  from restaurants r
  where r.listed and lower(r.city) = lower(btrim(p_city));
  v_location := coalesce(v_location, st_setsrid(st_makepoint(19.4, 52.0), 4326)::geography);

  insert into restaurants (name, cuisine, address, city, phone, location, plan, listed)
  values (btrim(p_name), btrim(p_cuisine), btrim(p_address), btrim(p_city), btrim(p_phone),
          v_location, 'free', false)
  returning id into v_id;

  insert into restaurant_staff (restaurant_id, user_id, role) values (v_id, v_uid, 'owner');
  insert into restaurant_owner_details (restaurant_id, nip, owner_email, updated_by)
  values (v_id, v_nip, (select lower(email) from auth.users where id = v_uid), v_uid);
  return v_id;
end;
$$;

-- ---------------------------------------------------------------
-- 2. Koniec zmiany potwierdzony kodem tej samej osoby
-- ---------------------------------------------------------------

alter table public.panel_login_tokens
  add column for_member uuid references public.staff_members (id) on delete cascade;

drop function public.panel_new_login_token(uuid, text, text);
create or replace function public.panel_new_login_token(
  p_restaurant_id  uuid,
  p_device         text default null,
  p_purpose        text default 'login',
  p_member_id      uuid default null
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
  if p_member_id is not null
     and not exists (select 1 from staff_members where id = p_member_id and restaurant_id = p_restaurant_id) then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  delete from panel_login_tokens
  where restaurant_id = p_restaurant_id and expires_at < now() - interval '1 hour';
  insert into panel_login_tokens (token, restaurant_id, created_by, purpose, for_member)
  values (v_token, p_restaurant_id, auth.uid(), coalesce(p_purpose, 'login'), p_member_id);
  return v_token;
end;
$$;

drop function public.panel_member_end_shift(uuid, text);
create or replace function public.panel_member_end_shift(p_restaurant_id uuid, p_code text, p_member_id uuid default null)
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
  if p_member_id is not null and v_found.member_id <> p_member_id then
    return jsonb_build_object(
      'error', 'To kod innej osoby. Wpisz kod: ' || (select name from staff_members where id = p_member_id) || '.'
    );
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

revoke execute on function public.panel_new_login_token(uuid, text, text, uuid) from public, anon;
revoke execute on function public.panel_member_end_shift(uuid, text, uuid) from public, anon;
grant execute on function public.panel_new_login_token(uuid, text, text, uuid) to authenticated;
grant execute on function public.panel_member_end_shift(uuid, text, uuid) to authenticated;

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
  v_other    text;
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
    if v_row.for_member is not null and v_row.for_member <> v_member.id then
      select name into v_other from staff_members where id = v_row.for_member;
      raise exception 'Ten kod kończy zmianę osoby: %. Zeskanować go może tylko ta osoba.', v_other;
    end if;
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
