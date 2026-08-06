-- supabase/migrations/0002_curriculum_seed_algebre.sql

insert into curriculum_chapters (id, level, theme, title, subtitle, icon, sort_order)
values (
  '7-algebre-bases',
  '7',
  'numeric',
  '{"en": "Algebra basics", "fr": "Bases de l''algèbre", "ar": "أساسيات الجبر"}',
  '{"en": "Expressions, equations and proportionality", "fr": "Expressions, équations et proportionnalité", "ar": "عبارات ومعادلات وتناسب"}',
  '🔤',
  1
)
on conflict (id) do nothing;

insert into curriculum_questions (chapter_id, sort_order, kind, payload) values
('7-algebre-bases', 1, 'mcq', '{
  "prompt": {"en": "A rectangle has length x cm and width 5 cm. What is its perimeter?", "fr": "Un rectangle a une longueur de x cm et une largeur de 5 cm. Quel est son périmètre ?", "ar": "لمستطيل طول x سم وعرض 5 سم. ما هو محيطه؟"},
  "choices": [{"en": "2x + 10", "fr": "2x + 10", "ar": "2x + 10"}, {"en": "5x", "fr": "5x", "ar": "5x"}, {"en": "x + 5", "fr": "x + 5", "ar": "x + 5"}, {"en": "2x + 5", "fr": "2x + 5", "ar": "2x + 5"}],
  "correctIndex": 0
}'),
('7-algebre-bases', 2, 'input', '{
  "prompt": {"en": "Solve: x + 7 = 15. x = ?", "fr": "Résous : x + 7 = 15. x = ?", "ar": "حلّ: x + 7 = 15. ما هو x؟"},
  "accepted": ["8"]
}'),
('7-algebre-bases', 3, 'drag_fill', '{
  "prompt": {"en": "Complete: ___ + 9 = 20", "fr": "Complète : ___ + 9 = 20", "ar": "أكمل: ___ + 9 = 20"},
  "choices": ["9", "10", "11", "12"],
  "correctIndex": 2
}'),
('7-algebre-bases', 4, 'true_false', '{
  "statement": {"en": "If a = 5, then 2a + 3 = 13.", "fr": "Si a = 5, alors 2a + 3 = 13.", "ar": "إذا كان a = 5 فإنّ 2a + 3 = 13."},
  "answer": true
}'),
('7-algebre-bases', 5, 'true_false', '{
  "statement": {"en": "A direct proportionality relation has the form y = a × x, where a is a constant.", "fr": "Une relation de proportionnalité directe a la forme y = a × x, où a est une constante.", "ar": "علاقة التناسب الطردي على الشكل y = a × x حيث a عدد ثابت."},
  "answer": true
}'),
('7-algebre-bases', 6, 'mcq', '{
  "prompt": {"en": "A pump extracts 20 litres of water per second. How much does it extract in 45 seconds?", "fr": "Une pompe extrait 20 litres d''eau par seconde. Quelle quantité extrait-elle en 45 secondes ?", "ar": "تستخرج مضخّة 20 لترا من الماء في كلّ ثانية. كم لترا تستخرج في 45 ثانية؟"},
  "choices": [{"en": "900 L", "fr": "900 L", "ar": "900 لتر"}, {"en": "800 L", "fr": "800 L", "ar": "800 لتر"}, {"en": "700 L", "fr": "700 L", "ar": "700 لتر"}, {"en": "950 L", "fr": "950 L", "ar": "950 لتر"}],
  "correctIndex": 0
}'),
('7-algebre-bases', 7, 'mcq', '{
  "prompt": {"en": "A rectangle has an area of 36 m². If its width is 4 m, what is its length?", "fr": "Un rectangle a une aire de 36 m². Si sa largeur est 4 m, quelle est sa longueur ?", "ar": "لمستطيل مساحة 36 م². إذا كان عرضه 4 أمتار، فما هو طوله؟"},
  "choices": [{"en": "9 m", "fr": "9 m", "ar": "9 أمتار"}, {"en": "8 m", "fr": "8 m", "ar": "8 أمتار"}, {"en": "6 m", "fr": "6 m", "ar": "6 أمتار"}, {"en": "12 m", "fr": "12 m", "ar": "12 مترا"}],
  "correctIndex": 0
}'),
('7-algebre-bases', 8, 'sort_buckets', '{
  "prompt": {"en": "Sort each situation", "fr": "Classe chaque situation", "ar": "صنّف كلّ وضعية"},
  "buckets": [{"en": "Direct proportionality", "fr": "Proportionnalité directe", "ar": "تناسب طردي"}, {"en": "Inverse proportionality", "fr": "Proportionnalité inverse", "ar": "تناسب عكسي"}],
  "items": [
    {"label": {"en": "Total price = number of items × unit price", "fr": "Prix total = nombre d''objets × prix unitaire", "ar": "الثمن الجملي = عدد الأشياء × ثمن الواحدة"}, "bucket": 0},
    {"label": {"en": "For a fixed area, length × width = constant", "fr": "Pour une aire fixe, longueur × largeur = constante", "ar": "لمساحة ثابتة، الطول × العرض = ثابت"}, "bucket": 1},
    {"label": {"en": "Distance travelled at constant speed vs. time", "fr": "Distance parcourue à vitesse constante et temps", "ar": "المسافة المقطوعة بسرعة ثابتة والزمن"}, "bucket": 0},
    {"label": {"en": "42 pupils split into equal groups: number of groups × pupils per group", "fr": "42 élèves répartis en groupes égaux : nombre de groupes × élèves par groupe", "ar": "توزيع 42 تلميذا إلى أفواج متكافئة: عدد الأفواج × عدد التلاميذ بالفوج"}, "bucket": 1}
  ]
}'),
('7-algebre-bases', 9, 'multi_select', '{
  "prompt": {"en": "Select every correct literal expression for \"twice a number x, plus 3\".", "fr": "Sélectionne les expressions littérales correctes pour \"le double d''un nombre x augmenté de 3\".", "ar": "اختر العبارات الحرفيّة الصحيحة لـ\"ضعف عدد x مزيدا بـ3\"."},
  "options": [{"en": "2x + 3", "fr": "2x + 3", "ar": "2x + 3"}, {"en": "x + 2 + 3", "fr": "x + 2 + 3", "ar": "x + 2 + 3"}, {"en": "2(x + 3)", "fr": "2(x + 3)", "ar": "2(x + 3)"}, {"en": "3 + 2x", "fr": "3 + 2x", "ar": "3 + 2x"}],
  "correct": [0, 3]
}'),
('7-algebre-bases', 10, 'maze', '{
  "prompt": {"en": "Solve each equation to move forward!", "fr": "Résous chaque équation pour avancer !", "ar": "حلّ كلّ معادلة للتقدّم!"},
  "layout": ["S#...#", ".#.#..", "..*#.#", "#.#.*.", "....#.", "##..*G"],
  "checkpoints": [
    {"prompt": {"en": "x + 5 = 12. x = ?", "fr": "x + 5 = 12. x = ?", "ar": "x + 5 = 12. ما هو x؟"}, "choices": [{"en": "5", "fr": "5", "ar": "5"}, {"en": "6", "fr": "6", "ar": "6"}, {"en": "7", "fr": "7", "ar": "7"}, {"en": "8", "fr": "8", "ar": "8"}], "correctIndex": 2},
    {"prompt": {"en": "3x = 18. x = ?", "fr": "3x = 18. x = ?", "ar": "3x = 18. ما هو x؟"}, "choices": [{"en": "5", "fr": "5", "ar": "5"}, {"en": "6", "fr": "6", "ar": "6"}, {"en": "7", "fr": "7", "ar": "7"}, {"en": "9", "fr": "9", "ar": "9"}], "correctIndex": 1},
    {"prompt": {"en": "x − 4 = 10. x = ?", "fr": "x − 4 = 10. x = ?", "ar": "x − 4 = 10. ما هو x؟"}, "choices": [{"en": "12", "fr": "12", "ar": "12"}, {"en": "13", "fr": "13", "ar": "13"}, {"en": "14", "fr": "14", "ar": "14"}, {"en": "15", "fr": "15", "ar": "15"}], "correctIndex": 2}
  ]
}'),
('7-algebre-bases', 11, 'match_pairs', '{
  "prompt": {"en": "Match each situation to its type of proportionality", "fr": "Associe chaque situation à son type de proportionnalité", "ar": "طابق كلّ وضعية بنوع التناسب المناسب لها"},
  "pairs": [
    {"left": {"en": "Constant speed: distance and time", "fr": "Vitesse constante : distance et temps", "ar": "سرعة ثابتة: المسافة والزمن"}, "right": {"en": "Direct proportionality", "fr": "Proportionnalité directe", "ar": "تناسب طردي"}},
    {"left": {"en": "Fixed area: length and width", "fr": "Aire fixe : longueur et largeur", "ar": "مساحة ثابتة: الطول والعرض"}, "right": {"en": "Inverse proportionality", "fr": "Proportionnalité inverse", "ar": "تناسب عكسي"}},
    {"left": {"en": "Total price and number of items at the same unit price", "fr": "Prix total et nombre d''articles au même prix unitaire", "ar": "الثمن الجملي وعدد القطع بنفس ثمن الوحدة"}, "right": {"en": "Direct proportionality", "fr": "Proportionnalité directe", "ar": "تناسب طردي"}},
    {"left": {"en": "Number of groups and group size for a fixed total", "fr": "Nombre de groupes et taille des groupes pour un effectif fixe", "ar": "عدد الأفواج وعدد كلّ فوج لعدد جملي ثابت"}, "right": {"en": "Inverse proportionality", "fr": "Proportionnalité inverse", "ar": "تناسب عكسي"}}
  ]
}'),
('7-algebre-bases', 12, 'number_line', '{
  "prompt": {"en": "Place the solution of 2x + 1 = 9 on the line.", "fr": "Place la solution de l''équation 2x + 1 = 9 sur la ligne.", "ar": "ضع حلّ المعادلة 2x + 1 = 9 على الخطّ."},
  "min": 0, "max": 10, "step": 1, "target": 4, "tolerance": 0.4
}');
