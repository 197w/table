-- Table · migracja 0029
-- 1. Login i krótkie hasło pracownika. Tworzy je osoba z uprawnieniem „Pracownicy”. Hasło widać tylko raz
--    (przy tworzeniu i przy nadaniu nowego), w bazie zostaje jego skrót bcrypt. Login widzi też sam pracownik.
--    Na razie służą do logowania na głównym stanowisku (panel), nie są kontem Supabase Auth.
-- 2. Główne stanowisko: jeden komputer lokalu, na którym pracownicy wchodzą na zmianę i nabijają zamówienia.
--    Zmiana stanowiska: wyłączyć na starym komputerze, włączyć na nowym.
-- 3. Logowanie na stanowisku: kod QR z aplikacji Table for employees albo login i hasło. Zaczyna zmianę.
-- 4. Grafik: osoba z uprawnieniem „Grafik” proponuje godziny, pracownik w aplikacji je przyjmuje albo proponuje inne.
-- 5. Statystyki pojedynczego pracownika.

-- ---------------------------------------------------------------
-- Pomocnicze
-- ---------------------------------------------------------------

-- Losowy napis z podanych znaków (gen_random_uuid korzysta z bezpiecznego generatora).
create or replace function private.random_text(p_chars text, p_len integer)
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_out  text := '';
  v_raw  bytea;
begin
  for i in 1 .. p_len loop
    -- Pierwsze 6 bajtów UUID v4 jest w pełni losowe.
    v_raw := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
    v_out := v_out || substr(p_chars, 1 + get_byte(v_raw, 0) % char_length(p_chars), 1);
  end loop;
  return v_out;
end;
$$;

-- Początek loginu z imienia i pierwszej litery nazwiska, bez polskich znaków: „Łucja Żak” → „lucja.z”.
create or replace function private.login_base(p_first text, p_last text)
returns text
language sql
immutable
set search_path = ''
as $$
  select coalesce(nullif(left(regexp_replace(translate(lower(coalesce(p_first, '')),
           'ąćęłńóśźżäöüéèáàíìúùý', 'acelnoszzaoueeaaiiuuy'), '[^a-z]', '', 'g'), 16), ''), 'pracownik')
      || coalesce('.' || nullif(left(regexp_replace(translate(lower(coalesce(p_last, '')),
           'ąćęłńóśźżäöüéèáàíìúùý', 'acelnoszzaoueeaaiiuuy'), '[^a-z]', '', 'g'), 1), ''), '')
$$;

revoke execute on function private.random_text(text, integer) from public, anon;
revoke execute on function private.login_base(text, text) from public, anon;
grant execute on function private.random_text(text, integer) to authenticated;
grant execute on function private.login_base(text, text) to authenticated;

-- Zmiana zaczęta logowaniem na stanowisku (login i hasło).
alter table public.staff_shifts drop constraint staff_shifts_source_check;
alter table public.staff_shifts
  add constraint staff_shifts_source_check check (source in ('scan', 'panel', 'station'));

-- Nowe uprawnienie „Grafik” (schedule): rozpisywanie godzin pracownikom.
create or replace function public.panel_my_permissions(p_restaurant_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when private.has_staff_role(p_restaurant_id, 'manager') then
      array['reservations', 'floor', 'floor_edit', 'menu', 'orders', 'kitchen',
            'deliveries', 'gift_cards', 'reviews', 'stats', 'staff', 'schedule', 'profile']
    else coalesce((
      select p.permissions
      from public.staff_members m
      join public.staff_positions p on p.id = m.position_id
      where m.restaurant_id = p_restaurant_id
        and m.user_id = (select auth.uid())
        and m.active
      limit 1
    ), '{}')
  end
$$;

-- ---------------------------------------------------------------
-- 1. Login i hasło pracownika
-- ---------------------------------------------------------------

create table public.staff_accounts (
  member_id        uuid primary key references public.staff_members (id) on delete cascade,
  restaurant_id    uuid not null references public.restaurants (id) on delete cascade,
  login            text not null unique check (login ~ '^[a-z][a-z0-9.]{2,39}$'),
  -- Skrót bcrypt. Samego hasła baza nie przechowuje: pokazujemy je raz, przy tworzeniu albo zmianie.
  password_hash    text not null,
  failed_attempts  smallint not null default 0,
  locked_until     timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index staff_accounts_restaurant_idx on public.staff_accounts (restaurant_id);
alter table public.staff_accounts enable row level security;

create policy "Loginy pracowników widzi osoba z uprawnieniem Pracownicy"
  on public.staff_accounts for select to authenticated
  using (private.has_permission(restaurant_id, 'staff'));

create policy "Pracownik widzi swój login"
  on public.staff_accounts for select to authenticated
  using (member_id in (select id from private.my_members()));

-- Zapis tylko przez funkcje poniżej. Skrótu hasła aplikacje nie czytają.
-- (Uprawnienie do kolumn działa tylko bez uprawnienia do całej tabeli, stąd revoke i grant.)
revoke all on public.staff_accounts from anon, authenticated;
grant select (member_id, restaurant_id, login, failed_attempts, locked_until, created_at, updated_at)
  on public.staff_accounts to authenticated;

-- Tworzy login i krótkie hasło (6 znaków bez mylących 0/o, 1/l/i). Hasło wraca tylko w tej odpowiedzi.
create or replace function public.panel_create_staff_login(p_member_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member    staff_members%rowtype;
  v_base      text;
  v_login     text;
  v_password  text := private.random_text('abcdefghjkmnpqrstuvwxyz23456789', 6);
begin
  select * into v_member from staff_members where id = p_member_id;
  if not found then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  perform private.require_permission(v_member.restaurant_id, 'staff');
  if exists (select 1 from staff_accounts where member_id = p_member_id) then
    raise exception 'Ten pracownik ma już login. Możesz mu nadać nowe hasło.';
  end if;

  v_base := private.login_base(coalesce(v_member.first_name, v_member.name), v_member.last_name);
  for i in 1 .. 40 loop
    v_login := v_base || private.random_text('0123456789', case when i <= 20 then 2 else 3 end);
    exit when not exists (select 1 from staff_accounts where login = v_login);
    v_login := null;
  end loop;
  if v_login is null then
    raise exception 'Nie udało się dobrać wolnego loginu. Spróbuj jeszcze raz.';
  end if;

  insert into staff_accounts (member_id, restaurant_id, login, password_hash)
  values (p_member_id, v_member.restaurant_id, v_login, extensions.crypt(v_password, extensions.gen_salt('bf')));
  return jsonb_build_object('login', v_login, 'password', v_password);
end;
$$;

-- Nowe hasło, np. gdy pracownik zapomniał albo ktoś je podejrzał. Zdejmuje blokadę po nieudanych próbach.
-- Hasło wraca tylko w tej odpowiedzi.
create or replace function public.panel_reset_staff_password(p_member_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
  v_password    text := private.random_text('abcdefghjkmnpqrstuvwxyz23456789', 6);
begin
  select restaurant_id into v_restaurant from staff_accounts where member_id = p_member_id;
  if v_restaurant is null then
    raise exception 'Ten pracownik nie ma jeszcze loginu.';
  end if;
  perform private.require_permission(v_restaurant, 'staff');
  update staff_accounts
  set password_hash = extensions.crypt(v_password, extensions.gen_salt('bf')),
      failed_attempts = 0, locked_until = null, updated_at = now()
  where member_id = p_member_id;
  return v_password;
end;
$$;

-- ---------------------------------------------------------------
-- 2. Główne stanowisko
-- ---------------------------------------------------------------

create table public.main_stations (
  restaurant_id  uuid primary key references public.restaurants (id) on delete cascade,
  -- Identyfikator instalacji panelu na komputerze (losowy, zapisany w panelu).
  device_id      text not null check (char_length(device_id) between 8 and 80),
  device_name    text check (char_length(device_name) <= 80),
  set_by         uuid references auth.users (id) on delete set null,
  set_at         timestamptz not null default now()
);

alter table public.main_stations enable row level security;

create policy "Obsługa widzi główne stanowisko"
  on public.main_stations for select to authenticated
  using (private.has_staff_role(restaurant_id));

-- Włącza albo wyłącza główne stanowisko na tym komputerze. Jest tylko jedno: żeby je przenieść,
-- trzeba je najpierw wyłączyć na starym komputerze. p_force: właściciel przejmuje stanowisko,
-- gdy stary komputer nie działa (panel prosi wtedy o hasło konta restauracji).
create or replace function public.panel_set_main_station(
  p_restaurant_id  uuid,
  p_device         text,
  p_name           text,
  p_enable         boolean,
  p_force          boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row  main_stations%rowtype;
begin
  perform private.require_permission(p_restaurant_id, 'profile');
  if coalesce(char_length(p_device), 0) < 8 then
    raise exception 'Nie rozpoznano tego komputera. Uruchom panel ponownie.';
  end if;
  if p_force then
    perform private.require_staff(p_restaurant_id, 'manager');
  end if;

  select * into v_row from main_stations where restaurant_id = p_restaurant_id for update;

  if p_enable then
    if found and v_row.device_id <> p_device and not p_force then
      raise exception 'Główne stanowisko jest już ustawione na komputerze „%”. Wyłącz je tam, a potem włącz tutaj.',
        coalesce(v_row.device_name, 'bez nazwy');
    end if;
    insert into main_stations (restaurant_id, device_id, device_name, set_by)
    values (p_restaurant_id, p_device, left(nullif(btrim(p_name), ''), 80), auth.uid())
    on conflict (restaurant_id) do update
      set device_id = excluded.device_id, device_name = excluded.device_name,
          set_by = excluded.set_by, set_at = now();
  else
    if found and v_row.device_id <> p_device then
      raise exception 'Główne stanowisko wyłącza się na komputerze, na którym jest ustawione („%”).',
        coalesce(v_row.device_name, 'bez nazwy');
    end if;
    delete from main_stations where restaurant_id = p_restaurant_id;
  end if;
end;
$$;

-- Pracownicy logują się tylko na głównym stanowisku.
create or replace function private.check_station(p_restaurant_id uuid, p_device text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_device  text;
  v_name    text;
begin
  select device_id, device_name into v_device, v_name
  from public.main_stations where restaurant_id = p_restaurant_id;
  if v_device is null then
    raise exception 'Najpierw ustaw główne stanowisko w Ustawieniach panelu.';
  end if;
  if v_device is distinct from p_device then
    raise exception 'Pracownicy logują się tylko na głównym stanowisku („%”).', coalesce(v_name, 'bez nazwy');
  end if;
end;
$$;

revoke execute on function private.check_station(uuid, text) from public, anon;
grant execute on function private.check_station(uuid, text) to authenticated;

-- ---------------------------------------------------------------
-- 3. Logowanie na stanowisku
-- ---------------------------------------------------------------

-- Dane zalogowanego pracownika dla panelu: uprawnienia jego stanowiska i trwająca zmiana.
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
    'permissions', coalesce(to_jsonb(p.permissions), '[]'::jsonb),
    'shift_started_at', (select s.started_at from public.staff_shifts s where s.member_id = m.id and s.ended_at is null)
  )
  from public.staff_members m
  left join public.staff_positions p on p.id = m.position_id
  where m.id = p_member_id
$$;

revoke execute on function private.member_session(uuid) from public, anon;
grant execute on function private.member_session(uuid) to authenticated;

-- Kod QR tylko na głównym stanowisku.
drop function public.panel_new_login_token(uuid);
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
  perform private.check_station(p_restaurant_id, p_device);
  delete from panel_login_tokens
  where restaurant_id = p_restaurant_id and expires_at < now() - interval '1 hour';
  insert into panel_login_tokens (token, restaurant_id, created_by) values (v_token, p_restaurant_id, auth.uid());
  return v_token;
end;
$$;

create or replace function public.panel_login_token_status(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row  panel_login_tokens%rowtype;
begin
  select * into v_row from panel_login_tokens where token = p_token;
  if not found then
    return null;
  end if;
  perform private.require_staff(v_row.restaurant_id);
  if v_row.claimed_member_id is null then
    return jsonb_build_object('claimed', false, 'expired', v_row.expires_at < now());
  end if;
  return private.member_session(v_row.claimed_member_id);
end;
$$;

-- Logowanie loginem i hasłem na głównym stanowisku. Zaczyna zmianę, jeśli jeszcze nie trwa.
-- Błędne hasło nie rzuca wyjątku, tylko zwraca {error}, żeby licznik prób się zapisał.
-- Po 5 błędnych próbach login jest zablokowany na 5 minut.
create or replace function public.panel_member_login(
  p_restaurant_id  uuid,
  p_login          text,
  p_password       text,
  p_device         text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account  staff_accounts%rowtype;
  v_active   boolean;
begin
  perform private.require_staff(p_restaurant_id);
  perform private.check_station(p_restaurant_id, p_device);

  select * into v_account from staff_accounts
  where login = lower(btrim(coalesce(p_login, ''))) and restaurant_id = p_restaurant_id
  for update;
  if not found then
    return jsonb_build_object('error', 'Nieprawidłowy login lub hasło.');
  end if;
  if v_account.locked_until > now() then
    return jsonb_build_object('error', 'Za dużo nieudanych prób. Spróbuj ponownie za kilka minut.');
  end if;
  if v_account.password_hash is distinct from
     extensions.crypt(lower(btrim(coalesce(p_password, ''))), v_account.password_hash) then
    update staff_accounts
    set failed_attempts = case when failed_attempts >= 4 then 0 else failed_attempts + 1 end,
        locked_until = case when failed_attempts >= 4 then now() + interval '5 minutes' else locked_until end
    where member_id = v_account.member_id;
    return jsonb_build_object('error', 'Nieprawidłowy login lub hasło.');
  end if;

  select active into v_active from staff_members where id = v_account.member_id;
  if not coalesce(v_active, false) then
    return jsonb_build_object('error', 'To konto jest wyłączone. Porozmawiaj z kierownikiem.');
  end if;

  update staff_accounts set failed_attempts = 0, locked_until = null where member_id = v_account.member_id;
  insert into staff_shifts (restaurant_id, member_id, source)
  values (p_restaurant_id, v_account.member_id, 'station')
  on conflict do nothing;
  return private.member_session(v_account.member_id);
end;
$$;

-- Skan kodu w aplikacji: zaczyna zmianę i od razu loguje pracownika na stanowisku,
-- jeśli nikt jeszcze nie zalogował się tym kodem (panel zaraz pokazuje nowy kod).
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

-- ---------------------------------------------------------------
-- 4. Grafik: propozycje godzin
-- ---------------------------------------------------------------

create table public.staff_schedule (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  member_id      uuid not null references public.staff_members (id) on delete cascade,
  day            date not null,
  starts         time not null,
  ends           time not null,
  -- proposed: czeka na pracownika, accepted: przyjęte, changed: pracownik proponuje inne godziny
  status         text not null default 'proposed' check (status in ('proposed', 'accepted', 'changed')),
  change_starts  time,
  change_ends    time,
  note           text check (char_length(note) <= 200),
  reply          text check (char_length(reply) <= 200),
  created_by     uuid references auth.users (id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (member_id, day),
  check (ends > starts),
  check ((change_starts is null) = (change_ends is null)),
  check (change_starts is null or change_ends > change_starts)
);

create index staff_schedule_day_idx on public.staff_schedule (restaurant_id, day);
alter table public.staff_schedule enable row level security;

create policy "Obsługa widzi grafik lokalu"
  on public.staff_schedule for select to authenticated
  using (private.has_staff_role(restaurant_id));

create policy "Pracownik widzi swój grafik"
  on public.staff_schedule for select to authenticated
  using (member_id in (select id from private.my_members()));

alter publication supabase_realtime add table public.staff_schedule;

create or replace function private.require_schedule(p_restaurant_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (private.has_permission(p_restaurant_id, 'schedule') or private.has_permission(p_restaurant_id, 'staff')) then
    raise exception 'Grafik rozpisuje osoba z uprawnieniem „Grafik”.';
  end if;
end;
$$;

revoke execute on function private.require_schedule(uuid) from public, anon;
grant execute on function private.require_schedule(uuid) to authenticated;

-- Proponuje pracownikowi godziny w danym dniu (albo zmienia propozycję). Pracownik musi ją przyjąć.
create or replace function public.panel_plan_shift(
  p_member_id  uuid,
  p_day        date,
  p_starts     time,
  p_ends       time,
  p_note       text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
begin
  select restaurant_id into v_restaurant from staff_members where id = p_member_id;
  if v_restaurant is null then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  perform private.require_schedule(v_restaurant);
  if p_starts is null or p_ends is null or p_ends <= p_starts then
    raise exception 'Koniec musi być później niż początek.';
  end if;

  insert into staff_schedule (restaurant_id, member_id, day, starts, ends, note, created_by)
  values (v_restaurant, p_member_id, p_day, p_starts, p_ends, nullif(btrim(p_note), ''), auth.uid())
  on conflict (member_id, day) do update
    set starts = excluded.starts, ends = excluded.ends, note = excluded.note,
        status = 'proposed', change_starts = null, change_ends = null, reply = null,
        created_by = excluded.created_by, updated_at = now();
end;
$$;

-- Przyjmuje godziny zaproponowane przez pracownika.
create or replace function public.panel_accept_shift_change(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row  staff_schedule%rowtype;
begin
  select * into v_row from staff_schedule where id = p_id;
  if not found then
    raise exception 'Nie znaleziono wpisu w grafiku.';
  end if;
  perform private.require_schedule(v_row.restaurant_id);
  if v_row.status <> 'changed' then
    raise exception 'Pracownik nie proponował innych godzin.';
  end if;
  update staff_schedule
  set starts = change_starts, ends = change_ends, change_starts = null, change_ends = null,
      status = 'accepted', updated_at = now()
  where id = p_id;
end;
$$;

create or replace function public.panel_delete_planned_shift(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
begin
  select restaurant_id into v_restaurant from staff_schedule where id = p_id;
  if v_restaurant is null then
    return;
  end if;
  perform private.require_schedule(v_restaurant);
  delete from staff_schedule where id = p_id;
end;
$$;

-- Aplikacja Table for employees: mój grafik.
create or replace function public.staff_my_schedule(p_from date, p_to date)
returns table (id uuid, restaurant_name text, day date, starts time, ends time, status text,
               change_starts time, change_ends time, note text, reply text)
language sql
stable
security definer
set search_path = public
as $$
  select s.id, r.name, s.day, s.starts, s.ends, s.status, s.change_starts, s.change_ends, s.note, s.reply
  from staff_schedule s
  join restaurants r on r.id = s.restaurant_id
  where s.member_id in (select id from private.my_members())
    and s.day between p_from and least(p_to, p_from + 62)
  order by s.day, s.starts
$$;

-- Pracownik przyjmuje propozycję albo proponuje inne godziny w tym dniu.
create or replace function public.staff_answer_shift(
  p_id      uuid,
  p_accept  boolean,
  p_starts  time default null,
  p_ends    time default null,
  p_reply   text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row  staff_schedule%rowtype;
begin
  select * into v_row from staff_schedule where id = p_id;
  if not found or not exists (select 1 from private.my_members() m where m.id = v_row.member_id) then
    raise exception 'Nie znaleziono tej zmiany w Twoim grafiku.';
  end if;
  if v_row.day < current_date then
    raise exception 'Ten dzień już minął.';
  end if;

  if p_accept then
    update staff_schedule
    set status = 'accepted', change_starts = null, change_ends = null,
        reply = nullif(btrim(p_reply), ''), updated_at = now()
    where id = p_id;
  else
    if p_starts is null or p_ends is null or p_ends <= p_starts then
      raise exception 'Koniec musi być później niż początek.';
    end if;
    update staff_schedule
    set status = 'changed', change_starts = p_starts, change_ends = p_ends,
        reply = nullif(btrim(p_reply), ''), updated_at = now()
    where id = p_id;
  end if;
end;
$$;

-- ---------------------------------------------------------------
-- 5. Statystyki pracownika
-- ---------------------------------------------------------------

create or replace function public.panel_member_stats(p_member_id uuid, p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_member  staff_members%rowtype;
  v_start   timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 366)));
  v_week    timestamptz := date_trunc('week', now());
begin
  select * into v_member from staff_members where id = p_member_id;
  if not found then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  if not private.has_permission(v_member.restaurant_id, 'staff') then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;

  return (
    with shifts as (
      select greatest(started_at, v_start) as s, coalesce(ended_at, now()) as e
      from staff_shifts
      where member_id = p_member_id and coalesce(ended_at, now()) > v_start
    ),
    closed as (
      select (select coalesce(sum(i.unit_price_grosze * i.quantity), 0)
              from order_items i where i.order_id = o.id and i.status <> 'cancelled') as total
      from orders o
      where o.closed_by_member = p_member_id and o.status = 'paid' and o.closed_at >= v_start
    ),
    items as (
      select name, quantity from order_items
      where created_by_member = p_member_id and status <> 'cancelled' and created_at >= v_start
    )
    select jsonb_build_object(
      'seconds', (select coalesce(sum(extract(epoch from e - s)), 0) from shifts)::bigint,
      'shifts', (select count(*) from shifts),
      'week_seconds', (
        select coalesce(sum(extract(epoch from coalesce(ended_at, now()) - greatest(started_at, v_week))), 0)
        from staff_shifts where member_id = p_member_id and coalesce(ended_at, now()) > v_week
      )::bigint,
      'open_since', (select started_at from staff_shifts where member_id = p_member_id and ended_at is null),
      'last_shift', (select max(started_at) from staff_shifts where member_id = p_member_id),
      'orders_opened', (select count(*) from orders where opened_by_member = p_member_id and opened_at >= v_start),
      'orders_closed', (select count(*) from closed),
      'revenue', (select coalesce(sum(total), 0) from closed)::bigint,
      'items', (select coalesce(sum(quantity), 0) from items)::bigint,
      'top_items', (
        select coalesce(jsonb_agg(t), '[]'::jsonb)
        from (
          select name, sum(quantity)::integer as quantity
          from items group by name order by sum(quantity) desc, name limit 5
        ) t
      ),
      'planned', (select count(*) from staff_schedule where member_id = p_member_id and day >= current_date)
    )
  );
end;
$$;

-- ---------------------------------------------------------------
-- Uprawnienia do funkcji
-- ---------------------------------------------------------------

revoke execute on function public.panel_create_staff_login(uuid) from public, anon;
revoke execute on function public.panel_reset_staff_password(uuid) from public, anon;
revoke execute on function public.panel_set_main_station(uuid, text, text, boolean, boolean) from public, anon;
revoke execute on function public.panel_new_login_token(uuid, text) from public, anon;
revoke execute on function public.panel_member_login(uuid, text, text, text) from public, anon;
revoke execute on function public.panel_plan_shift(uuid, date, time, time, text) from public, anon;
revoke execute on function public.panel_accept_shift_change(uuid) from public, anon;
revoke execute on function public.panel_delete_planned_shift(uuid) from public, anon;
revoke execute on function public.staff_my_schedule(date, date) from public, anon;
revoke execute on function public.staff_answer_shift(uuid, boolean, time, time, text) from public, anon;
revoke execute on function public.panel_member_stats(uuid, integer) from public, anon;

grant execute on function public.panel_create_staff_login(uuid) to authenticated;
grant execute on function public.panel_reset_staff_password(uuid) to authenticated;
grant execute on function public.panel_set_main_station(uuid, text, text, boolean, boolean) to authenticated;
grant execute on function public.panel_new_login_token(uuid, text) to authenticated;
grant execute on function public.panel_member_login(uuid, text, text, text) to authenticated;
grant execute on function public.panel_plan_shift(uuid, date, time, time, text) to authenticated;
grant execute on function public.panel_accept_shift_change(uuid) to authenticated;
grant execute on function public.panel_delete_planned_shift(uuid) to authenticated;
grant execute on function public.staff_my_schedule(date, date) to authenticated;
grant execute on function public.staff_answer_shift(uuid, boolean, time, time, text) to authenticated;
grant execute on function public.panel_member_stats(uuid, integer) to authenticated;
