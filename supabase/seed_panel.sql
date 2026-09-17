-- Table · dane przykładowe panelu restauracji
-- Uruchom po migracji 0012 i po seed.sql oraz seed_krakow.sql.
-- Strefy sali i rozstawienie stolików lokali przykładowych z planem Pro.

insert into public.floor_zones (restaurant_id, name, width_cm, height_cm, position)
select r.id, z.name, z.w, z.h, z.pos
from public.restaurants r
cross join (values ('sala', 1000, 700, 0), ('okno', 600, 300, 1)) as z(name, w, h, pos)
where r.is_example and r.plan = 'pro'
on conflict (restaurant_id, name) do nothing;

-- Środek blatu w centymetrach od lewego górnego rogu strefy.
update public.dining_tables t
set x_cm = p.x, y_cm = p.y, shape = p.shape
from public.restaurants r,
  (values
    ('S1', 160, 150, 'round'),
    ('S2', 360, 150, 'round'),
    ('S3', 620, 150, 'rect'),
    ('S4', 850, 150, 'rect'),
    ('S5', 500, 450, 'rect'),
    ('O1', 200, 150, 'rect'),
    ('O2', 330, 150, 'rect')
  ) as p(label, x, y, shape)
where t.restaurant_id = r.id
  and r.is_example
  and t.label = p.label;
