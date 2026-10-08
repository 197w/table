-- Nowy wygląd listy lokali w aplikacji Table: zdjęcie na całą szerokość karty i wyszukiwanie dań.
--
-- restaurants.cover_url: zdjęcie lokalu na liście (panel → „Dane lokalu” → „Zdjęcie na liście lokali”).
-- Bez niego lista pokazuje pierwsze zdjęcie dania z menu, a bez zdjęć kartę z ikoną kuchni.
-- search_restaurants szuka też po kuchni i po nazwach dań („pizza”, „pierogi”), zwraca zdjęcie,
-- dostawę i odbiór (szybkie filtry) oraz pierwsze pasujące danie.

alter table public.restaurants
  add column cover_url text check (char_length(cover_url) <= 500);

grant select (cover_url) on public.restaurants to anon, authenticated;
grant update (cover_url) on public.restaurants to authenticated;

drop function public.search_restaurants(double precision, double precision, numeric, text, text, text, text);

create function public.search_restaurants(
  p_lat        double precision,
  p_lng        double precision,
  p_radius_km  numeric default 10,
  p_cuisine    text default null,
  p_sort       text default 'ranking',
  p_city       text default null,
  p_query      text default null
)
returns table (
  id uuid, name text, cuisine text, price_level smallint, address text, city text, plan restaurant_plan,
  is_example boolean, logo_url text, distance_m double precision, verified_reviews integer,
  unverified_reviews integer, food_avg numeric, service_avg numeric, ambience_avg numeric, food_score numeric,
  cover_url text, delivery_enabled boolean, pickup_enabled boolean, matched_dish text
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
    select r.*, st_distance(r.location, o.g) as dist, dish.name as dish
    from restaurants r
    cross join origin o
    cross join q
    -- Pierwsze danie z menu pasujące do wpisanej frazy.
    left join lateral (
      select i.name
      from menu_items i
      join menu_sections s on s.id = i.section_id
      where q.text is not null and s.restaurant_id = r.id
        and unaccent(i.name) ilike '%' || unaccent(q.text) || '%'
      order by s.position, i.position
      limit 1
    ) dish on true
    where r.listed
      and (
        case
          when q.text is not null then
            unaccent(r.name) ilike '%' || unaccent(q.text) || '%'
            or unaccent(r.city) ilike '%' || unaccent(q.text) || '%'
            or r.cuisine ilike '%' || lower(unaccent(q.text)) || '%'
            or dish.name is not null
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
      coalesce(
        n.cover_url,
        (
          select i.photo_url
          from menu_items i
          join menu_sections ms on ms.id = i.section_id
          where ms.restaurant_id = n.id and i.photo_url is not null and i.available
          order by ms.position, i.position
          limit 1
        )
      ) as cover,
      n.delivery_enabled, n.pickup_enabled, n.dish,
      case when (select text from q) is null then 4
           when unaccent(n.name) ilike unaccent((select text from q)) || '%' then 0
           when unaccent(n.name) ilike '%' || unaccent((select text from q)) || '%' then 1
           when n.cuisine ilike '%' || lower(unaccent((select text from q))) || '%' then 2
           when n.dish is not null then 3
           else 4
      end as match_rank
    from nearby n
    left join stats s on s.restaurant_id = n.id
    cross join region
  )
  select
    sc.id, sc.name, sc.cuisine, sc.price_level, sc.address, sc.city, sc.plan, sc.is_example, sc.logo_url,
    sc.dist, sc.verified, sc.unverified, sc.food_avg, sc.service_avg, sc.ambience_avg, sc.score,
    sc.cover, sc.delivery_enabled, sc.pickup_enabled, sc.dish
  from scored sc
  order by
    sc.match_rank asc,
    (case when p_sort = 'distance' then sc.dist end) asc nulls last,
    sc.score desc nulls last,
    sc.dist asc
  limit 100
$$;

grant execute on function public.search_restaurants(double precision, double precision, numeric, text, text, text, text)
  to anon, authenticated;
