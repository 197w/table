-- Table · migracja 0017
-- Wgrywanie logo kończyło się błędem 400: Storage przy wysyłce czyta zapisany wiersz,
-- a kierownik nie miał prawa odczytu obiektów w koszyku logo.

create policy "Kierownik widzi logo lokalu"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'restaurant-logos' and private.can_manage_logo(name));
