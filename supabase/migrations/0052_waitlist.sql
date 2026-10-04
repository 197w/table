-- Lista oczekujących: gość zapisuje się, gdy nie ma wolnego stolika (dzień, liczba osób, przedział godzin).
-- Lokal widzi listę w Rezerwacjach i proponuje godzinę; gość widzi propozycję w aplikacji i rezerwuje.
-- Rezerwacja gościa w tym lokalu tego dnia zamyka jego wpis.

create table public.waitlist_entries (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  user_id        uuid not null references auth.users (id) on delete cascade,
  day            date not null,
  party_size     smallint not null check (party_size between 1 and 30),
  time_from      time not null,
  time_to        time not null,
  note           text check (note is null or char_length(note) <= 300),
  status         text not null default 'waiting' check (status in ('waiting', 'offered', 'booked', 'cancelled')),
  offered_time   time,
  offered_note   text check (offered_note is null or char_length(offered_note) <= 300),
  offered_at     timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (time_to > time_from)
);
create index waitlist_restaurant_day_idx on public.waitlist_entries (restaurant_id, day);
create index waitlist_user_idx on public.waitlist_entries (user_id, day);
alter table public.waitlist_entries enable row level security;
create policy waitlist_own_read on public.waitlist_entries
  for select to authenticated using (user_id = auth.uid());
create policy waitlist_staff_read on public.waitlist_entries
  for select to authenticated using (private.has_permission(restaurant_id, 'reservations'));

create or replace function public.guest_join_waitlist(
  p_restaurant_id  uuid,
  p_day            date,
  p_party_size     integer,
  p_from           time,
  p_to             time,
  p_note           text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_rest  restaurants%rowtype;
  v_id    uuid;
  v_today date;
begin
  if v_uid is null then
    raise exception 'Zaloguj się, żeby zapisać się na listę oczekujących.';
  end if;
  select * into v_rest from restaurants where id = p_restaurant_id;
  if not found or v_rest.plan <> 'pro' then
    raise exception 'Ten lokal nie prowadzi listy oczekujących w aplikacji.';
  end if;
  v_today := (now() at time zone coalesce(v_rest.timezone, 'Europe/Warsaw'))::date;
  if p_day < v_today or p_day > v_today + 60 then
    raise exception 'Wybierz dzień od dziś do 60 dni naprzód.';
  end if;
  if p_party_size is null or p_party_size not between 1 and v_rest.max_party_size then
    raise exception 'Lista oczekujących obejmuje od 1 do % osób.', v_rest.max_party_size;
  end if;
  if p_from is null or p_to is null or p_to <= p_from then
    raise exception 'Wybierz przedział godzin.';
  end if;
  if exists (
    select 1 from waitlist_entries
    where user_id = v_uid and restaurant_id = p_restaurant_id and day = p_day and status in ('waiting', 'offered')
  ) then
    raise exception 'Jesteś już na liście oczekujących w tym lokalu na ten dzień.';
  end if;
  if (select count(*) from waitlist_entries where user_id = v_uid and status in ('waiting', 'offered') and day >= v_today) >= 3 then
    raise exception 'Możesz czekać najwyżej w 3 miejscach naraz.';
  end if;
  insert into waitlist_entries (restaurant_id, user_id, day, party_size, time_from, time_to, note)
  values (p_restaurant_id, v_uid, p_day, p_party_size, p_from, p_to, nullif(btrim(p_note), ''))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.guest_leave_waitlist(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update waitlist_entries set status = 'cancelled', updated_at = now()
  where id = p_id and user_id = auth.uid() and status in ('waiting', 'offered');
  if not found then
    raise exception 'Nie znaleziono wpisu na liście oczekujących.';
  end if;
end;
$$;

-- Moje wpisy z nazwą lokalu (aplikacja Table).
create or replace function public.guest_my_waitlist()
returns table (
  id uuid, restaurant_id uuid, restaurant_name text, day date, party_size smallint, time_from time, time_to time,
  status text, offered_time time, offered_note text
)
language sql
stable
security definer
set search_path = public
as $$
  select w.id, w.restaurant_id, r.name, w.day, w.party_size, w.time_from, w.time_to, w.status, w.offered_time, w.offered_note
  from waitlist_entries w
  join restaurants r on r.id = w.restaurant_id
  where w.user_id = auth.uid()
    and w.status in ('waiting', 'offered')
    and w.day >= (now() at time zone coalesce(r.timezone, 'Europe/Warsaw'))::date
  order by w.day, w.time_from
$$;

-- Lista oczekujących lokalu na dzień, z imieniem i telefonem gościa.
create or replace function public.panel_waitlist(p_restaurant_id uuid, p_day date)
returns table (
  id uuid, party_size smallint, time_from time, time_to time, note text, status text,
  offered_time time, offered_at timestamptz, created_at timestamptz, guest_name text, guest_phone text, guest_visits integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform private.require_permission(p_restaurant_id, 'reservations');
  return query
  select w.id, w.party_size, w.time_from, w.time_to, w.note, w.status, w.offered_time, w.offered_at, w.created_at,
         coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.first_name), ''), 'Gość'),
         case when u.phone is not null and u.phone <> '' then '+' || u.phone end,
         (select count(*)::integer from reservations r
          where r.user_id = w.user_id and r.restaurant_id = w.restaurant_id and r.status in ('seated', 'completed'))
  from waitlist_entries w
  left join profiles p on p.id = w.user_id
  left join auth.users u on u.id = w.user_id
  where w.restaurant_id = p_restaurant_id and w.day = p_day and w.status in ('waiting', 'offered')
  order by w.created_at;
end;
$$;

-- Lokal proponuje gościowi godzinę (gość widzi ją w aplikacji i rezerwuje) albo usuwa go z listy.
create or replace function public.panel_offer_waitlist(p_id uuid, p_time time, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry waitlist_entries%rowtype;
begin
  select * into v_entry from waitlist_entries where id = p_id;
  if not found then
    raise exception 'Nie znaleziono wpisu.';
  end if;
  perform private.require_permission(v_entry.restaurant_id, 'reservations');
  if v_entry.status not in ('waiting', 'offered') then
    raise exception 'Ten gość nie czeka już na stolik.';
  end if;
  update waitlist_entries
  set status = 'offered', offered_time = p_time, offered_note = nullif(btrim(p_note), ''), offered_at = now(), updated_at = now()
  where id = p_id;
end;
$$;

create or replace function public.panel_remove_waitlist(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry waitlist_entries%rowtype;
begin
  select * into v_entry from waitlist_entries where id = p_id;
  if not found then
    raise exception 'Nie znaleziono wpisu.';
  end if;
  perform private.require_permission(v_entry.restaurant_id, 'reservations');
  update waitlist_entries set status = 'cancelled', updated_at = now() where id = p_id;
end;
$$;

-- Rezerwacja gościa w lokalu na ten dzień zamyka jego wpis na liście oczekujących.
create or replace function private.waitlist_booked()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tz text;
begin
  if new.user_id is null or new.status <> 'confirmed' then
    return new;
  end if;
  select coalesce(timezone, 'Europe/Warsaw') into v_tz from public.restaurants where id = new.restaurant_id;
  update public.waitlist_entries
  set status = 'booked', updated_at = now()
  where user_id = new.user_id and restaurant_id = new.restaurant_id
    and day = (new.starts_at at time zone v_tz)::date and status in ('waiting', 'offered');
  return new;
end;
$$;
create trigger reservations_waitlist_booked
  after insert on public.reservations
  for each row execute function private.waitlist_booked();

revoke execute on function public.guest_join_waitlist(uuid, date, integer, time, time, text) from public, anon;
revoke execute on function public.guest_leave_waitlist(uuid) from public, anon;
revoke execute on function public.guest_my_waitlist() from public, anon;
revoke execute on function public.panel_waitlist(uuid, date) from public, anon;
revoke execute on function public.panel_offer_waitlist(uuid, time, text) from public, anon;
revoke execute on function public.panel_remove_waitlist(uuid) from public, anon;
revoke execute on function private.waitlist_booked() from public, anon;
grant execute on function public.guest_join_waitlist(uuid, date, integer, time, time, text) to authenticated;
grant execute on function public.guest_leave_waitlist(uuid) to authenticated;
grant execute on function public.guest_my_waitlist() to authenticated;
grant execute on function public.panel_waitlist(uuid, date) to authenticated;
grant execute on function public.panel_offer_waitlist(uuid, time, text) to authenticated;
grant execute on function public.panel_remove_waitlist(uuid) to authenticated;
