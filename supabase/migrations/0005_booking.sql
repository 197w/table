-- Rarytka · migracja 0005
-- Wolne terminy, automatyczny dobór stolika, rezerwacja i odwołanie.

create schema if not exists private;
revoke all on schema private from public;

-- ---------------------------------------------------------------
-- Czas zajęcia stolika
-- ---------------------------------------------------------------

create or replace function private.visit_minutes(p_party integer)
returns integer
language sql
immutable
as $$
  select case when p_party <= 2 then 90 when p_party <= 4 then 105 else 120 end
$$;

create or replace function private.cleanup_minutes(p_party integer)
returns integer
language sql
immutable
as $$
  select case when p_party <= 4 then 15 else 20 end
$$;

-- ---------------------------------------------------------------
-- Dobór stolika
-- Kolejność: pojedynczy stolik marnujący najwyżej 2 miejsca,
-- potem dowolny pojedynczy, potem para z tej samej grupy łączenia.
-- Zwraca null, gdy nic nie pasuje.
-- ---------------------------------------------------------------

create or replace function private.find_tables(
  p_restaurant_id  uuid,
  p_party          integer,
  p_slot           tstzrange
)
returns uuid[]
language sql
stable
set search_path = public
as $$
  with free as (
    select t.id, t.seats, t.join_group, t.priority
    from dining_tables t
    where t.restaurant_id = p_restaurant_id
      and t.active
      and not exists (
        select 1 from table_holds h
        where h.table_id = t.id and h.active and h.slot && p_slot
      )
  ),
  candidates as (
    select array[f.id] as ids, f.seats::integer as seats, 1 as tables_count, f.priority::integer as priority
    from free f
    where f.seats >= p_party
    union all
    select array[a.id, b.id], (a.seats + b.seats)::integer, 2, greatest(a.priority, b.priority)::integer
    from free a
    join free b on a.join_group = b.join_group and a.id < b.id
    where a.join_group is not null
      and a.seats + b.seats >= p_party
  )
  select c.ids
  from candidates c
  order by c.tables_count, (c.seats - p_party) > 2, c.seats, c.priority desc
  limit 1
$$;

revoke execute on all functions in schema private from public;

-- ---------------------------------------------------------------
-- Wolne godziny w danym dniu
-- ---------------------------------------------------------------

create or replace function public.available_slots(
  p_restaurant_id  uuid,
  p_date           date,
  p_party_size     integer
)
returns table (slot_start timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  with r as (
    select id, timezone, slot_interval_min
    from restaurants
    where id = p_restaurant_id and plan = 'pro'
  ),
  h as (
    select oh.opens, oh.closes
    from opening_hours oh
    join r on r.id = oh.restaurant_id
    where oh.weekday = extract(isodow from p_date)
  ),
  d as (
    select private.visit_minutes(p_party_size) as visit,
           private.cleanup_minutes(p_party_size) as cleanup
  ),
  series as (
    select (gs at time zone r.timezone) as starts_at, d.visit, d.cleanup
    from r, h, d,
      generate_series(
        p_date + h.opens,
        p_date + h.closes - make_interval(mins => d.visit),
        make_interval(mins => r.slot_interval_min)
      ) as gs
  )
  select s.starts_at
  from series s
  where p_party_size between 1 and 12
    and s.starts_at > now() + interval '30 minutes'
    and private.find_tables(
          p_restaurant_id,
          p_party_size,
          tstzrange(s.starts_at, s.starts_at + make_interval(mins => s.visit + s.cleanup))
        ) is not null
  order by s.starts_at
$$;

-- ---------------------------------------------------------------
-- Rezerwacja z automatycznym doborem stolika
-- ---------------------------------------------------------------

create or replace function public.book_table(
  p_restaurant_id  uuid,
  p_starts_at      timestamptz,
  p_party_size     integer,
  p_occasion       public.reservation_occasion default null,
  p_message        text default null,
  p_diet           text default null,
  p_diet_consent   boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_rest      record;
  v_hours     record;
  v_local     timestamp;
  v_visit     integer;
  v_cleanup   integer;
  v_ends      timestamptz;
  v_slot      tstzrange;
  v_ids       uuid[];
  v_res_id    uuid;
  v_attempt   integer := 0;
  v_upcoming  integer;
begin
  if v_uid is null then
    raise exception 'Zaloguj się, żeby zarezerwować stolik.';
  end if;

  if p_party_size is null or p_party_size not between 1 and 12 then
    raise exception 'Rezerwacja w aplikacji obejmuje od 1 do 12 osób.';
  end if;

  select id, timezone, slot_interval_min, plan into v_rest
  from restaurants where id = p_restaurant_id;

  if not found then
    raise exception 'Nie znaleziono restauracji.';
  end if;

  if v_rest.plan <> 'pro' then
    raise exception 'Ta restauracja przyjmuje rezerwacje tylko telefonicznie.';
  end if;

  if p_starts_at < now() + interval '30 minutes' or p_starts_at > now() + interval '60 days' then
    raise exception 'Wybierz termin od 30 minut do 60 dni od teraz.';
  end if;

  v_visit   := private.visit_minutes(p_party_size);
  v_cleanup := private.cleanup_minutes(p_party_size);
  v_local   := p_starts_at at time zone v_rest.timezone;

  if extract(minute from v_local)::integer % v_rest.slot_interval_min <> 0
     or extract(second from v_local) <> 0 then
    raise exception 'Wybierz godzinę z listy wolnych terminów.';
  end if;

  select opens, closes into v_hours
  from opening_hours
  where restaurant_id = p_restaurant_id
    and weekday = extract(isodow from v_local);

  if not found
     or v_local::time < v_hours.opens
     or v_local + make_interval(mins => v_visit) > v_local::date + v_hours.closes then
    raise exception 'Restauracja jest wtedy zamknięta.';
  end if;

  if nullif(btrim(p_diet), '') is not null and not coalesce(p_diet_consent, false) then
    raise exception 'Zaznacz zgodę, żeby przekazać restauracji informację o alergiach.';
  end if;

  select count(*) into v_upcoming
  from reservations
  where user_id = v_uid and status = 'confirmed' and starts_at > now();

  if v_upcoming >= 5 then
    raise exception 'Masz już 5 nadchodzących rezerwacji. Odwołaj jedną, żeby dodać kolejną.';
  end if;

  v_ends := p_starts_at + make_interval(mins => v_visit);
  v_slot := tstzrange(p_starts_at, v_ends + make_interval(mins => v_cleanup));

  insert into reservations (
    restaurant_id, user_id, party_size, starts_at, ends_at,
    occasion, message, message_delete_after
  )
  values (
    p_restaurant_id, v_uid, p_party_size, p_starts_at, v_ends,
    p_occasion, nullif(btrim(p_message), ''), v_ends + interval '30 days'
  )
  returning id into v_res_id;

  -- Blokada w bazie rozstrzyga wyścig. Przy kolizji próbujemy kolejnego stolika.
  loop
    v_attempt := v_attempt + 1;
    v_ids := private.find_tables(p_restaurant_id, p_party_size, v_slot);

    if v_ids is null then
      raise exception 'Ten termin właśnie się zajął. Wybierz inną godzinę.';
    end if;

    begin
      insert into table_holds (reservation_id, table_id, slot)
      select v_res_id, t.table_id, v_slot
      from unnest(v_ids) as t(table_id);
      exit;
    exception
      when exclusion_violation then
        if v_attempt >= 5 then
          raise exception 'Ten termin właśnie się zajął. Wybierz inną godzinę.';
        end if;
    end;
  end loop;

  if nullif(btrim(p_diet), '') is not null then
    insert into reservation_diets (reservation_id, details, delete_after)
    values (v_res_id, btrim(p_diet), v_ends + interval '30 days');
  end if;

  return v_res_id;
end;
$$;

-- ---------------------------------------------------------------
-- Odwołanie rezerwacji przez gościa
-- ---------------------------------------------------------------

create or replace function public.cancel_reservation(p_reservation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update reservations
  set status = 'cancelled'
  where id = p_reservation_id
    and user_id = auth.uid()
    and status = 'confirmed'
    and starts_at > now();

  if not found then
    raise exception 'Tej rezerwacji nie da się już odwołać.';
  end if;

  update table_holds set active = false where reservation_id = p_reservation_id;
end;
$$;

-- ---------------------------------------------------------------
-- Uprawnienia do funkcji
-- ---------------------------------------------------------------

revoke execute on function public.available_slots(uuid, date, integer) from public;
revoke execute on function public.book_table(uuid, timestamptz, integer, public.reservation_occasion, text, text, boolean) from public, anon;
revoke execute on function public.cancel_reservation(uuid) from public, anon;

grant execute on function public.available_slots(uuid, date, integer) to anon, authenticated;
grant execute on function public.book_table(uuid, timestamptz, integer, public.reservation_occasion, text, text, boolean) to authenticated;
grant execute on function public.cancel_reservation(uuid) to authenticated;
