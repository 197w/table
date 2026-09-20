-- Table · migracja 0018
-- Wyszukiwanie lokalu po nazwie. Z frazą szukamy w całym kraju, bez niej działa jak dotąd:
-- miasto albo promień od punktu.

drop function if exists public.search_restaurants(double precision, double precision, numeric, text, text, text);

create or replace function public.search_restaurants(
  p_lat        double precision,
  p_lng        double precision,
  p_radius_km  numeric default 10,
  p_cuisine    text default null,
  p_sort       text default 'ranking',
  p_city       text default null,
  p_query      text default null
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
  logo_url            text,
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
  with q as (
    select nullif(btrim(p_query), '') as text
  ),
  origin as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  ),
  nearby as (
    select r.*, st_distance(r.location, o.g) as dist
    from restaurants r, origin o, q
    where (
        case
          when q.text is not null then
            r.name ilike '%' || q.text || '%' or r.city ilike '%' || q.text || '%'
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
      n.id, n.name, n.cuisine, n.price_level, n.address, n.city, n.plan, n.is_example, n.logo_url,
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
      end as score,
      -- Lokal zaczynający się od wpisanej frazy jest najbliżej tego, czego gość szuka.
      case when (select text from q) is null then 2
           when n.name ilike (select text from q) || '%' then 0
           when n.name ilike '%' || (select text from q) || '%' then 1
           else 2
      end as match_rank
    from nearby n
    left join stats s on s.restaurant_id = n.id
    cross join region
  )
  select
    sc.id, sc.name, sc.cuisine, sc.price_level, sc.address, sc.city, sc.plan, sc.is_example, sc.logo_url,
    sc.dist, sc.verified, sc.unverified, sc.food_avg, sc.service_avg, sc.ambience_avg, sc.score
  from scored sc
  order by
    sc.match_rank asc,
    (case when p_sort = 'distance' then sc.dist end) asc nulls last,
    sc.score desc nulls last,
    sc.dist asc
  limit 100
$$;

revoke execute on function public.search_restaurants(double precision, double precision, numeric, text, text, text, text) from public;
grant execute on function public.search_restaurants(double precision, double precision, numeric, text, text, text, text) to anon, authenticated;
