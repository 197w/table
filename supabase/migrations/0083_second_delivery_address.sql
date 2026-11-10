-- 0083: Drugi adres dostawy i adres domyślny (10.11.2026, prośba użytkownika).
-- Gość ma w Koncie → „Adresy dostawy” najwyżej dwa adresy (pierwszy w dotychczasowych kolumnach `address_*`, drugi
-- w `address2_*`) i wybiera domyślny (`address_default`: 1 albo 2). Zamówienie z dostawą uzupełnia się z domyślnego,
-- a w koszyku można przełączyć na drugi. Lokal w „Baza klientów” widzi adres domyślny.

alter table public.profiles
  add column if not exists address2_street      text check (address2_street is null or char_length(address2_street) <= 120),
  add column if not exists address2_house       text check (address2_house is null or char_length(address2_house) <= 20),
  add column if not exists address2_building    text check (address2_building is null or char_length(address2_building) <= 200),
  add column if not exists address2_entry_code  text check (address2_entry_code is null or char_length(address2_entry_code) <= 20),
  add column if not exists address2_city        text check (address2_city is null or char_length(address2_city) <= 80),
  add column if not exists address2_postcode    text check (address2_postcode is null or address2_postcode ~ '^[0-9]{2}-[0-9]{3}$'),
  add column if not exists address_default      smallint not null default 1 check (address_default in (1, 2));

comment on column public.profiles.address_default is
  'Domyślny adres dostawy gościa: 1 (address_*) albo 2 (address2_*).';

grant update (
  address2_street, address2_house, address2_building, address2_entry_code, address2_city, address2_postcode,
  address_default
) on public.profiles to authenticated;

-- Baza klientów: adres domyślny gościa (drugi, gdy jest domyślny i wpisany; inaczej ten, który jest).
create or replace function public.panel_customer_app_address(p_restaurant_id uuid, p_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public'
as $$
declare
  v profiles%rowtype;
  v_second boolean;
begin
  perform private.require_permission(p_restaurant_id, 'customers');
  select p.* into v
  from profiles p
  join auth.users u on u.id = p.id
  where (p.id::text = p_key or 'tel:' || private.customer_phone_key(private.account_phone(u.id)) = p_key)
    and (p.address_street is not null or p.address2_street is not null)
    and (
      exists (select 1 from reservations r where r.restaurant_id = p_restaurant_id and r.user_id = p.id)
      or exists (select 1 from orders o where o.restaurant_id = p_restaurant_id and o.guest_id = p.id)
    )
  order by p.address_updated_at desc nulls last
  limit 1;
  if not found then
    return null;
  end if;
  v_second := v.address2_street is not null and (v.address_default = 2 or v.address_street is null);
  return jsonb_build_object(
    'street', case when v_second then v.address2_street else v.address_street end,
    'house', case when v_second then v.address2_house else v.address_house end,
    'building', case when v_second then v.address2_building else v.address_building end,
    'entry_code', case when v_second then v.address2_entry_code else v.address_entry_code end,
    'city', case when v_second then v.address2_city else v.address_city end,
    'postcode', case when v_second then v.address2_postcode else v.address_postcode end,
    'updated_at', v.address_updated_at
  );
end;
$$;

revoke execute on function public.panel_customer_app_address(uuid, text) from public, anon;
grant execute on function public.panel_customer_app_address(uuid, text) to authenticated;
