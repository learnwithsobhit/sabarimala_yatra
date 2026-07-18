-- Lost-person tips on key itinerary stops
UPDATE itinerary_stops SET lost_person_tip = 'Wait at main entrance of Vadakkunnathan Temple'
WHERE title ILIKE '%Thrissur%' AND (lost_person_tip IS NULL OR lost_person_tip = '');

UPDATE itinerary_stops SET lost_person_tip = 'Wait in front of Guruvayur main temple door'
WHERE title ILIKE '%Guruvayur%' AND (lost_person_tip IS NULL OR lost_person_tip = '');

UPDATE itinerary_stops SET lost_person_tip = 'Going up: Pamba Ganapathy steps before Virtual Q. Returning: Indian Oil bunk. On top: Melshanthi room or 18 Steps.'
WHERE title ILIKE '%Pampa%' OR title ILIKE '%Sannidhanam%' OR title ILIKE '%Sabarimala%';
