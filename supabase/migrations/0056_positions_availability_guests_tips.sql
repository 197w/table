-- Table · migracja 0056
-- 1. Kilka stanowisk na pracownika (uprawnienia z wszystkich), stanowisko na dany dzień w grafiku.
-- 2. Grafik: status „Niedostępny” (pracownik nie może pracować albo nie zgłosił dyspozycyjności), propozycje zmian
--    od przełożonego (pracownik przyjmuje albo odrzuca w aplikacji), termin zgłaszania dyspozycyjności,
--    uwaga pracownika na tydzień.
-- 3. Liczba gości przy rachunku stolika (pominięcie liczy się w statystykach).
-- 4. Statystyki zespołu: od wybranej chwili (np. dziś), napiwki gotówką i kartą, goście i pominięcia, podsumowanie.

-- ---------------------------------------------------------------
-- 1. Kilka stanowisk
-- ---------------------------------------------------------------

create table public.staff_member_positions (
  member_id      uuid not null references public.staff_members (id) on delete cascade,
  position_id    uuid not null references public.staff_positions (id) on delete cascade,
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  primary key (member_id, position_id)
);
alter table public.staff_member_positions enable row level security;
create policy staff_member_positions_read on public.staff_member_positions
  for select to authenticated using (private.has_staff_role(restaurant_id));

-- Stanowiska pracownika: główne (staff_members.position_id) i dodatkowe.
create or replace function private.member_position_ids(p_member_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.position_id from public.staff_members m where m.id = p_member_id and m.position_id is not null
  union
  select x.position_id from public.staff_member_positions x where x.member_id = p_member_id
$$;

-- Uprawnienia pracownika: suma uprawnień wszystkich jego stanowisk.
create or replace function private.member_permissions(p_member_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct perm), '{}')
  from private.member_position_ids(p_member_id) as t(pid)
  cross join lateral unnest(coalesce(private.position_permissions(t.pid), '{}')) as u(perm)
$$;

-- Dostawca: któreś stanowisko (poza „ALL”) ma wprost uprawnienie „Dostawy”.
create or replace function private.is_courier(p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.member_position_ids(p_member_id) as t(pid)
    join public.staff_positions p on p.id = t.pid
    where p.system_key is distinct from 'all' and 'deliveries' = any (p.permissions)
  )
$$;

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
        where m.restaurant_id = p_restaurant_id
          and m.user_id = (select auth.uid())
          and m.active
          and p_permission = any (private.member_permissions(m.id))
      )
    )
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
    'permissions', to_jsonb(private.member_permissions(m.id)),
    'shift_started_at', (select s.started_at from public.staff_shifts s where s.member_id = m.id and s.ended_at is null)
  )
  from public.staff_members m
  left join public.staff_positions p on p.id = m.position_id
  where m.id = p_member_id
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
      select private.member_permissions(m.id)
      from public.staff_members m
      where m.restaurant_id = p_restaurant_id
        and m.user_id = (select auth.uid())
        and m.active
      limit 1
    ), '{}')
  end
$$;

create or replace function public.staff_my_jobs()
returns table (member_id uuid, restaurant_id uuid, restaurant_name text, member_name text,
               position_name text, permissions text[], shift_id uuid, shift_started_at timestamptz,
               week_seconds bigint, schedule_period text)
language sql
stable
security definer
set search_path = public
as $$
  select m.id, r.id, r.name, m.name, p.name, private.member_permissions(m.id),
         s.id, s.started_at,
         (select coalesce(sum(extract(epoch from coalesce(x.ended_at, now()) - x.started_at)), 0)::bigint
          from staff_shifts x
          where x.member_id = m.id and x.started_at >= date_trunc('week', now())),
         r.schedule_period
  from private.my_members() m
  join restaurants r on r.id = m.restaurant_id
  left join staff_positions p on p.id = m.position_id
  left join staff_shifts s on s.member_id = m.id and s.ended_at is null
  order by r.name
$$;

create or replace function private.courier_queue(p_restaurant_id uuid)
returns table (member_id uuid, name text, waiting_since timestamptz, busy boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select m.id,
         m.name,
         greatest(s.started_at, coalesce(m.courier_ready_at, s.started_at)),
         exists (
           select 1 from public.orders o
           where o.courier_member = m.id and o.fulfillment in ('accepted', 'ready', 'on_the_way')
         )
  from public.staff_members m
  join public.staff_shifts s on s.member_id = m.id and s.ended_at is null
  where m.restaurant_id = p_restaurant_id
    and m.active
    and private.is_courier(m.id)
  order by 4, 3, s.started_at
$$;

create or replace function public.staff_deliveries(p_member_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_member  staff_members%rowtype;
  v_r       restaurants%rowtype;
  v_since   timestamptz;
begin
  v_member := private.my_member(p_member_id);
  select * into v_r from restaurants where id = v_member.restaurant_id;
  v_since := date_trunc('day', now() at time zone v_r.timezone) at time zone v_r.timezone;
  return jsonb_build_object(
    'restaurant_name', v_r.name,
    'restaurant_address', v_r.address || ', ' || v_r.city,
    'on_shift', exists (select 1 from staff_shifts where member_id = p_member_id and ended_at is null),
    'is_courier', private.is_courier(p_member_id),
    'queue', coalesce((
      select jsonb_agg(jsonb_build_object('member_id', q.member_id, 'name', q.name, 'busy', q.busy, 'since', q.waiting_since))
      from private.courier_queue(v_member.restaurant_id) q
    ), '[]'::jsonb),
    'waiting', (
      select count(*) from orders
      where restaurant_id = v_member.restaurant_id and kind = 'delivery' and courier_member is null
        and fulfillment in ('accepted', 'ready')
    ),
    'courses', coalesce((
      select jsonb_agg(private.course_json(o) order by o.courier_assigned_at)
      from orders o
      where o.courier_member = p_member_id and o.fulfillment in ('accepted', 'ready', 'on_the_way')
    ), '[]'::jsonb),
    'today_count', (
      select count(*) from orders
      where courier_member = p_member_id and fulfillment = 'delivered' and delivered_at >= v_since
    ),
    'today_cash_grosze', coalesce((
      select sum((private.course_json(o) ->> 'total_grosze')::integer) from orders o
      where o.courier_member = p_member_id and o.fulfillment = 'delivered' and o.delivered_at >= v_since
        and o.payment_choice = 'cash'
    ), 0)
  );
end;
$$;

-- Dodatkowe stanowiska pracownika (główne zostaje w staff_members.position_id).
create or replace function public.panel_set_member_positions(p_member_id uuid, p_position_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member  staff_members%rowtype;
begin
  select * into v_member from staff_members where id = p_member_id;
  if not found then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  perform private.require_staff(v_member.restaurant_id, 'manager');
  if exists (
    select 1 from staff_positions p
    where p.id = any (coalesce(p_position_ids, '{}'))
      and p.restaurant_id is not null and p.restaurant_id <> v_member.restaurant_id
  ) then
    raise exception 'To stanowisko należy do innego lokalu.';
  end if;
  delete from staff_member_positions
  where member_id = p_member_id
    and (not (position_id = any (coalesce(p_position_ids, '{}'))) or position_id is not distinct from v_member.position_id);
  insert into staff_member_positions (member_id, position_id, restaurant_id)
  select p_member_id, x, v_member.restaurant_id
  from unnest(coalesce(p_position_ids, '{}')) as x
  where x is distinct from v_member.position_id
    and exists (select 1 from staff_positions p where p.id = x)
  on conflict do nothing;
end;
$$;

-- ---------------------------------------------------------------
-- 2. Grafik: niedostępny, propozycje, termin, uwaga na tydzień, stanowisko na dzień
-- ---------------------------------------------------------------

alter table public.staff_schedule drop constraint staff_schedule_status_check;
alter table public.staff_schedule add constraint staff_schedule_status_check
  check (status = any (array['pending', 'accepted', 'rejected', 'off', 'proposed', 'unavailable']));
alter table public.staff_schedule drop constraint staff_schedule_hours_check;
alter table public.staff_schedule add constraint staff_schedule_hours_check check (
  (status in ('off', 'unavailable') and starts is null and ends is null)
  or (status not in ('off', 'unavailable') and starts is not null and ends is not null and ends > starts)
);
alter table public.staff_schedule
  add column if not exists position_id uuid references public.staff_positions (id) on delete set null;

-- Termin zgłaszania dyspozycyjności: dzień tygodnia (1 = poniedziałek) i godzina przed początkiem okresu grafiku.
-- Bez dnia: bez terminu.
alter table public.restaurants
  add column if not exists schedule_deadline_dow smallint check (schedule_deadline_dow between 1 and 7),
  add column if not exists schedule_deadline_time time not null default '20:00';
grant update (schedule_deadline_dow, schedule_deadline_time) on public.restaurants to authenticated;

-- Pierwszy dzień okresu grafiku z dniem p_day (tydzień od poniedziałku, pary tygodni od 5.01.2026, miesiąc).
create or replace function private.schedule_period_start(p_kind text, p_day date)
returns date
language sql
immutable
set search_path = ''
as $$
  select case p_kind
    when 'month' then date_trunc('month', p_day)::date
    when 'two_weeks' then date '2026-01-05' + (floor((p_day - date '2026-01-05') / 14.0) * 14)::integer
    else date_trunc('week', p_day)::date
  end
$$;

-- Do kiedy można zgłaszać dyspozycyjność na okres z dniem p_day: ostatni wybrany dzień tygodnia przed początkiem
-- okresu, o wybranej godzinie (czas lokalu). Null: lokal nie ustawił terminu.
create or replace function private.schedule_deadline(p_restaurant_id uuid, p_day date)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select case when r.schedule_deadline_dow is null then null else
    ((s.start - 1 - ((extract(isodow from s.start - 1)::integer - r.schedule_deadline_dow + 7) % 7))
      + r.schedule_deadline_time) at time zone coalesce(r.timezone, 'Europe/Warsaw')
  end
  from public.restaurants r
  cross join lateral (select private.schedule_period_start(r.schedule_period, p_day) as start) s
  where r.id = p_restaurant_id
$$;

-- Termin minął: zgłaszanie wyłączone, pracownik jest niedostępny w dniach bez zgłoszenia.
create or replace function private.check_schedule_deadline(p_restaurant_id uuid, p_day date)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_deadline timestamptz := private.schedule_deadline(p_restaurant_id, p_day);
  v_tz       text;
begin
  if v_deadline is not null and now() > v_deadline then
    select coalesce(timezone, 'Europe/Warsaw') into v_tz from public.restaurants where id = p_restaurant_id;
    raise exception 'Termin zgłaszania dyspozycyjności na ten okres minął (%). Zapytaj przełożonego.',
      to_char(v_deadline at time zone v_tz, 'DD.MM HH24:MI');
  end if;
end;
$$;

create or replace function public.staff_submit_hours(p_member_id uuid, p_day date, p_starts time, p_ends time, p_note text default null)
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
  perform private.check_schedule_deadline(v_member.restaurant_id, p_day);

  select status into v_status from staff_schedule where member_id = p_member_id and day = p_day;
  if v_status = 'off' then
    raise exception 'Przełożony dał Ci wolne w tym dniu.';
  end if;
  if v_status = 'proposed' then
    raise exception 'Przełożony wysłał Ci propozycję na ten dzień. Przyjmij ją albo odrzuć.';
  end if;
  if v_status is not null and v_status not in ('pending', 'unavailable') then
    raise exception 'Przełożony już zdecydował o tym dniu. Tych godzin nie można już zmienić.';
  end if;

  insert into staff_schedule (restaurant_id, member_id, day, starts, ends, requested_starts, requested_ends, note, status)
  values (v_member.restaurant_id, p_member_id, p_day, p_starts, p_ends, p_starts, p_ends, nullif(btrim(p_note), ''), 'pending')
  on conflict (member_id, day) do update
    set starts = excluded.starts, ends = excluded.ends, status = 'pending',
        requested_starts = excluded.requested_starts, requested_ends = excluded.requested_ends,
        note = excluded.note, updated_at = now();
end;
$$;

-- Pracownik zgłasza, że w danym dniu nie może pracować.
create or replace function public.staff_mark_unavailable(p_member_id uuid, p_day date, p_note text default null)
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
  if p_day is null or p_day < current_date or p_day > current_date + 90 then
    raise exception 'Wybierz dzień od dziś do 90 dni do przodu.';
  end if;
  perform private.check_schedule_deadline(v_member.restaurant_id, p_day);
  select status into v_status from staff_schedule where member_id = p_member_id and day = p_day;
  if v_status is not null and v_status not in ('pending', 'unavailable') then
    raise exception 'Przełożony już zdecydował o tym dniu.';
  end if;
  insert into staff_schedule (restaurant_id, member_id, day, starts, ends, requested_starts, requested_ends, note, status)
  values (v_member.restaurant_id, p_member_id, p_day, null, null, null, null, nullif(btrim(p_note), ''), 'unavailable')
  on conflict (member_id, day) do update
    set starts = null, ends = null, requested_starts = null, requested_ends = null, status = 'unavailable',
        note = excluded.note, updated_at = now();
end;
$$;

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
  if v_row.status not in ('pending', 'unavailable') then
    raise exception 'Przełożony już zdecydował o tym dniu. Tych godzin nie można już zmienić.';
  end if;
  perform private.check_schedule_deadline(v_row.restaurant_id, v_row.day);
  delete from staff_schedule where id = p_id;
end;
$$;

-- Odpowiedź pracownika na propozycję przełożonego: przyjęcie albo „nie mogę” (niedostępny).
create or replace function public.staff_answer_proposal(p_id uuid, p_accept boolean, p_note text default null)
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
    raise exception 'Nie znaleziono tej propozycji.';
  end if;
  if v_row.status <> 'proposed' then
    raise exception 'Ta propozycja jest już nieaktualna.';
  end if;
  if p_accept then
    update staff_schedule set status = 'accepted', note = coalesce(nullif(btrim(p_note), ''), note), updated_at = now()
    where id = p_id;
  else
    update staff_schedule
    set status = 'unavailable', starts = null, ends = null, note = nullif(btrim(p_note), ''), updated_at = now()
    where id = p_id;
  end if;
end;
$$;

drop function if exists public.staff_my_schedule(date, date);
create function public.staff_my_schedule(p_from date, p_to date)
returns table (id uuid, member_id uuid, restaurant_name text, day date, starts time, ends time,
               requested_starts time, requested_ends time, status text, note text, answer text, position_name text)
language sql
stable
security definer
set search_path = public
as $$
  select s.id, s.member_id, r.name, s.day, s.starts, s.ends, s.requested_starts, s.requested_ends,
         s.status, s.note, s.answer, p.name
  from staff_schedule s
  join restaurants r on r.id = s.restaurant_id
  left join staff_positions p on p.id = s.position_id
  where s.member_id in (select id from private.my_members())
    and s.day between p_from and least(p_to, p_from + 92)
  order by s.day
$$;

-- Termin zgłaszania dla okresu z dniem p_day (aplikacja pracownika pokazuje go nad grafikiem).
create or replace function public.staff_schedule_deadline(p_member_id uuid, p_day date)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  select private.schedule_deadline(m.restaurant_id, p_day)
  from private.my_members() m
  where m.id = p_member_id
$$;

drop function if exists public.panel_add_hours(uuid, date, time, time, text);
create function public.panel_add_hours(
  p_member_id    uuid,
  p_day          date,
  p_starts       time,
  p_ends         time,
  p_answer       text default null,
  p_position_id  uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
  v_status      text;
begin
  select restaurant_id into v_restaurant from staff_members where id = p_member_id;
  if v_restaurant is null then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  perform private.require_schedule(v_restaurant);
  if p_starts is null or p_ends is null or p_ends <= p_starts then
    raise exception 'Koniec musi być później niż początek.';
  end if;
  select status into v_status from staff_schedule where member_id = p_member_id and day = p_day;
  if v_status is null or v_status in ('unavailable', 'proposed') then
    raise exception 'Pracownik jest niedostępny w tym dniu. Wyślij mu propozycję.';
  end if;
  update staff_schedule
  set starts = p_starts, ends = p_ends, status = 'accepted', answer = nullif(btrim(p_answer), ''),
      position_id = coalesce(p_position_id, position_id),
      decided_by = auth.uid(), decided_at = now(), updated_at = now()
  where member_id = p_member_id and day = p_day;
end;
$$;

drop function if exists public.panel_decide_hours(uuid, boolean, time, time, text);
create function public.panel_decide_hours(
  p_id           uuid,
  p_accept       boolean,
  p_starts       time default null,
  p_ends         time default null,
  p_answer       text default null,
  p_position_id  uuid default null
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
    if v_row.status in ('unavailable', 'proposed') then
      raise exception 'Pracownik jest niedostępny w tym dniu. Wyślij mu propozycję.';
    end if;
    if coalesce(p_starts, v_row.starts) is null or coalesce(p_ends, v_row.ends) is null then
      raise exception 'Podaj godziny.';
    end if;
    if coalesce(p_ends, v_row.ends) <= coalesce(p_starts, v_row.starts) then
      raise exception 'Koniec musi być później niż początek.';
    end if;
    update staff_schedule
    set status = 'accepted', starts = coalesce(p_starts, starts), ends = coalesce(p_ends, ends),
        position_id = coalesce(p_position_id, position_id),
        answer = nullif(btrim(p_answer), ''), decided_by = auth.uid(), decided_at = now(), updated_at = now()
    where id = p_id;
  else
    if v_row.status in ('off', 'unavailable') then
      raise exception 'W tym dniu nie ma godzin do odrzucenia.';
    end if;
    update staff_schedule
    set status = 'rejected', answer = nullif(btrim(p_answer), ''),
        decided_by = auth.uid(), decided_at = now(), updated_at = now()
    where id = p_id;
  end if;
end;
$$;

-- Propozycja zmiany dla pracownika (także niedostępnego): pracownik przyjmie ją albo odrzuci w aplikacji.
create or replace function public.panel_propose_hours(
  p_member_id    uuid,
  p_day          date,
  p_starts       time,
  p_ends         time,
  p_answer       text default null,
  p_position_id  uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
  v_status      text;
begin
  select restaurant_id into v_restaurant from staff_members where id = p_member_id;
  if v_restaurant is null then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  perform private.require_schedule(v_restaurant);
  if p_day is null then
    raise exception 'Wybierz dzień.';
  end if;
  if p_starts is null or p_ends is null or p_ends <= p_starts then
    raise exception 'Koniec musi być później niż początek.';
  end if;
  select status into v_status from staff_schedule where member_id = p_member_id and day = p_day;
  if v_status = 'accepted' then
    raise exception 'Ten dzień ma już przyjęte godziny.';
  end if;
  insert into staff_schedule (restaurant_id, member_id, day, starts, ends, status, answer, position_id, decided_by, decided_at)
  values (v_restaurant, p_member_id, p_day, p_starts, p_ends, 'proposed', nullif(btrim(p_answer), ''), p_position_id,
          auth.uid(), now())
  on conflict (member_id, day) do update
    set starts = excluded.starts, ends = excluded.ends, status = 'proposed', answer = excluded.answer,
        position_id = excluded.position_id, decided_by = excluded.decided_by, decided_at = now(), updated_at = now();
end;
$$;

create or replace function public.panel_save_schedule(p_restaurant_id uuid, p_changes jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c         jsonb;
  v_n         integer := 0;
  v_member    uuid;
  v_id        uuid;
  v_day       date;
  v_position  uuid;
begin
  perform private.require_schedule(p_restaurant_id);
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' or jsonb_array_length(p_changes) = 0 then
    raise exception 'Nie ma zmian do zapisania.';
  end if;
  if jsonb_array_length(p_changes) > 1000 then
    raise exception 'Za dużo zmian naraz. Zapisz grafik w częściach.';
  end if;
  for v_c in select * from jsonb_array_elements(p_changes) loop
    v_member := nullif(v_c->>'member_id', '')::uuid;
    v_id := nullif(v_c->>'id', '')::uuid;
    v_day := nullif(v_c->>'day', '')::date;
    v_position := nullif(v_c->>'position_id', '')::uuid;
    if v_member is not null
       and not exists (select 1 from staff_members where id = v_member and restaurant_id = p_restaurant_id) then
      raise exception 'Nie znaleziono pracownika.';
    end if;
    if v_c->>'action' in ('accept', 'reject')
       and not exists (select 1 from staff_schedule where id = v_id and restaurant_id = p_restaurant_id) then
      raise exception 'Zgłoszenie z % zmieniło się w trakcie edycji. Sprawdź ten dzień i zapisz jeszcze raz.',
        coalesce(to_char(v_day, 'DD.MM'), 'tego dnia');
    end if;
    case v_c->>'action'
      when 'accept' then
        perform panel_decide_hours(v_id, true, nullif(v_c->>'starts', '')::time, nullif(v_c->>'ends', '')::time,
                                   v_c->>'answer', v_position);
      when 'reject' then
        perform panel_decide_hours(v_id, false, null, null, v_c->>'answer', null);
      when 'add' then
        perform panel_add_hours(v_member, v_day, nullif(v_c->>'starts', '')::time, nullif(v_c->>'ends', '')::time,
                                v_c->>'answer', v_position);
      when 'propose' then
        perform panel_propose_hours(v_member, v_day, nullif(v_c->>'starts', '')::time, nullif(v_c->>'ends', '')::time,
                                    v_c->>'answer', v_position);
      when 'off' then
        perform panel_set_day_off(v_member, v_day, v_c->>'answer');
      when 'delete' then
        if exists (select 1 from staff_schedule where id = v_id and restaurant_id = p_restaurant_id) then
          perform panel_delete_hours(v_id);
        end if;
      else
        raise exception 'Nieznana zmiana w grafiku.';
    end case;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- Uwaga pracownika na tydzień (np. „w środę egzamin”).
create table public.staff_week_notes (
  member_id      uuid not null references public.staff_members (id) on delete cascade,
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  week_start     date not null check (extract(isodow from week_start) = 1),
  note           text not null check (char_length(note) between 1 and 300),
  updated_at     timestamptz not null default now(),
  primary key (member_id, week_start)
);
alter table public.staff_week_notes enable row level security;
create policy staff_week_notes_read on public.staff_week_notes
  for select to authenticated using (
    private.has_staff_role(restaurant_id) or member_id in (select m.id from private.my_members() m)
  );
alter publication supabase_realtime add table public.staff_week_notes;

create or replace function public.staff_set_week_note(p_member_id uuid, p_week date, p_note text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member  staff_members%rowtype;
  v_week    date := date_trunc('week', p_week)::date;
begin
  select * into v_member from private.my_members() m where m.id = p_member_id;
  if not found then
    raise exception 'Nie ma Cię na liście pracowników tego lokalu.';
  end if;
  if nullif(btrim(p_note), '') is null then
    delete from staff_week_notes where member_id = p_member_id and week_start = v_week;
    return;
  end if;
  if char_length(btrim(p_note)) > 300 then
    raise exception 'Uwaga do 300 znaków.';
  end if;
  insert into staff_week_notes (member_id, restaurant_id, week_start, note)
  values (p_member_id, v_member.restaurant_id, v_week, btrim(p_note))
  on conflict (member_id, week_start) do update set note = excluded.note, updated_at = now();
end;
$$;

-- ---------------------------------------------------------------
-- 3. Liczba gości przy rachunku
-- ---------------------------------------------------------------

alter table public.orders
  add column if not exists guests smallint check (guests between 1 and 99),
  add column if not exists guests_skipped boolean not null default false;

drop function if exists public.panel_open_order(uuid, uuid, uuid);
create function public.panel_open_order(
  p_restaurant_id  uuid,
  p_table_id       uuid,
  p_member_id      uuid default null,
  p_guests         integer default null,
  p_skip_guests    boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id     uuid;
  v_res    uuid;
  v_party  integer;
begin
  perform private.require_permission(p_restaurant_id, 'orders');
  perform private.check_member(p_restaurant_id, p_member_id);
  if p_guests is not null and p_guests not between 1 and 99 then
    raise exception 'Liczba gości od 1 do 99.';
  end if;

  if not exists (select 1 from dining_tables where id = p_table_id and restaurant_id = p_restaurant_id) then
    raise exception 'Nie znaleziono stolika.';
  end if;

  select id into v_id from orders where table_id = p_table_id and status = 'open';
  if found then
    if p_guests is not null then
      update orders set guests = p_guests, guests_skipped = false where id = v_id and guests is null;
    end if;
    return v_id;
  end if;

  select h.reservation_id, r.party_size into v_res, v_party
  from table_holds h
  join reservations r on r.id = h.reservation_id
  where h.table_id = p_table_id
    and h.active
    and r.status in ('seated', 'confirmed')
    and now() between lower(h.slot) - interval '30 minutes' and upper(h.slot)
  order by (r.status = 'seated') desc, lower(h.slot)
  limit 1;

  begin
    insert into orders (restaurant_id, table_id, reservation_id, opened_by, opened_by_member, guests, guests_skipped)
    values (p_restaurant_id, p_table_id, v_res, auth.uid(), p_member_id,
            coalesce(p_guests, case when v_party is null then null else least(v_party, 99) end),
            coalesce(p_skip_guests, false) and p_guests is null and v_party is null)
    returning id into v_id;
  exception
    when unique_violation then
      select id into v_id from orders where table_id = p_table_id and status = 'open';
  end;
  return v_id;
end;
$$;

create or replace function public.panel_set_order_guests(p_order_id uuid, p_guests integer, p_member_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
begin
  select * into v_order from orders where id = p_order_id;
  if not found then
    raise exception 'Nie znaleziono rachunku.';
  end if;
  perform private.require_permission(v_order.restaurant_id, 'orders');
  perform private.check_member(v_order.restaurant_id, p_member_id);
  if p_guests is null or p_guests not between 1 and 99 then
    raise exception 'Liczba gości od 1 do 99.';
  end if;
  update orders set guests = p_guests, guests_skipped = false where id = p_order_id;
end;
$$;

-- ---------------------------------------------------------------
-- 4. Statystyki zespołu
-- ---------------------------------------------------------------

-- Okres statystyk: od p_from (np. północ dziś), miesiąc kalendarzowy albo ostatnie p_days dni.
create or replace function private.stats_range(p_restaurant_id uuid, p_days integer, p_month date, p_from timestamptz,
  out starts timestamptz, out ends timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_from is not null then
    starts := greatest(p_from, now() - interval '400 days');
    ends := now();
  elsif p_month is not null then
    select m.starts, m.ends into starts, ends from private.month_range(p_restaurant_id, p_month) m;
  else
    starts := now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 366)));
    ends := now();
  end if;
end;
$$;

drop function if exists public.panel_team_stats(uuid, integer, date);
create function public.panel_team_stats(
  p_restaurant_id  uuid,
  p_days           integer default 30,
  p_month          date default null,
  p_from           timestamptz default null
)
returns table (member_id uuid, name text, position_name text, active boolean, seconds bigint, shifts integer,
               orders_opened integer, orders_closed integer, revenue bigint, items bigint, deliveries integer,
               rate integer, earnings bigint, contract text, tips_cash bigint, tips_card bigint, guests bigint,
               guests_skipped integer)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_start  timestamptz;
  v_end    timestamptz;
  v_pay    boolean;
begin
  perform private.require_permission(p_restaurant_id, 'stats');
  v_pay := private.has_permission(p_restaurant_id, 'staff');
  select r.starts, r.ends into v_start, v_end from private.stats_range(p_restaurant_id, p_days, p_month, p_from) r;

  return query
  with base as (
    select
      m.id,
      m.name,
      pos.name as position_name,
      m.active,
      (
        select coalesce(sum(extract(epoch from least(coalesce(s.ended_at, now()), v_end) - greatest(s.started_at, v_start))), 0)
        from staff_shifts s
        where s.member_id = m.id and coalesce(s.ended_at, now()) > v_start and s.started_at < v_end
      )::bigint as seconds,
      (select count(*) from staff_shifts s
       where s.member_id = m.id and coalesce(s.ended_at, now()) > v_start and s.started_at < v_end)::integer as shifts,
      (select count(*) from orders o
       where o.opened_by_member = m.id and o.opened_at >= v_start and o.opened_at < v_end)::integer as orders_opened,
      (select count(*) from orders o
       where o.closed_by_member = m.id and o.status = 'paid'
         and o.closed_at >= v_start and o.closed_at < v_end)::integer as orders_closed,
      (
        select coalesce(sum(i.unit_price_grosze * i.quantity), 0)
        from orders o
        join order_items i on i.order_id = o.id and i.status <> 'cancelled'
        where o.closed_by_member = m.id and o.status = 'paid' and o.closed_at >= v_start and o.closed_at < v_end
      )::bigint as revenue,
      (
        select coalesce(sum(i.quantity), 0)
        from order_items i
        where i.created_by_member = m.id and i.status <> 'cancelled' and i.created_at >= v_start and i.created_at < v_end
      )::bigint as items,
      (select count(*) from orders o
       where o.courier_member = m.id and o.fulfillment = 'delivered'
         and o.delivered_at >= v_start and o.delivered_at < v_end)::integer as deliveries,
      case when v_pay then sr.hourly_rate_grosze end as rate,
      case when v_pay then sr.contract end as contract,
      (select coalesce(sum(p.tip_grosze), 0) from order_payments p
       where p.member_id = m.id and p.method = 'cash' and p.created_at >= v_start and p.created_at < v_end)::bigint as tips_cash,
      (select coalesce(sum(p.tip_grosze), 0) from order_payments p
       where p.member_id = m.id and p.method <> 'cash' and p.created_at >= v_start and p.created_at < v_end)::bigint as tips_card,
      (select coalesce(sum(o.guests), 0) from orders o
       where o.opened_by_member = m.id and o.kind = 'dine_in' and o.opened_at >= v_start and o.opened_at < v_end)::bigint as guests,
      (select count(*) from orders o
       where o.opened_by_member = m.id and o.guests_skipped and o.opened_at >= v_start and o.opened_at < v_end)::integer
        as guests_skipped
    from staff_members m
    left join staff_positions pos on pos.id = m.position_id
    left join staff_rates sr on sr.member_id = m.id
    where m.restaurant_id = p_restaurant_id
  )
  select b.id, b.name, b.position_name, b.active, b.seconds, b.shifts, b.orders_opened, b.orders_closed,
         b.revenue, b.items, b.deliveries, b.rate,
         case when b.rate is null then null else round(b.seconds * b.rate / 3600.0)::bigint end,
         b.contract, b.tips_cash, b.tips_card, b.guests, b.guests_skipped
  from base b
  order by b.seconds desc, b.name;
end;
$$;

-- Podsumowanie okresu dla statystyk zespołu: obrót lokalu (do udziału wynagrodzeń), goście i pominięcia.
create or replace function public.panel_team_summary(
  p_restaurant_id  uuid,
  p_days           integer default 30,
  p_month          date default null,
  p_from           timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_start  timestamptz;
  v_end    timestamptz;
begin
  perform private.require_permission(p_restaurant_id, 'stats');
  select r.starts, r.ends into v_start, v_end from private.stats_range(p_restaurant_id, p_days, p_month, p_from) r;
  return jsonb_build_object(
    'revenue', coalesce((
      select sum(o.delivery_fee_grosze - o.discount_grosze + coalesce((
        select sum(i.unit_price_grosze * i.quantity) from order_items i
        where i.order_id = o.id and i.status <> 'cancelled'
      ), 0))
      from orders o
      where o.restaurant_id = p_restaurant_id and o.status = 'paid' and o.closed_at >= v_start and o.closed_at < v_end
    ), 0),
    'tables', (select count(*) from orders o
               where o.restaurant_id = p_restaurant_id and o.kind = 'dine_in' and o.note is distinct from 'Część rachunku'
                 and o.opened_at >= v_start and o.opened_at < v_end),
    'guests', coalesce((select sum(o.guests) from orders o
               where o.restaurant_id = p_restaurant_id and o.kind = 'dine_in'
                 and o.opened_at >= v_start and o.opened_at < v_end), 0),
    'skipped', (select count(*) from orders o
                where o.restaurant_id = p_restaurant_id and o.guests_skipped
                  and o.opened_at >= v_start and o.opened_at < v_end),
    'tips_cash', coalesce((select sum(p.tip_grosze) from order_payments p
                 where p.restaurant_id = p_restaurant_id and p.method = 'cash'
                   and p.created_at >= v_start and p.created_at < v_end), 0),
    'tips_card', coalesce((select sum(p.tip_grosze) from order_payments p
                 where p.restaurant_id = p_restaurant_id and p.method <> 'cash'
                   and p.created_at >= v_start and p.created_at < v_end), 0)
  );
end;
$$;

revoke execute on function private.member_position_ids(uuid) from public, anon;
revoke execute on function private.member_permissions(uuid) from public, anon;
revoke execute on function private.is_courier(uuid) from public, anon;
revoke execute on function private.schedule_period_start(text, date) from public, anon;
revoke execute on function private.schedule_deadline(uuid, date) from public, anon;
revoke execute on function private.check_schedule_deadline(uuid, date) from public, anon;
revoke execute on function private.stats_range(uuid, integer, date, timestamptz) from public, anon;
revoke execute on function public.panel_set_member_positions(uuid, uuid[]) from public, anon;
revoke execute on function public.staff_mark_unavailable(uuid, date, text) from public, anon;
revoke execute on function public.staff_answer_proposal(uuid, boolean, text) from public, anon;
revoke execute on function public.staff_my_schedule(date, date) from public, anon;
revoke execute on function public.staff_schedule_deadline(uuid, date) from public, anon;
revoke execute on function public.panel_add_hours(uuid, date, time, time, text, uuid) from public, anon;
revoke execute on function public.panel_decide_hours(uuid, boolean, time, time, text, uuid) from public, anon;
revoke execute on function public.panel_propose_hours(uuid, date, time, time, text, uuid) from public, anon;
revoke execute on function public.staff_set_week_note(uuid, date, text) from public, anon;
revoke execute on function public.panel_open_order(uuid, uuid, uuid, integer, boolean) from public, anon;
revoke execute on function public.panel_set_order_guests(uuid, integer, uuid) from public, anon;
revoke execute on function public.panel_team_stats(uuid, integer, date, timestamptz) from public, anon;
revoke execute on function public.panel_team_summary(uuid, integer, date, timestamptz) from public, anon;
grant execute on function private.member_position_ids(uuid) to authenticated;
grant execute on function private.member_permissions(uuid) to authenticated;
grant execute on function private.is_courier(uuid) to authenticated;
grant execute on function private.schedule_period_start(text, date) to authenticated;
grant execute on function private.schedule_deadline(uuid, date) to authenticated;
grant execute on function private.check_schedule_deadline(uuid, date) to authenticated;
grant execute on function private.stats_range(uuid, integer, date, timestamptz) to authenticated;
grant execute on function public.panel_set_member_positions(uuid, uuid[]) to authenticated;
grant execute on function public.staff_mark_unavailable(uuid, date, text) to authenticated;
grant execute on function public.staff_answer_proposal(uuid, boolean, text) to authenticated;
grant execute on function public.staff_my_schedule(date, date) to authenticated;
grant execute on function public.staff_schedule_deadline(uuid, date) to authenticated;
grant execute on function public.panel_add_hours(uuid, date, time, time, text, uuid) to authenticated;
grant execute on function public.panel_decide_hours(uuid, boolean, time, time, text, uuid) to authenticated;
grant execute on function public.panel_propose_hours(uuid, date, time, time, text, uuid) to authenticated;
grant execute on function public.staff_set_week_note(uuid, date, text) to authenticated;
grant execute on function public.panel_open_order(uuid, uuid, uuid, integer, boolean) to authenticated;
grant execute on function public.panel_set_order_guests(uuid, integer, uuid) to authenticated;
grant execute on function public.panel_team_stats(uuid, integer, date, timestamptz) to authenticated;
grant execute on function public.panel_team_summary(uuid, integer, date, timestamptz) to authenticated;
