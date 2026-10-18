insert into public.categories (slug, name, sort_order, is_active)
values
  ('electronics', 'Electronics', 10, true),
  ('vehicles', 'Vehicles', 20, true),
  ('property', 'Property', 30, true),
  ('fashion', 'Fashion', 40, true),
  ('home-living', 'Home & Living', 50, true),
  ('tools', 'Tools', 60, true),
  ('services', 'Services', 70, true)
on conflict (slug) do update
set name = excluded.name,
    sort_order = excluded.sort_order,
    is_active = excluded.is_active;

insert into public.locations (county, area_slug, area_name, is_active, sort_order)
values
  ('Nairobi', 'westlands', 'Westlands', true, 10),
  ('Nairobi', 'kilimani', 'Kilimani', true, 20),
  ('Nairobi', 'kasarani', 'Kasarani', true, 30),
  ('Nairobi', 'roysambu', 'Roysambu', true, 40),
  ('Kiambu', 'kiambu-town', 'Kiambu Town', true, 10),
  ('Kiambu', 'ruiru', 'Ruiru', true, 20),
  ('Kiambu', 'kikuyu', 'Kikuyu', true, 30),
  ('Kiambu', 'thika', 'Thika', true, 40)
on conflict (county, area_slug) do update
set area_name = excluded.area_name,
    is_active = excluded.is_active,
    sort_order = excluded.sort_order;