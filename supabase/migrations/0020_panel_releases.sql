-- Table · migracja 0020
-- Publiczny katalog na instalatory panelu na Windows i opis najnowszej wersji (latest.json).
-- Czytać może każdy, bo panel sprawdza aktualizacje bez logowania. Pliki wysyła tylko
-- GitHub Actions kluczem serwisowym, dlatego nie ma tu żadnej polityki zapisu.

insert into storage.buckets (id, name, public, file_size_limit)
values ('panel-releases', 'panel-releases', true, 209715200)
on conflict (id) do nothing;
