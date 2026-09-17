-- Table · migracja 0008
-- Wybór miasta i ranking najlepszej kuchni w okolicy lokalu.

drop function if exists public.search_restaurants(double precision, double precision, numeric, text, text);

create or replace function public.search_restaurants(
  p_lat        double precision,
  p_lng        double precision,
  p_radius_km  numeric default 10,
  p_cuisine    text default null,
  p_sort       text default 'ranking',
  p_city       text default null
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
    where (
        case
          when p_city is not null then r.city = p_city
          else st_dwithin(r.location, o.g, least(greatest(p_radius_km, 1), 50) * 1000)
        end
      )
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

-- Miasta z lokalami i ich środek, używany, gdy gość nie udostępnia lokalizacji.
create or replace function public.restaurant_cities()
returns table (city text, restaurants integer, lat double precision, lng double precision)
language sql
stable
set search_path = public, extensions
as $$
  select
    r.city,
    count(*)::integer,
    st_y(st_centroid(st_collect(r.location::geometry))),
    st_x(st_centroid(st_collect(r.location::geometry)))
  from restaurants r
  group by r.city
  order by count(*) desc, r.city
$$;

-- Ranking najlepszej kuchni w promieniu od lokalu, bez względu na rodzaj kuchni.
-- Zwraca czołówkę i sam lokal, nawet jeśli jest poza czołówką albo nie ma ocen.
create or replace function public.nearby_ranking(
  p_restaurant_id  uuid,
  p_radius_km      numeric default 10,
  p_limit          integer default 5
)
returns table (
  rank_position     integer,
  id                uuid,
  name              text,
  cuisine           text,
  food_score        numeric,
  food_avg          numeric,
  verified_reviews  integer,
  distance_m        double precision,
  is_current        boolean
)
language sql
stable
set search_path = public, extensions
as $$
  with origin as (
    select st_y(location::geometry) as lat, st_x(location::geometry) as lng
    from restaurants
    where restaurants.id = p_restaurant_id
  ),
  results as (
    select s.*
    from origin o
    cross join lateral public.search_restaurants(o.lat, o.lng, p_radius_km, null, 'ranking', null) s
  ),
  ranked as (
    select (row_number() over (order by res.food_score desc, res.distance_m))::integer as pos, res.*
    from results res
    where res.food_score is not null
  )
  select k.pos, k.id, k.name, k.cuisine, k.food_score, k.food_avg, k.verified_reviews, k.distance_m,
         k.id = p_restaurant_id
  from ranked k
  where k.pos <= least(greatest(p_limit, 1), 20) or k.id = p_restaurant_id
  union all
  select null, res.id, res.name, res.cuisine, null, null, 0, 0, true
  from results res
  where res.id = p_restaurant_id and res.food_score is null
  order by 1 nulls last
$$;

revoke execute on function public.search_restaurants(double precision, double precision, numeric, text, text, text) from public;
revoke execute on function public.restaurant_cities() from public;
revoke execute on function public.nearby_ranking(uuid, numeric, integer) from public;

grant execute on function public.search_restaurants(double precision, double precision, numeric, text, text, text) to anon, authenticated;
grant execute on function public.restaurant_cities() to anon, authenticated;
grant execute on function public.nearby_ranking(uuid, numeric, integer) to anon, authenticated;
