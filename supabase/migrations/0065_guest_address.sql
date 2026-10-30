-- 0065: adres gościa w ustawieniach aplikacji Table (do zamówień z dostawą) widoczny w panelu w „Baza klientów”.

alter table public.profiles
  add column if not exists address_street      text check (address_street is null or char_length(address_street) <= 120),
  add column if not exists address_house       text check (address_house is null or char_length(address_house) <= 20),
  add column if not exists address_building    text check (address_building is null or char_length(address_building) <= 200),
  add column if not exists address_entry_code  text check (address_entry_code is null or char_length(address_entry_code) <= 20),
  add column if not exists address_city        text check (address_city is null or char_length(address_city) <= 80),
  add column if not exists address_postcode    text check (address_postcode is null or address_postcode ~ '^[0-9]{2}-[0-9]{3}$'),
  add column if not exists address_updated_at  timestamptz;

-- Adres z aplikacji gościa dla karty klienta w panelu. Tylko gość, który ma rezerwację albo zamówienie w tym lokalu
-- (klucz klienta jak w panel_customers: telefon z konta albo identyfikator konta). Null: brak adresu.
create or replace function public.panel_customer_app_address(p_restaurant_id uuid, p_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v profiles%rowtype;
begin
  perform private.require_permission(p_restaurant_id, 'customers');
  select p.* into v
  from profiles p
  join auth.users u on u.id = p.id
  where (p.id::text = p_key or 'tel:' || private.customer_phone_key(u.phone) = p_key)
    and p.address_street is not null
    and (
      exists (select 1 from reservations r where r.restaurant_id = p_restaurant_id and r.user_id = p.id)
      or exists (select 1 from orders o where o.restaurant_id = p_restaurant_id and o.guest_id = p.id)
    )
  order by p.address_updated_at desc nulls last
  limit 1;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'street', v.address_street,
    'house', v.address_house,
    'building', v.address_building,
    'entry_code', v.address_entry_code,
    'city', v.address_city,
    'postcode', v.address_postcode,
    'updated_at', v.address_updated_at
  );
end;
$$;

revoke execute on function public.panel_customer_app_address(uuid, text) from public, anon;
grant execute on function public.panel_customer_app_address(uuid, text) to authenticated;
