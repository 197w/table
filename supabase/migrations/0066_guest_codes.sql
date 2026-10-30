-- 0066: osobiste kody rabatowe gości. Lokal ustawia automatyczne kody (po zrealizowanej rezerwacji i po zweryfikowanej
-- opinii), gość widzi je w aplikacji Table w „Moje” → „Kody”. Kod pokazuje się dopiero po „Aktywuj” i działa
-- 15 minut (do pokazania kelnerowi); każda aktywacja daje nowy ciąg znaków, więc zrzutu ekranu nie da się przekazać
-- dalej. Kelner wpisuje go przy rachunku jak zwykły kod.

-- Zasady automatycznych kodów lokalu: jedna na zdarzenie.
create table if not exists public.guest_code_rules (
  restaurant_id     uuid not null references public.restaurants (id) on delete cascade,
  event             text not null check (event in ('reservation', 'review')),
  active            boolean not null default false,
  kind              text not null default 'percent' check (kind in ('percent', 'amount')),
  value             integer not null default 10 check (value > 0),
  min_total_grosze  integer check (min_total_grosze is null or min_total_grosze > 0),
  valid_days        integer not null default 30 check (valid_days between 1 and 365),
  updated_at        timestamptz not null default now(),
  primary key (restaurant_id, event),
  check (kind <> 'percent' or value between 1 and 100)
);
alter table public.guest_code_rules enable row level security;

-- Kody osobiste gości.
create table if not exists public.guest_codes (
  id                uuid primary key default gen_random_uuid(),
  restaurant_id     uuid not null references public.restaurants (id) on delete cascade,
  user_id           uuid not null references auth.users (id) on delete cascade,
  source            text not null check (source in ('reservation', 'review')),
  -- Rezerwacja albo opinia, za którą jest kod (jeden kod za jedno zdarzenie).
  source_id         uuid not null,
  kind              text not null check (kind in ('percent', 'amount')),
  value             integer not null check (value > 0),
  min_total_grosze  integer,
  expires_at        timestamptz not null,
  -- Ciąg znaków z ostatniej aktywacji; działa do active_until.
  code              text,
  activated_at      timestamptz,
  active_until      timestamptz,
  used_at           timestamptz,
  used_order_id     uuid references public.orders (id) on delete set null,
  created_at        timestamptz not null default now(),
  unique (source, source_id)
);
create index if not exists guest_codes_user on public.guest_codes (user_id, created_at desc);
create unique index if not exists guest_codes_active_code on public.guest_codes (restaurant_id, code) where code is not null;
alter table public.guest_codes enable row level security;

alter table public.orders add column if not exists guest_code_id uuid references public.guest_codes (id) on delete set null;

-- Minimalna kwota: dla kodu osobistego ustawia ją funkcja przy wpisaniu kodu, więc trigger jej nie zeruje.
create or replace function private.order_discount_min()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.discount_code_id is null then
    if new.guest_code_id is null then
      new.discount_min_grosze := null;
    end if;
  elsif tg_op = 'INSERT' or new.discount_code_id is distinct from old.discount_code_id then
    new.discount_min_grosze := (select c.min_total_grosze from public.discount_codes c where c.id = new.discount_code_id);
  end if;
  return new;
end;
$$;

-- Nadanie kodu za zdarzenie, jeśli lokal ma włączoną zasadę.
create or replace function private.issue_guest_code(p_restaurant_id uuid, p_user uuid, p_source text, p_source_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rule public.guest_code_rules;
begin
  if p_user is null then
    return;
  end if;
  select * into v_rule from public.guest_code_rules
  where restaurant_id = p_restaurant_id and event = p_source and active;
  if not found then
    return;
  end if;
  insert into public.guest_codes (restaurant_id, user_id, source, source_id, kind, value, min_total_grosze, expires_at)
  values (p_restaurant_id, p_user, p_source, p_source_id, v_rule.kind, v_rule.value, v_rule.min_total_grosze,
          now() + make_interval(days => v_rule.valid_days))
  on conflict (source, source_id) do nothing;
end;
$$;

create or replace function private.reservation_guest_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' and new.user_id is not null then
    perform private.issue_guest_code(new.restaurant_id, new.user_id, 'reservation', new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists reservations_guest_code on public.reservations;
create trigger reservations_guest_code
  after update of status on public.reservations
  for each row execute function private.reservation_guest_code();

-- Kod za opinię tylko za zweryfikowaną (rezerwacja albo paragon), żeby nie nagradzać fikcyjnych opinii.
create or replace function private.review_guest_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.user_id is not null and new.verification::text <> 'none'
     and (tg_op = 'INSERT' or old.verification::text = 'none') then
    perform private.issue_guest_code(new.restaurant_id, new.user_id, 'review', new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists reviews_guest_code on public.reviews;
create trigger reviews_guest_code
  after insert or update of verification on public.reviews
  for each row execute function private.review_guest_code();

-- Kod osobisty do wpisania przy rachunku: nowy przy każdej aktywacji, unikalny w lokalu.
create or replace function private.new_guest_code_text(p_restaurant_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
begin
  loop
    v_code := 'T-';
    for i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::integer, 1);
    end loop;
    exit when not exists (select 1 from public.guest_codes where restaurant_id = p_restaurant_id and code = v_code)
          and not exists (select 1 from public.discount_codes where restaurant_id = p_restaurant_id and code = v_code);
  end loop;
  return v_code;
end;
$$;

-- Lista kodów gościa w aplikacji. Ciąg znaków tylko dla aktywnego kodu.
create or replace function public.guest_my_codes()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', g.id,
    'restaurant_id', g.restaurant_id,
    'restaurant_name', r.name,
    'restaurant_logo', r.logo_url,
    'source', g.source,
    'kind', g.kind,
    'value', g.value,
    'min_total', g.min_total_grosze,
    'expires_at', g.expires_at,
    'created_at', g.created_at,
    'used_at', g.used_at,
    'active_until', case when g.used_at is null and g.active_until > now() then g.active_until end,
    'code', case when g.used_at is null and g.active_until > now() then g.code end
  ) order by (g.used_at is null and g.expires_at > now()) desc, g.created_at desc), '[]'::jsonb)
  from guest_codes g
  join restaurants r on r.id = g.restaurant_id
  where g.user_id = auth.uid()
    and g.created_at > now() - interval '180 days'
$$;

-- „Aktywuj”: nowy ciąg znaków ważny 15 minut.
create or replace function public.guest_activate_code(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v guest_codes%rowtype;
begin
  select * into v from guest_codes where id = p_id and user_id = auth.uid() for update;
  if not found then
    raise exception 'Nie znaleziono kodu.';
  end if;
  if v.used_at is not null then
    raise exception 'Ten kod został już wykorzystany.';
  end if;
  if v.expires_at <= now() then
    raise exception 'Ten kod już wygasł.';
  end if;
  if v.active_until is null or v.active_until <= now() then
    update guest_codes
    set code = private.new_guest_code_text(v.restaurant_id), activated_at = now(),
        active_until = least(now() + interval '15 minutes', v.expires_at)
    where id = p_id
    returning * into v;
  end if;
  return jsonb_build_object('code', v.code, 'active_until', v.active_until);
end;
$$;

-- Kod przy rachunku: najpierw kod osobisty gościa (aktywny), potem kod lokalu.
create or replace function public.panel_order_set_discount(p_order_id uuid, p_code text, p_member_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
  v_code   discount_codes%rowtype;
  v_guest  guest_codes%rowtype;
  v_tz     text;
  v_text   text := upper(btrim(coalesce(p_code, '')));
begin
  select * into v_order from orders where id = p_order_id for update;
  if not found then
    raise exception 'Nie znaleziono rachunku.';
  end if;
  perform private.require_permission(v_order.restaurant_id, 'orders');
  perform private.check_member(v_order.restaurant_id, p_member_id);
  if v_order.status <> 'open' then
    raise exception 'Ten rachunek jest już zamknięty.';
  end if;
  if v_order.kind <> 'dine_in' then
    raise exception 'Kod rabatowy wpisuje się przy rachunku stolika.';
  end if;
  if v_text = '' then
    update orders
    set discount_code_id = null, guest_code_id = null, discount_code = null, discount_kind = null,
        discount_value = null, discount_min_grosze = null
    where id = p_order_id;
    return panel_order_due(p_order_id);
  end if;

  select * into v_guest from guest_codes
  where restaurant_id = v_order.restaurant_id and code = v_text;
  if found then
    if v_guest.used_at is not null then
      raise exception 'Ten kod gościa został już wykorzystany.';
    end if;
    if v_guest.active_until is null or v_guest.active_until <= now() then
      raise exception 'Kod gościa wygasł. Poproś gościa, żeby aktywował go jeszcze raz w aplikacji Table.';
    end if;
    update orders
    set guest_code_id = v_guest.id, discount_code_id = null, discount_code = v_guest.code,
        discount_kind = v_guest.kind, discount_value = v_guest.value, discount_min_grosze = v_guest.min_total_grosze
    where id = p_order_id;
    return panel_order_due(p_order_id);
  end if;

  select coalesce(timezone, 'Europe/Warsaw') into v_tz from restaurants where id = v_order.restaurant_id;
  v_code := private.valid_discount(v_order.restaurant_id, v_text, (now() at time zone v_tz)::date);
  update orders
  set discount_code_id = v_code.id, guest_code_id = null, discount_code = v_code.code, discount_kind = v_code.kind,
      discount_value = v_code.value
  where id = p_order_id;
  return panel_order_due(p_order_id);
end;
$$;

-- Zamknięcie rachunku: kod gościa staje się wykorzystany, gdy rabat naprawdę był.
create or replace function private.order_guest_code_used()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'paid' and old.status <> 'paid' and new.guest_code_id is not null and new.discount_grosze > 0 then
    update public.guest_codes set used_at = now(), used_order_id = new.id
    where id = new.guest_code_id and used_at is null;
  end if;
  return new;
end;
$$;

drop trigger if exists orders_guest_code_used on public.orders;
create trigger orders_guest_code_used
  after update of status on public.orders
  for each row execute function private.order_guest_code_used();

-- Panel: zasady automatycznych kodów i liczby wydanych/wykorzystanych.
create or replace function public.panel_guest_code_rules(p_restaurant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform private.require_permission(p_restaurant_id, 'discounts');
  return (
    select jsonb_agg(jsonb_build_object(
      'event', t.event,
      'active', coalesce(r.active, false),
      'kind', coalesce(r.kind, 'percent'),
      'value', coalesce(r.value, 10),
      'min_total', r.min_total_grosze,
      'valid_days', coalesce(r.valid_days, 30),
      'issued', (select count(*) from guest_codes g where g.restaurant_id = p_restaurant_id and g.source = t.event),
      'used', (select count(*) from guest_codes g
               where g.restaurant_id = p_restaurant_id and g.source = t.event and g.used_at is not null)
    ) order by t.ord)
    from (values ('reservation', 1), ('review', 2)) as t(event, ord)
    left join guest_code_rules r on r.restaurant_id = p_restaurant_id and r.event = t.event
  );
end;
$$;

create or replace function public.panel_save_guest_code_rule(
  p_restaurant_id uuid,
  p_event text,
  p_active boolean,
  p_kind text,
  p_value integer,
  p_min_total integer,
  p_valid_days integer,
  p_member_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.require_permission(p_restaurant_id, 'discounts');
  perform private.check_inventory_member(p_restaurant_id, p_member_id);
  if p_event not in ('reservation', 'review') then
    raise exception 'Nieznany rodzaj kodu.';
  end if;
  if p_kind not in ('percent', 'amount') or p_value is null or p_value <= 0 or (p_kind = 'percent' and p_value > 100) then
    raise exception 'Wpisz rabat: procent od 1 do 100 albo kwotę większą od zera.';
  end if;
  if p_valid_days is null or p_valid_days not between 1 and 365 then
    raise exception 'Ważność kodu to od 1 do 365 dni.';
  end if;
  if p_min_total is not null and (p_min_total <= 0 or (p_kind = 'amount' and p_min_total < p_value)) then
    raise exception 'Minimalna kwota rachunku nie może być mniejsza niż rabat.';
  end if;
  insert into guest_code_rules (restaurant_id, event, active, kind, value, min_total_grosze, valid_days, updated_at)
  values (p_restaurant_id, p_event, coalesce(p_active, false), p_kind, p_value, p_min_total, p_valid_days, now())
  on conflict (restaurant_id, event) do update
  set active = excluded.active, kind = excluded.kind, value = excluded.value,
      min_total_grosze = excluded.min_total_grosze, valid_days = excluded.valid_days, updated_at = now();
end;
$$;

revoke execute on function private.issue_guest_code(uuid, uuid, text, uuid) from public, anon, authenticated;
revoke execute on function private.reservation_guest_code() from public, anon, authenticated;
revoke execute on function private.review_guest_code() from public, anon, authenticated;
revoke execute on function private.new_guest_code_text(uuid) from public, anon, authenticated;
revoke execute on function private.order_guest_code_used() from public, anon, authenticated;
revoke execute on function public.guest_my_codes() from public, anon;
revoke execute on function public.guest_activate_code(uuid) from public, anon;
revoke execute on function public.panel_order_set_discount(uuid, text, uuid) from public, anon;
revoke execute on function public.panel_guest_code_rules(uuid) from public, anon;
revoke execute on function public.panel_save_guest_code_rule(uuid, text, boolean, text, integer, integer, integer, uuid) from public, anon;
grant execute on function public.guest_my_codes() to authenticated;
grant execute on function public.guest_activate_code(uuid) to authenticated;
grant execute on function public.panel_order_set_discount(uuid, text, uuid) to authenticated;
grant execute on function public.panel_guest_code_rules(uuid) to authenticated;
grant execute on function public.panel_save_guest_code_rule(uuid, text, boolean, text, integer, integer, integer, uuid) to authenticated;
