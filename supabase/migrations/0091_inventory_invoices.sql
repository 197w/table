-- Management → Inwentaryzacja → Faktury (20.11.2026, prośba użytkownika: „dodać faktury w management
-- w inwentaryzacji”): faktury zakupu od dostawców towaru, opcjonalnie powiązane z wpisem dostawy
-- (`inventory_docs`), z kwotą brutto, terminem płatności i oznaczeniem „opłacona”. Tylko dla osób z uprawnieniem
-- „Edytowanie składników” (`inventory_edit`), bo to pieniądze. Zapis i odczyt tylko funkcjami.

create table if not exists public.inventory_invoices (
  id                 uuid primary key default gen_random_uuid(),
  restaurant_id      uuid not null references public.restaurants (id) on delete cascade,
  -- Dostawa, której dotyczy faktura (znika razem z usuniętym wpisem dostawy tylko jako powiązanie).
  doc_id             uuid references public.inventory_docs (id) on delete set null,
  supplier           text not null check (char_length(btrim(supplier)) between 1 and 120),
  number             text not null check (char_length(btrim(number)) between 1 and 60),
  issued_on          date not null,
  due_on             date,
  gross_grosze       integer not null check (gross_grosze > 0),
  note               text check (note is null or char_length(note) <= 300),
  -- Dzień zapłaty. Null: nieopłacona.
  paid_on            date,
  created_by_member  uuid references public.staff_members (id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (due_on is null or due_on >= issued_on),
  unique (restaurant_id, supplier, number)
);

create index if not exists inventory_invoices_restaurant_idx
  on public.inventory_invoices (restaurant_id, issued_on desc);

alter table public.inventory_invoices enable row level security;
revoke all on public.inventory_invoices from anon, authenticated;

-- Faktura jako JSON do listy.
create or replace function private.inventory_invoice_json(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', i.id,
    'doc_id', i.doc_id,
    'doc_at', d.happened_at,
    'supplier', i.supplier,
    'number', i.number,
    'issued_on', i.issued_on,
    'due_on', i.due_on,
    'gross_grosze', i.gross_grosze,
    'note', i.note,
    'paid_on', i.paid_on,
    'created_by', m.name,
    'created_at', i.created_at
  )
  from public.inventory_invoices i
  left join public.inventory_docs d on d.id = i.doc_id
  left join public.staff_members m on m.id = i.created_by_member
  where i.id = p_id
$$;
revoke execute on function private.inventory_invoice_json(uuid) from public, anon;

-- Faktury lokalu, najnowsze pierwsze (najwyżej 1000).
create or replace function public.panel_inventory_invoices(p_restaurant_id uuid, p_member_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public'
as $$
begin
  perform private.inventory_allowed(p_restaurant_id, p_member_id, 'inventory_edit');
  return coalesce((
    select jsonb_agg(private.inventory_invoice_json(x.id) order by x.issued_on desc, x.created_at desc)
    from (
      select id, issued_on, created_at from inventory_invoices
      where restaurant_id = p_restaurant_id
      order by issued_on desc, created_at desc
      limit 1000
    ) x
  ), '[]'::jsonb);
end;
$$;

-- Nowa faktura ([p_id] null) albo zmiana istniejącej. Ten sam dostawca i numer drugi raz nie przejdzie.
create or replace function public.panel_save_inventory_invoice(
  p_restaurant_id uuid,
  p_id uuid,
  p_supplier text,
  p_number text,
  p_issued_on date,
  p_due_on date,
  p_gross_grosze integer,
  p_doc_id uuid default null,
  p_note text default null,
  p_paid_on date default null,
  p_member_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_id  uuid := p_id;
begin
  perform private.inventory_allowed(p_restaurant_id, p_member_id, 'inventory_edit');
  if nullif(btrim(p_supplier), '') is null then
    raise exception 'Wpisz dostawcę.';
  end if;
  if nullif(btrim(p_number), '') is null then
    raise exception 'Wpisz numer faktury.';
  end if;
  if p_issued_on is null then
    raise exception 'Wybierz datę wystawienia.';
  end if;
  if p_gross_grosze is null or p_gross_grosze <= 0 then
    raise exception 'Wpisz kwotę brutto większą od zera.';
  end if;
  if p_due_on is not null and p_due_on < p_issued_on then
    raise exception 'Termin płatności nie może być przed datą wystawienia.';
  end if;
  if p_doc_id is not null and not exists (
    select 1 from inventory_docs where id = p_doc_id and restaurant_id = p_restaurant_id
  ) then
    raise exception 'Nie znaleziono tej dostawy.';
  end if;

  if v_id is null then
    insert into inventory_invoices (
      restaurant_id, doc_id, supplier, number, issued_on, due_on, gross_grosze, note, paid_on, created_by_member
    )
    values (
      p_restaurant_id, p_doc_id, btrim(p_supplier), btrim(p_number), p_issued_on, p_due_on, p_gross_grosze,
      nullif(btrim(p_note), ''), p_paid_on, p_member_id
    )
    returning id into v_id;
  else
    update inventory_invoices
    set doc_id = p_doc_id, supplier = btrim(p_supplier), number = btrim(p_number), issued_on = p_issued_on,
        due_on = p_due_on, gross_grosze = p_gross_grosze, note = nullif(btrim(p_note), ''), paid_on = p_paid_on,
        updated_at = now()
    where id = v_id and restaurant_id = p_restaurant_id;
    if not found then
      raise exception 'Nie znaleziono faktury.';
    end if;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'Faktura % od tego dostawcy jest już wpisana.', btrim(p_number);
end;
$$;

-- Oznacza fakturę jako opłaconą w dniu [p_paid_on] albo jako nieopłaconą (null).
create or replace function public.panel_set_inventory_invoice_paid(
  p_id uuid,
  p_paid_on date,
  p_member_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_restaurant uuid;
begin
  select restaurant_id into v_restaurant from inventory_invoices where id = p_id;
  if v_restaurant is null then
    raise exception 'Nie znaleziono faktury.';
  end if;
  perform private.inventory_allowed(v_restaurant, p_member_id, 'inventory_edit');
  update inventory_invoices set paid_on = p_paid_on, updated_at = now() where id = p_id;
end;
$$;

create or replace function public.panel_delete_inventory_invoice(p_id uuid, p_member_id uuid default null)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_restaurant uuid;
begin
  select restaurant_id into v_restaurant from inventory_invoices where id = p_id;
  if v_restaurant is null then
    raise exception 'Nie znaleziono faktury.';
  end if;
  perform private.inventory_allowed(v_restaurant, p_member_id, 'inventory_edit');
  delete from inventory_invoices where id = p_id;
end;
$$;

revoke all on function public.panel_inventory_invoices(uuid, uuid) from public, anon;
revoke all on function public.panel_save_inventory_invoice(uuid, uuid, text, text, date, date, integer, uuid, text, date, uuid) from public, anon;
revoke all on function public.panel_set_inventory_invoice_paid(uuid, date, uuid) from public, anon;
revoke all on function public.panel_delete_inventory_invoice(uuid, uuid) from public, anon;
grant execute on function public.panel_inventory_invoices(uuid, uuid) to authenticated;
grant execute on function public.panel_save_inventory_invoice(uuid, uuid, text, text, date, date, integer, uuid, text, date, uuid) to authenticated;
grant execute on function public.panel_set_inventory_invoice_paid(uuid, date, uuid) to authenticated;
grant execute on function public.panel_delete_inventory_invoice(uuid, uuid) to authenticated;
