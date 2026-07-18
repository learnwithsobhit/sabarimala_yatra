-- Richer Sabarimala PDF knowledge for RAG / chatbot (idempotent inserts by section)

INSERT INTO knowledge_chunks (trip_id, source_title, source_section, content)
SELECT t.id, 'Shabarimala2026_Aug15-20.pdf', k.section, k.content
FROM trips t
CROSS JOIN (VALUES
  ('15 Aug — Assembly & Irumudi',
   '08:00 assemble at Ravindra’s House #97/a, 6th cross, 20th main, Rajajinagar 1st N block. Phones 23370704 / 9739038345 / 9844038345. Irumudi 9:00–12:30 (Kanni first). Lunch prasadham 13:00. Leave for railway 14:30. Board train 16315 KOCHUVELI EXP at 16:35.'),
  ('Mala wearing note',
   'As advised by Guru Swamy, mala should be removed at the same place it was worn. If going home directly from station after trip, wear mala at an Ayyappa temple near home with a priest. Senior Swamy (3+ years with Irumudi) may wear at home after elder blessings.'),
  ('16 Aug — Thrissur morning',
   'Arrive Thrissur ~02:50, bus to Pearl Regency, Wariam Lane near railway (0487 242 1895). Finish morning by ~05:45. 06:00 Vadakkunnathan & Paramekkavu. Breakfast 07:30. 08:30 Peruvanam Mahadeva then Triprayar Rama. Lunch 13:00–14:00.'),
  ('16 Aug — Guruvayur',
   '14:00 leave to Guruvayur, check-in Bhagavatam Guest House / stay Rajavalsam Hotel. 16:00 main temple darshan (queue near front gate), then Mammiyur Shiva. Dinner 19:30–20:30. 20:45 Seeveli Seva (side/back gate), then Guruvayur Keshavan place.'),
  ('17 Aug — To Sabarimala',
   'Wake ~02:00–02:30; depart ~03:30–04:00. Kodungallur Bhagavathy ~05:20; Chottanikkara ~06:15; breakfast 07:30. Optional Ettumanoor ~09:30. Erumely ~11:30; lunch then leave for Pampa ~12:30. Nilakkal ~13:45–14:30 government bus to Pampa. Bath if water/time allows. Climb from ~15:30 with a Senior Swamy. Sannidhanam darshan ~17–19; Padi Pooja & Pushpa Abhishekam ~19–19:30; dinner/sleep ~22:30.'),
  ('Pushpa / Ashta Abhishekam tickets',
   'For each Pushpa Abhishekam, 5 Swamis participate with flower baskets. Group tries to book enough tickets; if short, preference to Kanni and first-time seva, else chit system. Same for Ashta Dravya Abhishekam next day.'),
  ('18 Aug — Abhishekam & descend',
   '03:00–05:00 open Irumudi (at least one Kanni prepared). Ashta Dravya Abhishekam slot-dependent (sandal, ghee, rose water, milk, vibhuti, honey, panchamrutha, tender coconut). Then prasadham, Maalikapurathamma, Mel Shanthi (vastra+kanike). Offer coconut to Agni Kundam; rice near Malikappuram; Bell Swamis near Kanni Moola Ganapathy; aralu & pepper at Vavar. Depart toward Pampa ~12:05; lunch at Pampa; leave Nilakkal ~16:00 toward Chengannur. Optional Aranmula if early. Stay AMDEN RESIDENCY.'),
  ('19 Aug — Chengannur circuit & return',
   '04:30 Chengannur temple morning darshan. Breakfast then Aranmula if needed, Sree Vallabha, Ambalapuza Krishna (lunch), Velorvattom Mahadevar. Reach Cherthala station ~19:00; board 16316 KCVL MYS EXP at 19:40.'),
  ('20 Aug — Bengaluru & mala removal',
   'Arrive KR Puram ~07:12 / SBC ~08:25. Mala removal at Ravindra’s house ~09:40 then home. Family may wash feet and aarathi at entrance; keep prasadhams in pooja room.'),
  ('Lost — Guruvayur / Thrissur / Chottanikkara',
   'Guruvayur: wait at main temple door. Thrissur: Vadakkunnathan main entrance. Chottanikkara: main entrance of upper temple. Other temples: main entrance.'),
  ('Lost — Pamba / Sabarimala',
   'Pamba network poor; usually BSNL. Going up: wait at start of steps near Pamba Ganapathy before Virtual Q/Aadhaar. Returning: Indian Oil petrol bunk. Sabarimala: Holy 18 Steps if below; Melshanthi room if on top.'),
  ('Mandala Vratham start',
   '30 Jun / 7 Jul 2026 start for 48/41 days austerities. Kerala often 41 days before Irumudi; Karnataka 48. Some complete 41 days after return.'),
  ('Before leaving house',
   'Pack checklist; bath; black dhoti & shalya; tilak; handful of rice from each family member; pray house deity & Guru; light two ghee lamps; mangala aarathi; namaskaram; leave silently without formal goodbye (inform family of custom).'),
  ('Carry essentials',
   'Original photo ID/Aadhaar for Virtual Q (not stored in app). Black dhotis 3+ sets, irumudi bag, waist pouch, raincoat/blue plastic, water bottle 0.5–1L, personal medicines, spare covers, change (₹10/20/50). Kanni: ask for raincoat at Irumudi if needed.'),
  ('Vratham essence',
   'Simple living, cleanliness; no alcohol/tobacco/non-veg; no hair/nail cutting during vratham; bathe 2–3× daily; chant Ayyappa Sharanam (≥108); treat devotees as Ayyappa; humility; brahmacharya; no oil on bath; carry Tulasi; sleep on mat; complete surrender.')
) AS k(section, content)
WHERE t.year = 2026
  AND NOT EXISTS (
    SELECT 1 FROM knowledge_chunks kc
    WHERE kc.trip_id = t.id AND kc.source_section = k.section
  );
