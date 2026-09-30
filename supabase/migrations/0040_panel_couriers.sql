-- Table · migracja 0040
-- Dostawcy na zmianie dla panelu (zakładka „Dostawy”): kolejka i kto jest w kursie. Pozwala ręcznie zmienić dostawcę.

create or replace function public.panel_couriers(p_restaurant_id uuid)
returns table (member_id uuid, name text, waiting_since timestamptz, busy boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform private.require_permission(p_restaurant_id, 'orders');
  return query select q.member_id, q.name, q.waiting_since, q.busy from private.courier_queue(p_restaurant_id) q;
end;
$$;

revoke execute on function public.panel_couriers(uuid) from public, anon;
grant execute on function public.panel_couriers(uuid) to authenticated;
