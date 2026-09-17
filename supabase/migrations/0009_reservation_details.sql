-- Table · migracja 0009
-- Szczegóły rezerwacji z położeniem lokalu. Ranking w okolicy lokalu usunięty z aplikacji.

drop function if exists public.nearby_ranking(uuid, numeric, integer);

create or replace function public.reservation_details(p_reservation_id uuid)
returns table (
  id               uuid,
  restaurant_id    uuid,
  restaurant_name  text,
  address          text,
  city             text,
  phone            text,
  lat              double precision,
  lng              double precision,
  party_size       smallint,
  starts_at        timestamptz,
  ends_at          timestamptz,
  status           public.reservation_status,
  occasion         public.reservation_occasion,
  message          text,
  diet             text,
  reviewed         boolean
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select
    r.id, r.restaurant_id, s.name, s.address, s.city, s.phone,
    st_y(s.location::geometry), st_x(s.location::geometry),
    r.party_size, r.starts_at, r.ends_at, r.status, r.occasion, r.message,
    d.details,
    exists (select 1 from reviews rv where rv.reservation_id = r.id)
  from reservations r
  join restaurants s on s.id = r.restaurant_id
  left join reservation_diets d on d.reservation_id = r.id
  where r.id = p_reservation_id
    and r.user_id = auth.uid()
$$;

revoke execute on function public.reservation_details(uuid) from public, anon;
grant execute on function public.reservation_details(uuid) to authenticated;
