-- Table · migracja 0025
-- Nowy stan pozycji: „do wydania”. Kuchnia zbija danie, kelner je zanosi i dopiero wtedy jest „wydane”.
-- Osobna migracja, bo nowej wartości typu nie można użyć w tej samej transakcji.

alter type public.order_item_status add value if not exists 'ready' after 'sent';
