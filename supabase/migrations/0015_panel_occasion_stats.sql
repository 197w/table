-- Table · migracja 0015
-- Statystyki okazji rezerwacji w panelu (urodziny, rocznice, randki...).

create or replace function public.panel_occasion_stats(
  p_restaurant_id  uuid,
  p_days           integer default 30
)
returns table (
  occasion      public.reservation_occasion,
  reservations  integer,
  covers        integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_days integer := least(greatest(coalesce(p_days, 30), 1), 366);
begin
  perform private.require_staff(p_restaurant_id);

  return query
  select r.occasion, count(*)::integer, coalesce(sum(r.party_size), 0)::integer
  from reservations r
  where r.restaurant_id = p_restaurant_id
    and r.occasion is not null
    and r.status in ('confirmed', 'seated', 'completed')
    and r.starts_at >= now() - make_interval(days => v_days)
    and r.starts_at < now() + interval '1 day'
  group by r.occasion
  order by count(*) desc;
end;
$$;

revoke execute on function public.panel_occasion_stats(uuid, integer) from public, anon;
grant execute on function public.panel_occasion_stats(uuid, integer) to authenticated;
