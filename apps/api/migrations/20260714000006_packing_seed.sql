-- Seed packing checklist from Sabarimala PDF for 2026 trip (idempotent)

INSERT INTO packing_items (trip_id, title, quantity_hint, sort_order)
SELECT t.id, p.title, p.hint, p.sort
FROM trips t
CROSS JOIN (VALUES
  ('Black dhotis with black shalya (extra for rain)', '3+ sets', 1),
  ('Irumudi bag + inner coconut bag (wash if reused)', '1 set', 2),
  ('Swamy mala from previous trip (Kanni: provided)', '1', 3),
  ('Original photo ID / Aadhaar for Virtual Q', '1', 4),
  ('Waist pouch for valuables', '1', 5),
  ('Reusable water bottle for hill climb', '0.5–1 L', 6),
  ('Thin raincoat or blue plastic cover', '1', 7),
  ('Air pillow', '1', 8),
  ('Pen torch / power-bank / charger', 'as needed', 9),
  ('Spare plastic covers (wet clothes / prasadham)', 'few', 10),
  ('Money + small change (₹10/20/50)', 'misc', 11),
  ('Personal medicines (BP, sugar, fever, cold)', '1 week', 12),
  ('Rice from home (do not mix with dal/wheat)', '<200 gms', 13),
  ('Kumkum / turmeric / vibhuti (group may carry)', 'optional', 14),
  ('Monetary offerings from friends/family', 'if any', 15)
) AS p(title, hint, sort)
WHERE t.year = 2026
  AND NOT EXISTS (
    SELECT 1 FROM packing_items pi WHERE pi.trip_id = t.id AND pi.title = p.title
  );
