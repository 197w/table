-- Table · migracja 0035
-- „Wolne” w grafiku: przełożony daje pracownikowi wolny dzień (panel, „Pracownicy” → „Grafik”).
-- Wpis nie ma godzin. Pracownik widzi go w aplikacji i nie zgłosi już godzin na ten dzień.

alter table public.staff_schedule
  alter column starts drop not null,
  alter column ends drop not null,
  drop constraint staff_schedule_check,
  drop constraint staff_schedule_status_check;

-- off: wolne (bez godzin), pozostałe stany zawsze z godzinami.
alter table public.staff_schedule
  add constraint staff_schedule_status_check check (status in ('pending', 'accepted', 'rejected', 'off')),
  add constraint staff_schedule_hours_check check (
    (status = 'off' and starts is null and ends is null)
    or (status <> 'off' and starts is not null and ends is not null and ends > starts)
  );

-- Jak w 0030, z osobnym komunikatem dla wolnego dnia.
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
  if v_status = 'off' then
    raise exception 'Przełożony dał Ci wolne w tym dniu.';
  end if;
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

-- Jak w 0030. Przyjęcie wolnego dnia wymaga podania godzin.
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
    if coalesce(p_starts, v_row.starts) is null or coalesce(p_ends, v_row.ends) is null then
      raise exception 'Podaj godziny.';
    end if;
    if coalesce(p_ends, v_row.ends) <= coalesce(p_starts, v_row.starts) then
      raise exception 'Koniec musi być później niż początek.';
    end if;
    update staff_schedule
    set status = 'accepted', starts = coalesce(p_starts, starts), ends = coalesce(p_ends, ends),
        answer = nullif(btrim(p_answer), ''), decided_by = auth.uid(), decided_at = now(), updated_at = now()
    where id = p_id;
  else
    if v_row.status = 'off' then
      raise exception 'Ten dzień to już wolne. Usuń wpis, żeby pracownik mógł zgłosić godziny.';
    end if;
    update staff_schedule
    set status = 'rejected', answer = nullif(btrim(p_answer), ''),
        decided_by = auth.uid(), decided_at = now(), updated_at = now()
    where id = p_id;
  end if;
end;
$$;

-- Przełożony daje wolne: pusty dzień albo zamiana zgłoszenia czy przyjętych godzin na wolne.
-- Zgłoszone przez pracownika godziny zostają w requested_starts i requested_ends.
create or replace function public.panel_set_day_off(
  p_member_id  uuid,
  p_day        date,
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
  if p_day is null then
    raise exception 'Wybierz dzień.';
  end if;
  insert into staff_schedule (restaurant_id, member_id, day, starts, ends, status, answer, decided_by, decided_at)
  values (v_restaurant, p_member_id, p_day, null, null, 'off', nullif(btrim(p_answer), ''), auth.uid(), now())
  on conflict (member_id, day) do update
    set starts = null, ends = null, status = 'off', answer = excluded.answer,
        decided_by = excluded.decided_by, decided_at = now(), updated_at = now();
end;
$$;

revoke execute on function public.panel_set_day_off(uuid, date, text) from public, anon;
grant execute on function public.panel_set_day_off(uuid, date, text) to authenticated;
