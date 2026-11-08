-- 0081: Okno zgłaszania dyspozycyjności (8.11.2026).
-- Pracownik zgłasza godziny (i „Nie mogę”) tylko na jeden okres lokalu naraz: tydzień, 2 tygodnie albo miesiąc
-- z „Ustawienia lokalu” → „Grafik pracowników” → „Okres zgłaszania”. To pierwszy okres po bieżącym, którego termin
-- zgłaszania jeszcze nie minął (bez terminu: po prostu następny okres). Ani wcześniej (bieżący okres i okresy po
-- terminie), ani później (kolejne okresy). W aplikacji Table for employees te dni są zielone.

-- Ostatni dzień okresu, który zaczyna się [p_start].
create or replace function private.schedule_period_end(p_kind text, p_start date)
returns date
language sql
immutable
set search_path = ''
as $$
  select case p_kind
    when 'month' then (p_start + interval '1 month')::date - 1
    when 'two_weeks' then p_start + 13
    else p_start + 6
  end
$$;

-- Okres, na który pracownicy lokalu zgłaszają teraz dyspozycyjność.
create or replace function private.schedule_window(p_restaurant_id uuid)
returns table (starts date, ends date)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_kind   text;
  v_tz     text;
  v_today  date;
  v_start  date;
  v_dl     timestamptz;
begin
  select coalesce(r.schedule_period, 'week'), coalesce(r.timezone, 'Europe/Warsaw')
  into v_kind, v_tz
  from public.restaurants r
  where r.id = p_restaurant_id;
  if not found then
    return;
  end if;
  v_today := (now() at time zone v_tz)::date;
  -- Pierwszy okres po bieżącym; gdy jego termin minął, następny (termin jest zawsze przed początkiem okresu).
  v_start := private.schedule_period_end(v_kind, private.schedule_period_start(v_kind, v_today)) + 1;
  for i in 1..3 loop
    v_dl := private.schedule_deadline(p_restaurant_id, v_start);
    exit when v_dl is null or now() <= v_dl;
    v_start := private.schedule_period_end(v_kind, v_start) + 1;
  end loop;
  starts := v_start;
  ends := private.schedule_period_end(v_kind, v_start);
  return next;
end;
$$;

-- Dzień poza oknem zgłaszania: błąd po polsku z zakresem dni.
create or replace function private.check_schedule_window(p_restaurant_id uuid, p_day date)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_starts  date;
  v_ends    date;
begin
  select w.starts, w.ends into v_starts, v_ends from private.schedule_window(p_restaurant_id) w;
  if v_starts is null then
    return;
  end if;
  if p_day < v_starts or p_day > v_ends then
    raise exception 'Dyspozycyjność zgłaszasz teraz tylko na dni od % do %.',
      to_char(v_starts, 'DD.MM'), to_char(v_ends, 'DD.MM');
  end if;
end;
$$;

-- Okno zgłaszania i jego termin dla aplikacji pracownika.
create or replace function public.staff_schedule_window(p_member_id uuid)
returns table (starts date, ends date, deadline timestamptz)
language sql
stable
security definer
set search_path = 'public'
as $$
  select w.starts, w.ends, private.schedule_deadline(m.restaurant_id, w.starts)
  from private.my_members() m
  cross join lateral private.schedule_window(m.restaurant_id) w
  where m.id = p_member_id
$$;

create or replace function public.staff_submit_hours(p_member_id uuid, p_day date, p_starts time without time zone, p_ends time without time zone, p_note text default null::text)
returns void
language plpgsql
security definer
set search_path = 'public'
as $function$
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
  if p_starts is null or p_ends is null or p_ends = p_starts then
    raise exception 'Początek i koniec nie mogą być takie same.';
  end if;
  perform private.check_schedule_deadline(v_member.restaurant_id, p_day);
  perform private.check_schedule_window(v_member.restaurant_id, p_day);

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
$function$;

create or replace function public.staff_mark_unavailable(p_member_id uuid, p_day date, p_note text default null::text)
returns void
language plpgsql
security definer
set search_path = 'public'
as $function$
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
  perform private.check_schedule_window(v_member.restaurant_id, p_day);
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
$function$;

revoke execute on function private.schedule_period_end(text, date) from public, anon;
revoke execute on function private.schedule_window(uuid) from public, anon;
revoke execute on function private.check_schedule_window(uuid, date) from public, anon;
revoke execute on function public.staff_schedule_window(uuid) from public, anon;
grant execute on function private.schedule_period_end(text, date) to authenticated;
grant execute on function private.schedule_window(uuid) to authenticated;
grant execute on function private.check_schedule_window(uuid, date) to authenticated;
grant execute on function public.staff_schedule_window(uuid) to authenticated;
