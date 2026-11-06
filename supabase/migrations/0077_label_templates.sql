-- Etykiety na pudełka i torby zamówień na wynos (6.11.2026, prośba użytkownika): drukarka termiczna etykiet
-- (np. Xprinter XP-410B) drukuje w panelu etykietę na każde danie albo na całe zamówienie. Wygląd etykiety
-- (rozmiar, elementy z polami jak {numer}, {danie}, {adres}) ustawia lokal w panelu („Drukarki”) i jest wspólny
-- dla wszystkich komputerów lokalu. Drukarkę i automatyczne drukowanie wybiera każdy komputer u siebie.

create table public.label_templates (
  restaurant_id uuid primary key references public.restaurants (id) on delete cascade,
  width_mm integer not null default 100 check (width_mm between 20 and 110),
  height_mm integer not null default 50 check (height_mm between 15 and 200),
  -- item: etykieta na każdą sztukę dania, order: jedna na zamówienie.
  per text not null default 'item' check (per in ('item', 'order')),
  -- Rodzaje zamówień, na które drukujemy (delivery, pickup).
  kinds text[] not null default '{delivery,pickup}',
  -- Działy menu z etykietą; puste: wszystkie dania, które robi kuchnia (bez napojów z „Nie pokazuj w kuchni”).
  sections uuid[] not null default '{}',
  elements jsonb not null default '[]'::jsonb check (jsonb_typeof(elements) = 'array'),
  updated_at timestamptz not null default now()
);

-- Tylko funkcje: czyta każdy z obsługi lokalu, zapisuje osoba z uprawnieniem do ustawień lokalu.
alter table public.label_templates enable row level security;

create or replace function public.panel_label_template(p_restaurant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row label_templates;
begin
  if not private.has_staff_role(p_restaurant_id, 'staff') then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;
  select * into v_row from label_templates where restaurant_id = p_restaurant_id;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'width_mm', v_row.width_mm,
    'height_mm', v_row.height_mm,
    'per', v_row.per,
    'kinds', to_jsonb(v_row.kinds),
    'sections', to_jsonb(v_row.sections),
    'elements', v_row.elements,
    'updated_at', v_row.updated_at
  );
end;
$$;

create or replace function public.panel_save_label_template(
  p_restaurant_id uuid,
  p_width_mm integer,
  p_height_mm integer,
  p_per text,
  p_kinds text[],
  p_sections uuid[],
  p_elements jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.require_permission(p_restaurant_id, 'profile');
  if p_elements is null or jsonb_typeof(p_elements) <> 'array' then
    raise exception 'Nieprawidłowe elementy etykiety.';
  end if;
  if jsonb_array_length(p_elements) > 60 then
    raise exception 'Najwyżej 60 elementów na etykiecie.';
  end if;
  if octet_length(p_elements::text) > 60000 then
    raise exception 'Etykieta jest za duża.';
  end if;
  if exists (select 1 from unnest(coalesce(p_kinds, '{}')) k where k not in ('delivery', 'pickup')) then
    raise exception 'Nieznany rodzaj zamówienia.';
  end if;
  insert into label_templates (restaurant_id, width_mm, height_mm, per, kinds, sections, elements, updated_at)
  values (
    p_restaurant_id, p_width_mm, p_height_mm, p_per, coalesce(p_kinds, '{}'), coalesce(p_sections, '{}'),
    p_elements, now()
  )
  on conflict (restaurant_id) do update
    set width_mm = excluded.width_mm,
        height_mm = excluded.height_mm,
        per = excluded.per,
        kinds = excluded.kinds,
        sections = excluded.sections,
        elements = excluded.elements,
        updated_at = now();
end;
$$;

revoke execute on function public.panel_label_template(uuid) from public, anon;
grant execute on function public.panel_label_template(uuid) to authenticated;
revoke execute on function public.panel_save_label_template(uuid, integer, integer, text, text[], uuid[], jsonb)
  from public, anon;
grant execute on function public.panel_save_label_template(uuid, integer, integer, text, text[], uuid[], jsonb)
  to authenticated;
