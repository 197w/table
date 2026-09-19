-- Table · migracja 0014
-- Lista lokali w panelu zwraca też logo, żeby pokazać je przy wyborze lokalu.

drop function if exists public.panel_my_restaurants();

create or replace function public.panel_my_restaurants()
returns table (
  id           uuid,
  name         text,
  city         text,
  plan         public.restaurant_plan,
  role         public.staff_role,
  timezone     text,
  logo_url     text
)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.name, r.city, r.plan, s.role, r.timezone, r.logo_url
  from restaurant_staff s
  join restaurants r on r.id = s.restaurant_id
  where s.user_id = auth.uid()
  order by r.name
$$;

revoke execute on function public.panel_my_restaurants() from public, anon;
grant execute on function public.panel_my_restaurants() to authenticated;
