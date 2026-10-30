-- 0067: platformy dostaw (Glovo, Uber Eats, Wolt…) w podsumowaniu dnia: lokal wpisuje ich nazwy
-- w „Ustawienia lokalu”, a w podsumowaniu dnia kwotę sprzedaży z każdej. Liczone osobno, poza kasą fiskalną.

alter table public.restaurants
  add column if not exists delivery_platforms text[] not null default '{}';

alter table public.day_reports
  add column if not exists platforms jsonb not null default '[]'::jsonb;

-- Lista platform lokalu (kolejność jak w podsumowaniu dnia).
create or replace function public.panel_set_delivery_platforms(p_restaurant_id uuid, p_names text[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_names text[];
begin
  perform private.require_permission(p_restaurant_id, 'profile');
  select coalesce(array_agg(n order by ord), '{}')
  into v_names
  from (
    select distinct on (lower(btrim(x))) left(btrim(x), 40) as n, ord
    from unnest(coalesce(p_names, '{}')) with ordinality as t(x, ord)
    where btrim(x) <> ''
    order by lower(btrim(x)), ord
  ) s;
  if cardinality(v_names) > 12 then
    raise exception 'Najwyżej 12 platform.';
  end if;
  update restaurants set delivery_platforms = v_names where id = p_restaurant_id;
end;
$$;

-- Zapis raportu z kwotami z platform. [p_platforms] null: bez zmiany (starsze wersje panelu).
drop function if exists public.panel_save_day_report(uuid, date, integer, jsonb, integer, text, uuid);
create function public.panel_save_day_report(
  p_restaurant_id uuid,
  p_day date,
  p_fiscal integer,
  p_terminals jsonb,
  p_cash_counted integer,
  p_note text,
  p_member_id uuid default null,
  p_platforms jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_terminals jsonb;
  v_platforms jsonb;
begin
  perform private.require_permission(p_restaurant_id, 'day_close');
  perform private.check_inventory_member(p_restaurant_id, p_member_id);
  if p_day > (now() at time zone 'Europe/Warsaw')::date + 1 then
    raise exception 'Nie można wpisać raportu na przyszły dzień.';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'name', left(coalesce(nullif(trim(t->>'name'), ''), 'Terminal'), 60),
           'grosze', greatest(0, least((t->>'grosze')::integer, 100000000))
         )), '[]'::jsonb)
  into v_terminals
  from jsonb_array_elements(coalesce(p_terminals, '[]'::jsonb)) t
  where (t->>'grosze') is not null;

  if p_platforms is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
             'name', left(coalesce(nullif(trim(t->>'name'), ''), 'Platforma'), 40),
             'grosze', greatest(0, least((t->>'grosze')::integer, 100000000))
           )), '[]'::jsonb)
    into v_platforms
    from jsonb_array_elements(p_platforms) t
    where (t->>'grosze') is not null;
  end if;

  insert into day_reports (restaurant_id, day, fiscal_grosze, terminals, cash_counted_grosze, note, platforms,
                           updated_at, updated_by_member, updated_by_name)
  values (p_restaurant_id, p_day, p_fiscal, v_terminals, p_cash_counted, nullif(trim(p_note), ''),
          coalesce(v_platforms, '[]'::jsonb), now(), p_member_id, private.note_author(p_restaurant_id, p_member_id))
  on conflict (restaurant_id, day) do update
    set fiscal_grosze = excluded.fiscal_grosze, terminals = excluded.terminals,
        cash_counted_grosze = excluded.cash_counted_grosze, note = excluded.note,
        platforms = coalesce(v_platforms, day_reports.platforms),
        updated_at = now(), updated_by_member = excluded.updated_by_member, updated_by_name = excluded.updated_by_name;
end;
$$;

-- Podsumowanie dnia oddaje też kwoty z platform zapisane w raporcie.
do $$
declare
  v_def text;
  v_new text;
begin
  v_def := pg_get_functiondef('public.panel_day_summary(uuid, date)'::regprocedure);
  v_new := replace(v_def, '''note'', r.note, ''updated_at''', '''note'', r.note, ''platforms'', r.platforms, ''updated_at''');
  if v_new = v_def then
    raise exception 'panel_day_summary: nie znaleziono miejsca na platformy';
  end if;
  execute v_new;
end;
$$;

revoke execute on function public.panel_set_delivery_platforms(uuid, text[]) from public, anon;
revoke execute on function public.panel_save_day_report(uuid, date, integer, jsonb, integer, text, uuid, jsonb) from public, anon;
grant execute on function public.panel_set_delivery_platforms(uuid, text[]) to authenticated;
grant execute on function public.panel_save_day_report(uuid, date, integer, jsonb, integer, text, uuid, jsonb) to authenticated;
