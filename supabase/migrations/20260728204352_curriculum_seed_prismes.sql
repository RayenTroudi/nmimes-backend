-- supabase/migrations/0004_curriculum_seed_prismes.sql

insert into curriculum_chapters (id, level, theme, title, subtitle, icon, sort_order)
values (
  '7-prismes-cylindres',
  '7',
  'geometric',
  '{"en": "Prisms & cylinders", "fr": "Prismes et cylindres", "ar": "الموشور والإسطوانة"}',
  '{"en": "Right prisms and right cylinders", "fr": "Moshour droit et cylindre droit", "ar": "الموشور القائم والإسطوانة القائمة"}',
  '📦',
  3
)
on conflict (id) do nothing;

insert into curriculum_questions (chapter_id, sort_order, kind, payload) values
('7-prismes-cylindres', 1, 'true_false', '{
  "statement": {"en": "In a right prism, the two bases are congruent polygons.", "fr": "Dans un prisme droit, les deux bases sont deux polygones superposables.", "ar": "في الموشور القائم، القاعدتان مضلّعان متقايسان."},
  "answer": true
}'),
('7-prismes-cylindres', 2, 'true_false', '{
  "statement": {"en": "The lateral faces of a right prism are triangles.", "fr": "Les faces latérales d''un prisme droit sont des triangles.", "ar": "الأوجه الجانبيّة للموشور القائم هي مثلّثات."},
  "answer": false
}'),
('7-prismes-cylindres', 3, 'mcq', '{
  "prompt": {"en": "In a right cylinder, the two bases are:", "fr": "Dans un cylindre droit, les deux bases sont :", "ar": "في الإسطوانة القائمة، القاعدتان هما:"},
  "choices": [{"en": "two congruent disks", "fr": "deux disques superposables", "ar": "قرصان متقايسان"}, {"en": "two squares", "fr": "deux carrés", "ar": "مربّعان"}, {"en": "two triangles", "fr": "deux triangles", "ar": "مثلّثان"}, {"en": "two rectangles", "fr": "deux rectangles", "ar": "مستطيلان"}],
  "correctIndex": 0
}'),
('7-prismes-cylindres', 4, 'mcq', '{
  "prompt": {"en": "The length of a right prism''s lateral edges equals:", "fr": "La longueur des arêtes latérales d''un prisme droit est égale à :", "ar": "طول الأحرف الجانبيّة للموشور القائم يساوي:"},
  "choices": [{"en": "the prism''s height", "fr": "la hauteur du prisme", "ar": "ارتفاع الموشور"}, {"en": "the base''s perimeter", "fr": "le périmètre de la base", "ar": "محيط القاعدة"}, {"en": "the base''s radius", "fr": "le rayon de la base", "ar": "شعاع القاعدة"}, {"en": "the base''s diagonal", "fr": "la diagonale de la base", "ar": "قطر القاعدة"}],
  "correctIndex": 0
}'),
('7-prismes-cylindres', 5, 'input', '{
  "prompt": {"en": "The volume, in cm³, of a right prism with a 24 cm² base and a 10 cm height is:", "fr": "Le volume, en cm³, d''un prisme droit de base 24 cm² et de hauteur 10 cm est :", "ar": "حجم موشور قائم قاعدته 24 سم² وارتفاعه 10 سم، بـ سم³، هو:"},
  "accepted": ["240"]
}'),
('7-prismes-cylindres', 6, 'input', '{
  "prompt": {"en": "The volume of a right cylinder with radius 3 cm and height 10 cm is about ___ cm³ (use π ≈ 3.14).", "fr": "Le volume d''un cylindre droit de rayon 3 cm et de hauteur 10 cm est environ ___ cm³ (prends π ≈ 3,14).", "ar": "حجم إسطوانة قائمة شعاعها 3 سم وارتفاعها 10 سم يساوي تقريبا ___ سم³ (خذ π ≈ 3,14)."},
  "accepted": ["282.6", "282,6"]
}'),
('7-prismes-cylindres', 7, 'drag_fill', '{
  "prompt": {"en": "Right cylinder volume formula: V = π × r² × ___", "fr": "Formule du volume d''un cylindre droit : V = π × r² × ___", "ar": "صيغة حجم الإسطوانة القائمة: V = π × r² × ___"},
  "choices": ["r", "h", "2r", "2h"],
  "correctIndex": 1
}'),
('7-prismes-cylindres', 8, 'multi_select', '{
  "prompt": {"en": "Check the solids that are right prisms.", "fr": "Coche les solides qui sont des prismes droits.", "ar": "اختر المجسّمات التي هي موشور قائم."},
  "options": [{"en": "A cube", "fr": "Un cube", "ar": "مكعّب"}, {"en": "A rectangular box", "fr": "Un parallélépipède rectangle", "ar": "متوازي مستطيلات"}, {"en": "A cone", "fr": "Un cône", "ar": "مخروط"}, {"en": "A pyramid", "fr": "Une pyramide", "ar": "هرم"}],
  "correct": [0, 1]
}'),
('7-prismes-cylindres', 9, 'sort_buckets', '{
  "prompt": {"en": "Sort each property", "fr": "Classe chaque propriété", "ar": "صنّف كلّ خاصيّة"},
  "buckets": [{"en": "Right prism", "fr": "Prisme droit", "ar": "الموشور القائم"}, {"en": "Right cylinder", "fr": "Cylindre droit", "ar": "الإسطوانة القائمة"}],
  "items": [
    {"label": {"en": "Bases are polygons", "fr": "Bases = polygones", "ar": "القاعدتان مضلّعان"}, "bucket": 0},
    {"label": {"en": "Bases are disks", "fr": "Bases = disques", "ar": "القاعدتان قرصان"}, "bucket": 1},
    {"label": {"en": "Rectangular lateral faces + 2 polygon bases", "fr": "Faces latérales rectangulaires + 2 bases polygonales", "ar": "أوجه جانبيّة مستطيلة + قاعدتان مضلّعتان"}, "bucket": 0},
    {"label": {"en": "Net = 1 rectangle + 2 disks", "fr": "Développement = 1 rectangle + 2 disques", "ar": "الفرش = مستطيل واحد + قرصان"}, "bucket": 1}
  ]
}'),
('7-prismes-cylindres', 10, 'maze', '{
  "prompt": {"en": "Answer each question to move forward!", "fr": "Réponds à chaque question pour avancer !", "ar": "أجب عن كلّ سؤال للتقدّم!"},
  "layout": ["S#...#", ".#.#..", "..*#.#", "#.#.*.", "....#.", "##..*G"],
  "checkpoints": [
    {"prompt": {"en": "A prism''s base perimeter is 20 cm and its height is 7 cm. Lateral area = ?", "fr": "Le périmètre de la base d''un prisme est 20 cm et sa hauteur est 7 cm. Aire latérale = ?", "ar": "محيط قاعدة موشور 20 سم وارتفاعه 7 سم. المساحة الجانبيّة تساوي:"}, "choices": [{"en": "140 cm²", "fr": "140 cm²", "ar": "140 سم²"}, {"en": "27 cm²", "fr": "27 cm²", "ar": "27 سم²"}, {"en": "70 cm²", "fr": "70 cm²", "ar": "70 سم²"}, {"en": "130 cm²", "fr": "130 cm²", "ar": "130 سم²"}], "correctIndex": 0},
    {"prompt": {"en": "A cylinder has radius 5 cm. Its base perimeter (2πr, π ≈ 3.14) is about:", "fr": "Un cylindre a un rayon de 5 cm. Son périmètre de base (2πr, π ≈ 3,14) est environ :", "ar": "لإسطوانة شعاع 5 سم. محيط قاعدتها (2πr، π ≈ 3,14) يساوي تقريبا:"}, "choices": [{"en": "31.4 cm", "fr": "31,4 cm", "ar": "31,4 سم"}, {"en": "15.7 cm", "fr": "15,7 cm", "ar": "15,7 سم"}, {"en": "62.8 cm", "fr": "62,8 cm", "ar": "62,8 سم"}, {"en": "25 cm", "fr": "25 cm", "ar": "25 سم"}], "correctIndex": 0},
    {"prompt": {"en": "A right prism has a 15 cm² base and a 6 cm height. Its volume is:", "fr": "Un prisme droit a une base de 15 cm² et une hauteur de 6 cm. Son volume est :", "ar": "لموشور قائم قاعدة مساحتها 15 سم² وارتفاعه 6 سم. حجمه يساوي:"}, "choices": [{"en": "90 cm³", "fr": "90 cm³", "ar": "90 سم³"}, {"en": "21 cm³", "fr": "21 cm³", "ar": "21 سم³"}, {"en": "45 cm³", "fr": "45 cm³", "ar": "45 سم³"}, {"en": "180 cm³", "fr": "180 cm³", "ar": "180 سم³"}], "correctIndex": 0}
  ]
}'),
('7-prismes-cylindres', 11, 'match_pairs', '{
  "prompt": {"en": "Match each solid to its base shape", "fr": "Associe chaque solide à sa base", "ar": "طابق كلّ مجسّم بشكل قاعدته"},
  "pairs": [
    {"left": {"en": "Triangular right prism", "fr": "Prisme droit à base triangulaire", "ar": "موشور قائم قاعدته مثلّث"}, "right": {"en": "Base = triangle", "fr": "Base = triangle", "ar": "القاعدة = مثلّث"}},
    {"left": {"en": "Rectangular right prism", "fr": "Prisme droit à base rectangulaire", "ar": "موشور قائم قاعدته مستطيل"}, "right": {"en": "Base = rectangle", "fr": "Base = rectangle", "ar": "القاعدة = مستطيل"}},
    {"left": {"en": "Right cylinder", "fr": "Cylindre droit", "ar": "إسطوانة قائمة"}, "right": {"en": "Base = disk", "fr": "Base = disque", "ar": "القاعدة = قرص"}},
    {"left": {"en": "Hexagonal right prism", "fr": "Prisme droit à base hexagonale", "ar": "موشور قائم قاعدته سداسي"}, "right": {"en": "Base = hexagon", "fr": "Base = hexagone", "ar": "القاعدة = سداسي"}}
  ]
}'),
('7-prismes-cylindres', 12, 'number_line', '{
  "prompt": {"en": "Place the volume of a cube with 4 cm edges (in cm³) on the line.", "fr": "Place le volume d''un cube d''arête 4 cm (en cm³) sur la ligne.", "ar": "ضع حجم مكعّب طول حرفه 4 سم (بـ سم³) على الخطّ."},
  "min": 0, "max": 100, "step": 10, "target": 64, "tolerance": 3
}');
