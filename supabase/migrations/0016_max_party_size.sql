-- Table · migracja 0016
-- Limit osób w jednej rezerwacji z aplikacji ustawiany przez lokal (wcześniej na stałe 12).

alter table public.restaurants
  add column max_party_size smallint not null default 12 check (max_party_size between 1 and 30);

grant update (max_party_size) on public.restaurants to authenticated;

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
    select id, timezone, slot_interval_min, max_party_size
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
  where p_party_size between 1 and (select max_party_size from r)
    and s.starts_at > now() + interval '30 minutes'
    and private.find_tables(
          p_restaurant_id,
          p_party_size,
          tstzrange(s.starts_at, s.starts_at + make_interval(mins => s.visit + s.cleanup))
        ) is not null
  order by s.starts_at
$$;

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

  select id, timezone, slot_interval_min, plan, max_party_size into v_rest
  from restaurants where id = p_restaurant_id;

  if not found then
    raise exception 'Nie znaleziono restauracji.';
  end if;

  if p_party_size is null or p_party_size not between 1 and v_rest.max_party_size then
    raise exception 'Rezerwacja w aplikacji obejmuje od 1 do % osób. Większą grupę umów telefonicznie.', v_rest.max_party_size;
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
