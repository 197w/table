-- Baza klientów: ten sam numer telefonu to jeden klient.
-- Wcześniej klucz klienta brał najpierw konto z aplikacji (user_id), więc ten sam numer z aplikacji i z panelu
-- (albo z rezerwacji telefonicznej) dawał dwóch klientów. Teraz najpierw telefon (ostatnie 9 cyfr, numer
-- z konta w aplikacji ma pierwszeństwo przed wpisanym), potem konto, na końcu imię.
--
-- restaurant_customers: dane klienta z zamówień na wynos (imię, firma, NIP, adres), dopisywane same przy
-- przyjętym zamówieniu, jeśli klienta nie ma w bazie (a gdy jest: nowy adres i brakujące dane).
-- Klient z bazy jest na liście „Klienci” także bez dostarczonego jeszcze zamówienia.

create table public.restaurant_customers (
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  phone_key      text not null check (phone_key ~ '^[0-9]{9}$'),
  phone          text,
  name           text,
  company        text,
  nip            text,
  street         text,
  house          text,
  city           text,
  -- Adres w jednym napisie (zamówienie z aplikacji Table nie ma osobnych pól).
  address        text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  primary key (restaurant_id, phone_key)
);

alter table public.restaurant_customers enable row level security;
revoke all on public.restaurant_customers from anon, authenticated;

-- Ostatnie 9 cyfr numeru albo null, gdy cyfr jest mniej (np. samo „+48”).
create or replace function private.customer_phone_key(p_phone text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when char_length(k) = 9 then k end from (select private.phone_key(p_phone) as k) x
$$;

create or replace function private.customer_key(p_user uuid, p_phone text, p_name text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    'tel:' || coalesce(
      private.customer_phone_key((select u.phone from auth.users u where u.id = p_user)),
      private.customer_phone_key(p_phone)
    ),
    p_user::text,
    'imie:' || nullif(lower(btrim(p_name)), '')
  )
$$;

-- Dopisuje albo uzupełnia klienta z danych zamówienia na wynos.
create or replace function private.remember_customer(p_order public.orders)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key  text := private.customer_phone_key(p_order.customer_phone);
begin
  if v_key is null then
    return;
  end if;
  insert into public.restaurant_customers as c (
    restaurant_id, phone_key, phone, name, company, nip, street, house, city, address
  )
  values (
    p_order.restaurant_id, v_key, nullif(btrim(p_order.customer_phone), ''),
    nullif(btrim(case when p_order.customer_company is not null and p_order.customer_name = p_order.customer_company
                      then null else p_order.customer_name end), ''),
    p_order.customer_company, p_order.customer_nip,
    p_order.address_street, p_order.address_house, p_order.address_city, p_order.delivery_address
  )
  on conflict (restaurant_id, phone_key) do update
  set phone = coalesce(excluded.phone, c.phone),
      name = coalesce(excluded.name, c.name),
      company = coalesce(excluded.company, c.company),
      nip = coalesce(excluded.nip, c.nip),
      -- Adres z ostatniego zamówienia z dostawą.
      street = case when excluded.address is not null then excluded.street else c.street end,
      house = case when excluded.address is not null then excluded.house else c.house end,
      city = case when excluded.address is not null then excluded.city else c.city end,
      address = coalesce(excluded.address, c.address),
      updated_at = now();
end;
$$;

create or replace function private.orders_remember_customer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.remember_customer(new);
  return new;
end;
$$;

-- Przyjęte (albo złożone gotówką) zamówienie na wynos i każda zmiana danych klienta. Szkic z panelu i zamówienie
-- czekające na płatność kartą jeszcze nie.
create trigger orders_remember_customer
  after insert or update of fulfillment, customer_name, customer_phone, customer_company, customer_nip,
    address_street, address_house, address_city, delivery_address
  on public.orders
  for each row
  when (new.kind <> 'dine_in' and new.customer_phone is not null
        and new.fulfillment not in ('draft', 'awaiting_payment', 'rejected', 'cancelled'))
  execute function private.orders_remember_customer();

-- Klienci z dotychczasowych zamówień, od najstarszego, żeby został najnowszy adres.
do $$
declare
  v_order  public.orders%rowtype;
begin
  for v_order in
    select * from public.orders
    where kind <> 'dine_in' and customer_phone is not null
      and fulfillment not in ('draft', 'awaiting_payment', 'rejected', 'cancelled')
    order by opened_at
  loop
    perform private.remember_customer(v_order);
  end loop;
end;
$$;

-- Notatki przypięte do konta z aplikacji przechodzą na numer telefonu (nowy klucz tego samego klienta).
update public.customer_notes n
set customer_key = private.customer_key(u.id, null, null)
from auth.users u
where n.customer_key = u.id::text
  and private.customer_key(u.id, null, null) like 'tel:%';

drop function public.panel_customers(uuid);

create function public.panel_customers(p_restaurant_id uuid)
returns table (
  key text, name text, phone text, from_app boolean, visits integer, reservations integer, no_shows integer,
  cancelled integer, orders integer, spent_grosze bigint, first_seen timestamptz, last_visit timestamptz,
  next_reservation timestamptz, company text, nip text, address text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform private.require_permission(p_restaurant_id, 'customers');

  return query
  with events as (
    select
      coalesce(
        'tel:' || coalesce(private.customer_phone_key(u.phone), private.customer_phone_key(r.guest_phone)),
        r.user_id::text,
        'imie:' || nullif(lower(btrim(r.guest_name)), '')
      ) as key,
      r.user_id is not null as from_app,
      coalesce(nullif(btrim(r.guest_name), ''), nullif(btrim(p.full_name), ''), nullif(btrim(p.first_name), '')) as name,
      coalesce(
        nullif(btrim(r.guest_phone), ''),
        case when u.phone is not null and u.phone <> '' then '+' || u.phone end
      ) as phone,
      r.starts_at as at,
      'reservation'::text as kind,
      r.status::text as status,
      (
        select coalesce(sum(i.unit_price_grosze * i.quantity), 0)
        from orders o
        join order_items i on i.order_id = o.id and i.status <> 'cancelled'
        where o.reservation_id = r.id and o.status = 'paid'
      )::bigint as spent
    from reservations r
    left join profiles p on p.id = r.user_id
    left join auth.users u on u.id = r.user_id
    where r.restaurant_id = p_restaurant_id and r.source <> 'block'
    union all
    select
      coalesce(
        'tel:' || coalesce(private.customer_phone_key(u.phone), private.customer_phone_key(o.customer_phone)),
        o.guest_id::text,
        'imie:' || nullif(lower(btrim(o.customer_name)), '')
      ),
      o.guest_id is not null,
      nullif(btrim(o.customer_name), ''),
      nullif(btrim(o.customer_phone), ''),
      o.opened_at,
      'order'::text,
      o.fulfillment,
      (
        (select coalesce(sum(i.unit_price_grosze * i.quantity), 0)
         from order_items i where i.order_id = o.id and i.status <> 'cancelled')
        + o.delivery_fee_grosze
      )::bigint
    from orders o
    left join auth.users u on u.id = o.guest_id
    where o.restaurant_id = p_restaurant_id and o.kind <> 'dine_in' and o.fulfillment = 'delivered'
    union all
    -- Klient dopisany z zamówienia (np. jeszcze w drodze): jest w bazie od razu.
    select
      'tel:' || c.phone_key, false, coalesce(c.name, c.company), c.phone, c.created_at, 'base'::text, null::text,
      0::bigint
    from restaurant_customers c
    where c.restaurant_id = p_restaurant_id
  ),
  grouped as (
    select
      e.key,
      coalesce((array_agg(e.name order by e.at desc) filter (where e.name is not null))[1], 'Gość') as name,
      (array_agg(e.phone order by e.at desc) filter (where e.phone is not null))[1] as phone,
      bool_or(e.from_app) as from_app,
      (count(*) filter (where e.kind = 'reservation' and e.status in ('seated', 'completed')))::integer as visits,
      (count(*) filter (where e.kind = 'reservation'))::integer as reservations,
      (count(*) filter (where e.kind = 'reservation' and e.status = 'no_show'))::integer as no_shows,
      (count(*) filter (where e.kind = 'reservation' and e.status = 'cancelled'))::integer as cancelled,
      (count(*) filter (where e.kind = 'order'))::integer as orders,
      coalesce(sum(e.spent), 0)::bigint as spent,
      min(e.at) as first_seen,
      max(e.at) filter (where (e.kind = 'reservation' and e.status in ('seated', 'completed')) or e.kind = 'order')
        as last_visit,
      min(e.at) filter (where e.kind = 'reservation' and e.status = 'confirmed' and e.at > now()) as next_reservation
    from events e
    where e.key is not null
    group by e.key
  )
  select
    g.key, g.name, g.phone, g.from_app, g.visits, g.reservations, g.no_shows, g.cancelled, g.orders, g.spent,
    g.first_seen, g.last_visit, g.next_reservation,
    c.company, c.nip,
    coalesce(
      nullif(concat_ws(', ', nullif(btrim(concat_ws(' ', c.street, c.house)), ''), c.city), ''),
      c.address
    )
  from grouped g
  left join restaurant_customers c on c.restaurant_id = p_restaurant_id and 'tel:' || c.phone_key = g.key
  order by g.last_visit desc nulls last, g.name;
end;
$$;

revoke execute on function public.panel_customers(uuid) from public, anon;
revoke execute on function private.remember_customer(public.orders) from public, anon, authenticated;
revoke execute on function private.orders_remember_customer() from public, anon, authenticated;
grant execute on function public.panel_customers(uuid) to authenticated;
grant execute on function private.customer_phone_key(text) to authenticated;
grant execute on function private.customer_key(uuid, text, text) to authenticated;
