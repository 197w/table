-- Table · migracja 0030
-- 1. Hasła pracowników są stale widoczne dla osoby z uprawnieniem „Loginy i hasła” i dla samego pracownika
--    (prośba użytkownika). Hasło leży zaszyfrowane w Supabase Vault, do logowania nadal służy skrót bcrypt.
--    Nowe hasła są łatwe do zapamiętania: proste słowo i dwie cyfry, np. „kawa47”. Można też wpisać własne.
-- 2. Grafik od strony pracownika: pracownik zgłasza, od której do której może pracować w danym dniu,
--    przełożony z uprawnieniem „Grafik” przyjmuje (także ze zmienionymi godzinami) albo odrzuca.
--    Po decyzji pracownik nie może już zmienić tego dnia.
-- 3. Szczegółowe uprawnienia. Istniejące stanowiska dostają odpowiedniki, żeby nic im nie zniknęło.

-- ---------------------------------------------------------------
-- 1. Widoczne hasła
-- ---------------------------------------------------------------

alter table public.staff_accounts add column password_secret uuid;

-- Proste słowo bez polskich znaków i dwie cyfry, np. „kawa47”.
create or replace function private.easy_password()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_words  text[] := array[
    'kawa', 'lampa', 'zupa', 'mleko', 'ryba', 'sowa', 'lato', 'zima', 'woda', 'pies',
    'kura', 'koza', 'lody', 'mapa', 'nuta', 'rower', 'okno', 'tort', 'pizza', 'banan',
    'malina', 'kiwi', 'arbuz', 'melon', 'sernik', 'kotlet', 'pierogi', 'makaron', 'chleb', 'miska',
    'garnek', 'talerz', 'kubek', 'cukier', 'pieprz', 'kakao', 'herbata', 'burak', 'cebula', 'marchew',
    'kapusta', 'pomidor', 'papryka', 'oliwka', 'grzyb', 'jajko', 'rogal', 'bajka', 'gwiazda', 'morze',
    'rzeka', 'park', 'most', 'zamek', 'konik', 'lisek', 'zebra', 'tygrys', 'panda', 'delfin',
    'orzech', 'figa', 'jagoda', 'imbir', 'mango', 'kokos', 'wafel', 'pianka', 'budyn', 'kisiel'];
  v_raw    bytea := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
begin
  return v_words[1 + ((get_byte(v_raw, 0) * 256 + get_byte(v_raw, 1)) % array_length(v_words, 1))]
      || lpad(((get_byte(v_raw, 2) * 256 + get_byte(v_raw, 3)) % 100)::text, 2, '0');
end;
$$;

-- Zapisuje hasło: skrót do logowania i zaszyfrowaną kopię do podglądu.
create or replace function private.store_staff_password(p_member_id uuid, p_password text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret  uuid;
begin
  select password_secret into v_secret from public.staff_accounts where member_id = p_member_id;
  if v_secret is null then
    v_secret := vault.create_secret(p_password, null, 'Hasło pracownika do głównego stanowiska Table');
  else
    perform vault.update_secret(v_secret, p_password);
  end if;
  update public.staff_accounts
  set password_hash = extensions.crypt(p_password, extensions.gen_salt('bf')),
      password_secret = v_secret,
      failed_attempts = 0,
      locked_until = null,
      updated_at = now()
  where member_id = p_member_id;
end;
$$;

-- Hasło do wpisania: małe litery i cyfry, 4–20 znaków. Null: wylosowane łatwe hasło.
create or replace function private.clean_staff_password(p_password text)
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v  text := lower(btrim(coalesce(p_password, '')));
begin
  if v = '' then
    return private.easy_password();
  end if;
  if v !~ '^[a-z0-9]{4,20}$' then
    raise exception 'Hasło: od 4 do 20 znaków, same litery bez polskich znaków i cyfry.';
  end if;
  return v;
end;
$$;

-- Usunięcie loginu usuwa też zaszyfrowaną kopię hasła.
create or replace function private.drop_staff_password()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.password_secret is not null then
    -- Brak uprawnień do Vault nie może blokować usunięcia pracownika.
    begin
      delete from vault.secrets where id = old.password_secret;
    exception when insufficient_privilege then
      null;
    end;
  end if;
  return old;
end;
$$;

create trigger staff_accounts_drop_password
after delete on public.staff_accounts
for each row execute function private.drop_staff_password();

revoke execute on function private.easy_password() from public, anon;
revoke execute on function private.store_staff_password(uuid, text) from public, anon;
revoke execute on function private.clean_staff_password(text) from public, anon;
-- Wołają je tylko funkcje bazy (security definer), więc zalogowani użytkownicy ich nie dostają.
revoke execute on function private.easy_password() from authenticated;
revoke execute on function private.store_staff_password(uuid, text) from authenticated;
revoke execute on function private.clean_staff_password(text) from authenticated;

-- Login i hasło dla pracownika. [p_password] puste: łatwe hasło wylosowane przez bazę.
drop function public.panel_create_staff_login(uuid);
create or replace function public.panel_create_staff_login(p_member_id uuid, p_password text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member    staff_members%rowtype;
  v_base      text;
  v_login     text;
  v_password  text := private.clean_staff_password(p_password);
begin
  select * into v_member from staff_members where id = p_member_id;
  if not found then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  if not (private.has_permission(v_member.restaurant_id, 'staff')
          or private.has_permission(v_member.restaurant_id, 'staff_logins')) then
    raise exception 'Nie masz uprawnień do loginów pracowników.';
  end if;
  if exists (select 1 from staff_accounts where member_id = p_member_id) then
    raise exception 'Ten pracownik ma już login. Możesz mu zmienić hasło.';
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
  perform private.store_staff_password(p_member_id, v_password);
  return jsonb_build_object('login', v_login, 'password', v_password);
end;
$$;

-- Nowe hasło (wpisane albo wylosowane). Stare przestaje działać, blokada po błędach znika.
drop function public.panel_reset_staff_password(uuid);
create or replace function public.panel_set_staff_password(p_member_id uuid, p_password text default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
  v_password    text := private.clean_staff_password(p_password);
begin
  select restaurant_id into v_restaurant from staff_accounts where member_id = p_member_id;
  if v_restaurant is null then
    raise exception 'Ten pracownik nie ma jeszcze loginu.';
  end if;
  perform private.require_permission(v_restaurant, 'staff_logins');
  perform private.store_staff_password(p_member_id, v_password);
  return v_password;
end;
$$;

-- Loginy i hasła pracowników lokalu dla osoby z uprawnieniem „Loginy i hasła”.
-- Hasło null: login założony przed tą zmianą, trzeba nadać nowe, żeby było widać.
create or replace function public.panel_staff_logins(p_restaurant_id uuid)
returns table (member_id uuid, login text, password text, locked_until timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform private.require_permission(p_restaurant_id, 'staff_logins');
  return query
    select a.member_id, a.login, s.decrypted_secret::text, a.locked_until
    from staff_accounts a
    left join vault.decrypted_secrets s on s.id = a.password_secret
    where a.restaurant_id = p_restaurant_id;
end;
$$;

-- Aplikacja Table for employees: mój login i hasło do głównego stanowiska.
create or replace function public.staff_my_logins()
returns table (member_id uuid, login text, password text)
language sql
stable
security definer
set search_path = public
as $$
  select a.member_id, a.login, s.decrypted_secret::text
  from staff_accounts a
  left join vault.decrypted_secrets s on s.id = a.password_secret
  where a.member_id in (select id from private.my_members())
$$;

-- ---------------------------------------------------------------
-- 2. Grafik: pracownik zgłasza godziny, przełożony decyduje
-- ---------------------------------------------------------------

-- Tabela z 0029 była pusta (propozycje od przełożonego), więc budujemy ją od nowa.
drop function public.panel_plan_shift(uuid, date, time, time, text);
drop function public.panel_accept_shift_change(uuid);
drop function public.panel_delete_planned_shift(uuid);
drop function public.staff_my_schedule(date, date);
drop function public.staff_answer_shift(uuid, boolean, time, time, text);
drop function public.panel_member_stats(uuid, integer);
drop table public.staff_schedule;

create table public.staff_schedule (
  id                uuid primary key default gen_random_uuid(),
  restaurant_id     uuid not null references public.restaurants (id) on delete cascade,
  member_id         uuid not null references public.staff_members (id) on delete cascade,
  day               date not null,
  -- Godziny w grafiku: zgłoszone, a po przyjęciu te zatwierdzone (mogą być zmienione przez przełożonego).
  starts            time not null,
  ends              time not null,
  -- Co zgłosił pracownik. Null: godziny wpisał przełożony.
  requested_starts  time,
  requested_ends    time,
  -- pending: czeka na przełożonego, accepted: przyjęte, rejected: odrzucone
  status            text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
  note              text check (char_length(note) <= 200),
  answer            text check (char_length(answer) <= 200),
  decided_by        uuid references auth.users (id) on delete set null,
  decided_at        timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (member_id, day),
  check (ends > starts),
  check (requested_starts is null or requested_ends > requested_starts)
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

-- Pracownik zgłasza godziny w danym dniu albo poprawia zgłoszenie, dopóki przełożony nie zdecydował.
create or replace function public.staff_submit_hours(
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
  v_member  staff_members%rowtype;
  v_status  text;
begin
  select * into v_member from private.my_members() m where m.id = p_member_id;
  if not found then
    raise exception 'Nie ma Cię na liście pracowników tego lokalu.';
  end if;
  if p_day is null or p_day < current_date then
    raise exception 'Godziny można zgłaszać od dziś.';
  end if;
  if p_day > current_date + 90 then
    raise exception 'Godziny można zgłaszać najwyżej 90 dni do przodu.';
  end if;
  if p_starts is null or p_ends is null or p_ends <= p_starts then
    raise exception 'Koniec musi być później niż początek.';
  end if;

  select status into v_status from staff_schedule where member_id = p_member_id and day = p_day;
  if v_status is not null and v_status <> 'pending' then
    raise exception 'Przełożony już zdecydował o tym dniu. Tych godzin nie można już zmienić.';
  end if;

  insert into staff_schedule (restaurant_id, member_id, day, starts, ends, requested_starts, requested_ends, note)
  values (v_member.restaurant_id, p_member_id, p_day, p_starts, p_ends, p_starts, p_ends, nullif(btrim(p_note), ''))
  on conflict (member_id, day) do update
    set starts = excluded.starts, ends = excluded.ends,
        requested_starts = excluded.requested_starts, requested_ends = excluded.requested_ends,
        note = excluded.note, updated_at = now();
end;
$$;

-- Pracownik wycofuje zgłoszenie, dopóki przełożony nie zdecydował.
create or replace function public.staff_delete_hours(p_id uuid)
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
    raise exception 'Nie znaleziono tego zgłoszenia.';
  end if;
  if v_row.status <> 'pending' then
    raise exception 'Przełożony już zdecydował o tym dniu. Tych godzin nie można już zmienić.';
  end if;
  delete from staff_schedule where id = p_id;
end;
$$;

-- Mój grafik w aplikacji: zgłoszenia i decyzje.
create or replace function public.staff_my_schedule(p_from date, p_to date)
returns table (id uuid, member_id uuid, restaurant_name text, day date, starts time, ends time,
               requested_starts time, requested_ends time, status text, note text, answer text)
language sql
stable
security definer
set search_path = public
as $$
  select s.id, s.member_id, r.name, s.day, s.starts, s.ends, s.requested_starts, s.requested_ends,
         s.status, s.note, s.answer
  from staff_schedule s
  join restaurants r on r.id = s.restaurant_id
  where s.member_id in (select id from private.my_members())
    and s.day between p_from and least(p_to, p_from + 92)
  order by s.day
$$;

-- Przełożony przyjmuje zgłoszenie (z godzinami pracownika albo zmienionymi) albo je odrzuca.
create or replace function public.panel_decide_hours(
  p_id      uuid,
  p_accept  boolean,
  p_starts  time default null,
  p_ends    time default null,
  p_answer  text default null
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
  if not found then
    raise exception 'Nie znaleziono wpisu w grafiku.';
  end if;
  perform private.require_schedule(v_row.restaurant_id);

  if p_accept then
    if coalesce(p_ends, v_row.ends) <= coalesce(p_starts, v_row.starts) then
      raise exception 'Koniec musi być później niż początek.';
    end if;
    update staff_schedule
    set status = 'accepted', starts = coalesce(p_starts, starts), ends = coalesce(p_ends, ends),
        answer = nullif(btrim(p_answer), ''), decided_by = auth.uid(), decided_at = now(), updated_at = now()
    where id = p_id;
  else
    update staff_schedule
    set status = 'rejected', answer = nullif(btrim(p_answer), ''),
        decided_by = auth.uid(), decided_at = now(), updated_at = now()
    where id = p_id;
  end if;
end;
$$;

-- Przełożony wpisuje godziny sam (np. pracownik bez aplikacji). Wpis jest od razu przyjęty.
create or replace function public.panel_add_hours(
  p_member_id  uuid,
  p_day        date,
  p_starts     time,
  p_ends       time,
  p_answer     text default null
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
  insert into staff_schedule (restaurant_id, member_id, day, starts, ends, status, answer, decided_by, decided_at)
  values (v_restaurant, p_member_id, p_day, p_starts, p_ends, 'accepted', nullif(btrim(p_answer), ''), auth.uid(), now())
  on conflict (member_id, day) do update
    set starts = excluded.starts, ends = excluded.ends, status = 'accepted', answer = excluded.answer,
        decided_by = excluded.decided_by, decided_at = now(), updated_at = now();
end;
$$;

create or replace function public.panel_delete_hours(p_id uuid)
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

-- Statystyki pracownika (jak w 0029, „planned” to przyjęte godziny od dziś).
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
      'planned', (select count(*) from staff_schedule
                  where member_id = p_member_id and day >= current_date and status = 'accepted')
    )
  );
end;
$$;

-- ---------------------------------------------------------------
-- 3. Szczegółowe uprawnienia
-- ---------------------------------------------------------------

create or replace function public.panel_my_permissions(p_restaurant_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when private.has_staff_role(p_restaurant_id, 'manager') then
      array['reservations', 'floor', 'floor_edit', 'orders', 'orders_close', 'orders_cancel', 'deliveries',
            'kitchen', 'kitchen_settings', 'staff', 'staff_logins', 'schedule', 'timesheet', 'positions',
            'profile', 'menu', 'gift_cards', 'settings', 'reviews', 'stats']
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

-- Istniejące stanowiska zachowują to, co mogły wcześniej.
update public.staff_positions set permissions = array(
  select distinct unnest(permissions || case when 'orders' = any (permissions) then array['orders_close'] else '{}' end
                                      || case when 'kitchen' = any (permissions) then array['kitchen_settings'] else '{}' end
                                      || case when 'staff' = any (permissions)
                                              then array['staff_logins', 'schedule', 'timesheet'] else '{}' end
                                      || case when 'profile' = any (permissions) then array['settings'] else '{}' end)
);

-- ---------------------------------------------------------------
-- Uprawnienia do funkcji
-- ---------------------------------------------------------------

revoke execute on function public.panel_create_staff_login(uuid, text) from public, anon;
revoke execute on function public.panel_set_staff_password(uuid, text) from public, anon;
revoke execute on function public.panel_staff_logins(uuid) from public, anon;
revoke execute on function public.staff_my_logins() from public, anon;
revoke execute on function public.staff_submit_hours(uuid, date, time, time, text) from public, anon;
revoke execute on function public.staff_delete_hours(uuid) from public, anon;
revoke execute on function public.staff_my_schedule(date, date) from public, anon;
revoke execute on function public.panel_decide_hours(uuid, boolean, time, time, text) from public, anon;
revoke execute on function public.panel_add_hours(uuid, date, time, time, text) from public, anon;
revoke execute on function public.panel_delete_hours(uuid) from public, anon;
revoke execute on function public.panel_member_stats(uuid, integer) from public, anon;

grant execute on function public.panel_create_staff_login(uuid, text) to authenticated;
grant execute on function public.panel_set_staff_password(uuid, text) to authenticated;
grant execute on function public.panel_staff_logins(uuid) to authenticated;
grant execute on function public.staff_my_logins() to authenticated;
grant execute on function public.staff_submit_hours(uuid, date, time, time, text) to authenticated;
grant execute on function public.staff_delete_hours(uuid) to authenticated;
grant execute on function public.staff_my_schedule(date, date) to authenticated;
grant execute on function public.panel_decide_hours(uuid, boolean, time, time, text) to authenticated;
grant execute on function public.panel_add_hours(uuid, date, time, time, text) to authenticated;
grant execute on function public.panel_delete_hours(uuid) to authenticated;
grant execute on function public.panel_member_stats(uuid, integer) to authenticated;
