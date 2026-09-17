-- Table · migracja 0004
-- Wyszukiwanie lokali, ranking kuchni, opinie, zdarzenia i usuwanie konta.

-- ---------------------------------------------------------------
-- Wyszukiwanie w okolicy z rankingiem kuchni
-- wynik = (v / (v + m)) * R + (m / (v + m)) * C,  m = 10
-- Liczą się tylko zweryfikowane opinie.
-- ---------------------------------------------------------------

create or replace function public.search_restaurants(
  p_lat        double precision,
  p_lng        double precision,
  p_radius_km  numeric default 10,
  p_cuisine    text default null,
  p_sort       text default 'ranking'
)
returns table (
  id                  uuid,
  name                text,
  cuisine             text,
  price_level         smallint,
  address             text,
  city                text,
  plan                public.restaurant_plan,
  is_example          boolean,
  distance_m          double precision,
  verified_reviews    integer,
  unverified_reviews  integer,
  food_avg            numeric,
  service_avg         numeric,
  ambience_avg        numeric,
  food_score          numeric
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with origin as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  ),
  nearby as (
    select r.*, st_distance(r.location, o.g) as dist
    from restaurants r, origin o
    where st_dwithin(r.location, o.g, least(greatest(p_radius_km, 1), 50) * 1000)
      and (p_cuisine is null or r.cuisine = p_cuisine)
  ),
  stats as (
    select
      rv.restaurant_id,
      count(*) filter (where rv.verification <> 'none')          as verified,
      count(*) filter (where rv.verification = 'none')           as unverified,
      avg(rv.food) filter (where rv.verification <> 'none')      as food_avg,
      avg(rv.service) filter (where rv.verification <> 'none')   as service_avg,
      avg(rv.ambience) filter (where rv.verification <> 'none')  as ambience_avg
    from reviews rv
    join nearby n on n.id = rv.restaurant_id
    group by rv.restaurant_id
  ),
  region as (
    select coalesce(sum(s.food_avg * s.verified) / nullif(sum(s.verified), 0), 4.0) as c
    from stats s
  ),
  scored as (
    select
      n.id, n.name, n.cuisine, n.price_level, n.address, n.city, n.plan, n.is_example,
      n.dist,
      coalesce(s.verified, 0)::integer   as verified,
      coalesce(s.unverified, 0)::integer as unverified,
      round(s.food_avg, 2)     as food_avg,
      round(s.service_avg, 2)  as service_avg,
      round(s.ambience_avg, 2) as ambience_avg,
      case
        when coalesce(s.verified, 0) = 0 then null
        else round(
          (s.verified::numeric / (s.verified + 10)) * s.food_avg
          + (10::numeric / (s.verified + 10)) * region.c, 3)
      end as score
    from nearby n
    left join stats s on s.restaurant_id = n.id
    cross join region
  )
  select
    sc.id, sc.name, sc.cuisine, sc.price_level, sc.address, sc.city, sc.plan, sc.is_example,
    sc.dist, sc.verified, sc.unverified, sc.food_avg, sc.service_avg, sc.ambience_avg, sc.score
  from scored sc
  order by
    (case when p_sort = 'distance' then sc.dist end) asc nulls last,
    sc.score desc nulls last,
    sc.dist asc
  limit 100
$$;

-- ---------------------------------------------------------------
-- Podsumowanie ocen jednego lokalu
-- ---------------------------------------------------------------

create or replace function public.restaurant_rating(p_restaurant_id uuid)
returns table (
  verified_reviews    integer,
  unverified_reviews  integer,
  food_avg            numeric,
  service_avg         numeric,
  ambience_avg        numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select
    (count(*) filter (where verification <> 'none'))::integer,
    (count(*) filter (where verification = 'none'))::integer,
    round(avg(food) filter (where verification <> 'none'), 2),
    round(avg(service) filter (where verification <> 'none'), 2),
    round(avg(ambience) filter (where verification <> 'none'), 2)
  from reviews
  where restaurant_id = p_restaurant_id
$$;

-- ---------------------------------------------------------------
-- Lista opinii bez identyfikatorów autorów
-- ---------------------------------------------------------------

create or replace function public.restaurant_reviews(
  p_restaurant_id  uuid,
  p_limit          integer default 20,
  p_offset         integer default 0
)
returns table (
  id            uuid,
  food          smallint,
  service       smallint,
  ambience      smallint,
  body          text,
  verification  public.review_verification,
  author        text,
  is_mine       boolean,
  created_at    timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    rv.id, rv.food, rv.service, rv.ambience, rv.body, rv.verification,
    coalesce(nullif(btrim(p.first_name), ''), rv.seed_author, 'Gość'),
    coalesce(rv.user_id = auth.uid(), false),
    rv.created_at
  from reviews rv
  left join profiles p on p.id = rv.user_id
  where rv.restaurant_id = p_restaurant_id
  order by (rv.verification <> 'none') desc, rv.created_at desc
  limit least(greatest(p_limit, 1), 50)
  offset greatest(p_offset, 0)
$$;

-- ---------------------------------------------------------------
-- Dodawanie opinii
-- Z rezerwacją: opinia zweryfikowana, po zakończeniu wizyty.
-- Bez rezerwacji: opinia niezweryfikowana, jedna na lokal.
-- Weryfikacja paragonem pojawi się w kolejnej wersji.
-- ---------------------------------------------------------------

create or replace function public.submit_review(
  p_restaurant_id   uuid,
  p_food            integer,
  p_service         integer,
  p_ambience        integer,
  p_body            text default null,
  p_reservation_id  uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid           uuid := auth.uid();
  v_verification  public.review_verification := 'none';
  v_id            uuid;
begin
  if v_uid is null then
    raise exception 'Zaloguj się, żeby dodać opinię.';
  end if;

  if coalesce(p_food, 0) not between 1 and 5
     or coalesce(p_service, 0) not between 1 and 5
     or coalesce(p_ambience, 0) not between 1 and 5 then
    raise exception 'Oceń kuchnię, obsługę i atmosferę w skali od 1 do 5.';
  end if;

  if p_reservation_id is not null then
    perform 1
    from reservations r
    where r.id = p_reservation_id
      and r.user_id = v_uid
      and r.restaurant_id = p_restaurant_id
      and r.status in ('confirmed', 'seated', 'completed')
      and r.ends_at < now();

    if not found then
      raise exception 'Opinię o wizycie możesz dodać dopiero po jej zakończeniu.';
    end if;

    v_verification := 'reservation';
  end if;

  insert into reviews (restaurant_id, user_id, reservation_id, food, service, ambience, body, verification)
  values (p_restaurant_id, v_uid, p_reservation_id, p_food, p_service, p_ambience,
          nullif(btrim(p_body), ''), v_verification)
  returning id into v_id;

  return v_id;
exception
  when unique_violation then
    raise exception 'Masz już opinię o tej wizycie albo o tym lokalu.';
end;
$$;

create or replace function public.my_reviewed_reservations()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select reservation_id from reviews
  where user_id = auth.uid() and reservation_id is not null
$$;

-- ---------------------------------------------------------------
-- Zdarzenia: wyświetlenie profilu i kliknięcie „Zadzwoń”
-- ---------------------------------------------------------------

create or replace function public.log_restaurant_event(p_restaurant_id uuid, p_kind text)
returns void
language sql
security definer
set search_path = public
as $$
  insert into restaurant_events (restaurant_id, kind, user_id)
  select p_restaurant_id, p_kind, auth.uid()
  where p_kind in ('view', 'call_click')
    and exists (select 1 from restaurants where id = p_restaurant_id)
$$;

-- ---------------------------------------------------------------
-- Usuwanie konta w aplikacji, wymagane przez Apple
-- ---------------------------------------------------------------

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Zaloguj się, żeby usunąć konto.';
  end if;

  delete from auth.users where id = auth.uid();
end;
$$;

-- ---------------------------------------------------------------
-- Uprawnienia do funkcji
-- ---------------------------------------------------------------

revoke execute on function public.search_restaurants(double precision, double precision, numeric, text, text) from public;
revoke execute on function public.restaurant_rating(uuid) from public;
revoke execute on function public.restaurant_reviews(uuid, integer, integer) from public;
revoke execute on function public.log_restaurant_event(uuid, text) from public;
revoke execute on function public.submit_review(uuid, integer, integer, integer, text, uuid) from public, anon;
revoke execute on function public.my_reviewed_reservations() from public, anon;
revoke execute on function public.delete_my_account() from public, anon;

grant execute on function public.search_restaurants(double precision, double precision, numeric, text, text) to anon, authenticated;
grant execute on function public.restaurant_rating(uuid) to anon, authenticated;
grant execute on function public.restaurant_reviews(uuid, integer, integer) to anon, authenticated;
grant execute on function public.log_restaurant_event(uuid, text) to anon, authenticated;
grant execute on function public.submit_review(uuid, integer, integer, integer, text, uuid) to authenticated;
grant execute on function public.my_reviewed_reservations() to authenticated;
grant execute on function public.delete_my_account() to authenticated;
