-- Karta przy odbiorze i uwagi do adresu (31.10.2026).
-- 1. Nowa forma płatności zamówień na wynos: „Karta przy odbiorze” (`payment_choice = 'card_on_delivery'`): gość
--    płaci kartą dostawcy przy drzwiach albo w lokalu przy odbiorze osobistym. Lokal włącza ją w „Ustawienia lokalu”
--    → „Dostawa i odbiór” (`restaurants.takeaway_card`, domyślnie tak jak gotówka). Wydanie albo dostarczenie
--    zapisuje płatność jako kartę (terminal), więc podsumowanie dnia liczy ją razem z terminalami.
-- 2. Uwagi do adresu (kod do klatki, piętro, opis budynku) to co innego niż uwagi do zamówienia: osobna kolumna
--    `orders.address_note`, tylko przy dostawie. `delivery_note` zostaje uwagami do zamówienia (dla lokalu), także
--    przy odbiorze osobistym.

alter table public.orders add column if not exists address_note text check (char_length(address_note) <= 300);
alter table public.restaurants add column if not exists takeaway_card boolean not null default true;
grant update (takeaway_card) on public.restaurants to authenticated;

alter table public.orders drop constraint if exists orders_payment_choice_check;
alter table public.orders add constraint orders_payment_choice_check
  check (payment_choice in ('cash', 'card_online', 'card_on_delivery', 'prepaid'));

-- Zamiana tekstu w definicji funkcji; brak dopasowania przerywa migrację.
create function pg_temp.rep(p_src text, p_old text, p_new text)
returns text
language plpgsql
as $f$
begin
  if position(p_old in p_src) = 0 then
    raise exception 'Nie znaleziono w funkcji: %', left(p_old, 160);
  end if;
  return replace(p_src, p_old, p_new);
end;
$f$;

-- Zamówienie z aplikacji Table: karta przy odbiorze i uwagi do adresu (nowy parametr na końcu, z domyślnym null,
-- więc starsze wersje aplikacji działają dalej).
do $$
declare
  v text := pg_get_functiondef(
    'public.guest_place_order(uuid, text, jsonb, text, text, text, text, text, timestamptz)'::regprocedure
  );
begin
  v := pg_temp.rep(v,
    'p_scheduled_for timestamp with time zone DEFAULT NULL::timestamp with time zone)',
    'p_scheduled_for timestamp with time zone DEFAULT NULL::timestamp with time zone, p_address_note text DEFAULT NULL::text)');
  v := pg_temp.rep(v,
    'p_payment not in (''cash'', ''card_online'')',
    'p_payment not in (''cash'', ''card_online'', ''card_on_delivery'')');
  v := pg_temp.rep(v,
    'raise exception ''Ten lokal przyjmuje tylko płatność kartą online.'';
  end if;',
    'raise exception ''Ten lokal nie przyjmuje płatności gotówką.'';
  end if;
  if p_payment = ''card_on_delivery'' and not v_r.takeaway_card then
    raise exception ''Ten lokal nie przyjmuje płatności kartą przy odbiorze.'';
  end if;');
  v := pg_temp.rep(v,
    'delivery_address, delivery_note,
    delivery_fee_grosze, payment_choice',
    'delivery_address, delivery_note, address_note,
    delivery_fee_grosze, payment_choice');
  v := pg_temp.rep(v,
    'left(nullif(btrim(p_note), ''''), 300),',
    'left(nullif(btrim(p_note), ''''), 300),
    case when p_kind = ''delivery'' then left(nullif(btrim(p_address_note), ''''), 300) end,');
  drop function public.guest_place_order(uuid, text, jsonb, text, text, text, text, text, timestamptz);
  execute v;
end;
$$;

revoke all on function public.guest_place_order(uuid, text, jsonb, text, text, text, text, text, timestamptz, text)
  from public, anon;
grant execute on function public.guest_place_order(uuid, text, jsonb, text, text, text, text, text, timestamptz, text)
  to authenticated;

-- Kurs dostawcy i karta zamówienia: uwagi do adresu.
do $$
declare
  v text := pg_get_functiondef('private.course_json(public.orders)'::regprocedure);
begin
  v := pg_temp.rep(v,
    '''delivery_note'', p_order.delivery_note,',
    '''delivery_note'', p_order.delivery_note,
    ''address_note'', p_order.address_note,');
  execute v;
end;
$$;

-- Zamówienie z panelu: „do opłacenia” gotówką albo kartą przy odbiorze (`payment` w danych klienta),
-- uwagi do adresu (`address_note`) przy dostawie.
do $$
declare
  v text := pg_get_functiondef('public.panel_takeaway_create(uuid, text, jsonb, uuid)'::regprocedure);
begin
  v := pg_temp.rep(v,
    'delivery_address, delivery_note, staff_note,',
    'delivery_address, delivery_note, staff_note, address_note,');
  v := pg_temp.rep(v,
    'v_c.note, v_c.staff_note,',
    'v_c.note, v_c.staff_note,
    case when p_kind = ''delivery'' then left(nullif(btrim(p_customer ->> ''address_note''), ''''), 300) end,');
  v := pg_temp.rep(v,
    'case when v_c.paid then ''prepaid'' else ''cash'' end,',
    'case when v_c.paid then ''prepaid''
         when p_customer ->> ''payment'' = ''card_on_delivery'' then ''card_on_delivery''
         else ''cash'' end,');
  execute v;
end;
$$;

do $$
declare
  v text := pg_get_functiondef('public.panel_takeaway_update(uuid, jsonb, uuid)'::regprocedure);
begin
  v := pg_temp.rep(v,
    'staff_note = v_c.staff_note,',
    'staff_note = v_c.staff_note,
      -- Starsza wersja panelu nie wysyła uwag do adresu ani formy płatności: zostają jak były.
      address_note = case
        when kind <> ''delivery'' then null
        when p_customer ? ''address_note'' then left(nullif(btrim(p_customer ->> ''address_note''), ''''), 300)
        else address_note
      end,');
  v := pg_temp.rep(v,
    'payment_choice = case when v_c.paid then ''prepaid'' else ''cash'' end,',
    'payment_choice = case
        when v_c.paid then ''prepaid''
        when p_customer ? ''payment'' then
          case when p_customer ->> ''payment'' = ''card_on_delivery'' then ''card_on_delivery'' else ''cash'' end
        when payment_choice = ''card_on_delivery'' then ''card_on_delivery''
        else ''cash''
      end,');
  execute v;
end;
$$;

-- Wydanie odbioru i dostarczenie: karta przy odbiorze to płatność kartą (terminal).
do $$
declare
  v_fn regprocedure;
  v text;
begin
  foreach v_fn in array array[
    'public.panel_takeaway_handed(uuid, uuid)'::regprocedure,
    'public.staff_delivery_done(uuid, uuid)'::regprocedure
  ] loop
    v := pg_get_functiondef(v_fn);
    v := pg_temp.rep(v,
      'case payment_choice when ''card_online'' then ''card'' when ''prepaid''',
      'case payment_choice when ''card_online'' then ''card'' when ''card_on_delivery'' then ''card'' when ''prepaid''');
    execute v;
  end loop;
end;
$$;
