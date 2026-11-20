-- Poprawka do 0092: zniżka na dział liczy się w chwili złożenia zamówienia (`now()`), nie w chwili zamówienia „na
-- godzinę” (`scheduled_for`). Aplikacja gościa liczy cenę w koszyku w chwili zamawiania, więc cena w koszyku i cena
-- w zamówieniu zgadzają się także dla zamówienia na godzinę, które przekracza początek albo koniec wydarzenia.
-- Zmienia tylko jedno wyrażenie w `guest_place_order` (reszta funkcji bez zmian).

do $$
declare
  v_def text;
begin
  select pg_get_functiondef(
    'public.guest_place_order(uuid, text, jsonb, text, text, text, text, text, timestamptz, text)'::regprocedure
  ) into v_def;
  if position('coalesce(v_when, now())' in v_def) = 0 then
    raise exception 'guest_place_order nie ma oczekiwanego wyrażenia';
  end if;
  v_def := replace(v_def, 'coalesce(v_when, now())', 'now()');
  execute v_def;
end;
$$;
