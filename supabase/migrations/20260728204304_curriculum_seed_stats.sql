-- supabase/migrations/0003_curriculum_seed_stats.sql

insert into curriculum_chapters (id, level, theme, title, subtitle, icon, sort_order)
values (
  '7-stats-probas',
  '7',
  'numeric',
  '{"en": "Statistics & probability", "fr": "Statistiques et probabilités", "ar": "الإحصاء والاحتمالات"}',
  '{"en": "Reading data and chance", "fr": "Lire des données et le hasard", "ar": "قراءة المعطيات والصدفة"}',
  '📊',
  2
)
on conflict (id) do nothing;

insert into curriculum_questions (chapter_id, sort_order, kind, payload) values
('7-stats-probas', 1, 'input', '{
  "prompt": {"en": "A die is rolled 40 times. The result 2 came up 8 times. What is the frequency of 2, as a percentage?", "fr": "Un dé est lancé 40 fois. Le résultat 2 est sorti 8 fois. Quelle est la fréquence de 2, en pourcentage ?", "ar": "رُمي نرد 40 مرّة. ظهر العدد 2 في 8 مرّات. ما هو التواتر المئوي للعدد 2؟"},
  "accepted": ["20", "20%"]
}'),
('7-stats-probas', 2, 'mcq', '{
  "prompt": {"en": "On a family''s expense pie chart, food is 20% of a 3500-dinar total. How much is spent on food?", "fr": "Sur le diagramme circulaire des dépenses d''une famille, l''alimentation représente 20% d''un budget total de 3500 dinars. Quelle somme est consacrée à l''alimentation ?", "ar": "في المخطط الدائري لمصاريف عائلة، يمثّل الغذاء 20% من مجموع 3500 دينار. كم دينارا يُخصّص للغذاء؟"},
  "choices": [{"en": "700 dinars", "fr": "700 dinars", "ar": "700 دينار"}, {"en": "800 dinars", "fr": "800 dinars", "ar": "800 دينار"}, {"en": "600 dinars", "fr": "600 dinars", "ar": "600 دينار"}, {"en": "750 dinars", "fr": "750 dinars", "ar": "750 دينارا"}],
  "correctIndex": 0
}'),
('7-stats-probas', 3, 'true_false', '{
  "statement": {"en": "The mode of a statistical series is the value that appears most often.", "fr": "Le mode d''une série statistique est la valeur qui apparaît le plus souvent.", "ar": "المنوال في سلسلة إحصائيّة هو القيمة الأكثر تكرارا."},
  "answer": true
}'),
('7-stats-probas', 4, 'true_false', '{
  "statement": {"en": "The range of a series is the difference between its largest and smallest values.", "fr": "L''étendue d''une série est la différence entre la plus grande et la plus petite valeur.", "ar": "المدى في سلسلة هو الفرق بين أكبر قيمة وأصغر قيمة."},
  "answer": true
}'),
('7-stats-probas', 5, 'drag_fill', '{
  "prompt": {"en": "In a class, the grades are 9, 10, 10, 12, 15. The total headcount is ___.", "fr": "Dans une classe, les notes sont : 9, 10, 10, 12, 15. L''effectif total est ___.", "ar": "في قسم، المعدّلات هي: 9، 10، 10، 12، 15. العدد الجملي للتلاميذ هو ___."},
  "choices": ["4", "5", "6", "7"],
  "correctIndex": 1
}'),
('7-stats-probas', 6, 'multi_select', '{
  "prompt": {"en": "A bag has red, grey, blue and green candies. Check the colours with more than 10 candies.", "fr": "Un sac contient des bonbons rouges, gris, bleus et verts. Coche les couleurs dont l''effectif est supérieur à 10.", "ar": "يحتوي كيس على قطع حلوى حمراء ورمادية وزرقاء وخضراء. اختر الألوان التي تكرارها أكبر من 10."},
  "options": [{"en": "Red (12)", "fr": "Rouge (12)", "ar": "أحمر (12)"}, {"en": "Grey (4)", "fr": "Gris (4)", "ar": "رمادي (4)"}, {"en": "Blue (23)", "fr": "Bleu (23)", "ar": "أزرق (23)"}, {"en": "Green (1)", "fr": "Vert (1)", "ar": "أخضر (1)"}],
  "correct": [0, 2]
}'),
('7-stats-probas', 7, 'mcq', '{
  "prompt": {"en": "A bag has 40 candies: 12 red, 4 grey, 23 blue and 1 green. What is the probability of drawing a blue one?", "fr": "Un sac contient 40 bonbons : 12 rouges, 4 gris, 23 bleus et 1 vert. Quelle est la probabilité de tirer un bonbon bleu ?", "ar": "يحتوي كيس على 40 قطعة حلوى: 12 حمراء و4 رمادية و23 زرقاء وواحدة خضراء. ما احتمال سحب قطعة زرقاء؟"},
  "choices": [{"en": "23/40", "fr": "23/40", "ar": "23/40"}, {"en": "12/40", "fr": "12/40", "ar": "12/40"}, {"en": "4/40", "fr": "4/40", "ar": "4/40"}, {"en": "1/40", "fr": "1/40", "ar": "1/40"}],
  "correctIndex": 0
}'),
('7-stats-probas', 8, 'sort_buckets', '{
  "prompt": {"en": "Sort each event", "fr": "Classe chaque événement", "ar": "صنّف كلّ حدث"},
  "buckets": [{"en": "Certain", "fr": "Certain", "ar": "أكيد"}, {"en": "Impossible", "fr": "Impossible", "ar": "مستحيل"}, {"en": "Possible", "fr": "Possible", "ar": "ممكن"}],
  "items": [
    {"label": {"en": "Rolling an even number on a 6-sided die", "fr": "Obtenir un nombre pair en lançant un dé à 6 faces", "ar": "الحصول على عدد زوجي برمي نرد ذي 6 أوجه"}, "bucket": 2},
    {"label": {"en": "Rolling a number greater than 6 on a 6-sided die", "fr": "Obtenir un nombre supérieur à 6 avec un dé à 6 faces", "ar": "الحصول على عدد أكبر من 6 برمي نرد ذي 6 أوجه"}, "bucket": 1},
    {"label": {"en": "Rolling a number less than 7 on a 6-sided die", "fr": "Obtenir un nombre inférieur à 7 avec un dé à 6 faces", "ar": "الحصول على عدد أصغر من 7 برمي نرد ذي 6 أوجه"}, "bucket": 0},
    {"label": {"en": "Drawing a red marble from a bag that only has red marbles", "fr": "Tirer une bille rouge d''un sac qui ne contient que des billes rouges", "ar": "سحب كرة حمراء من كيس لا يحتوي إلّا على كرات حمراء"}, "bucket": 0}
  ]
}'),
('7-stats-probas', 9, 'maze', '{
  "prompt": {"en": "Answer each probability question to move forward!", "fr": "Réponds à chaque question de probabilité pour avancer !", "ar": "أجب عن كلّ سؤال احتمالات للتقدّم!"},
  "layout": ["S#...#", ".#.#..", "..*#.#", "#.#.*.", "....#.", "##..*G"],
  "checkpoints": [
    {"prompt": {"en": "A coin is tossed. What is the probability of getting heads?", "fr": "Une pièce de monnaie est lancée. Quelle est la probabilité d''obtenir pile ?", "ar": "تُقذف قطعة نقدية. ما احتمال الحصول على ''بيلة''؟"}, "choices": [{"en": "1/2", "fr": "1/2", "ar": "1/2"}, {"en": "1/3", "fr": "1/3", "ar": "1/3"}, {"en": "1", "fr": "1", "ar": "1"}, {"en": "0", "fr": "0", "ar": "0"}], "correctIndex": 0},
    {"prompt": {"en": "A 6-sided die is rolled. Probability of a multiple of 3 (3 or 6)?", "fr": "Un dé à 6 faces est lancé. Probabilité d''obtenir un multiple de 3 (3 ou 6) ?", "ar": "يُرمى نرد ذو 6 أوجه. ما احتمال الحصول على مضاعف لـ3 (3 أو 6)؟"}, "choices": [{"en": "1/6", "fr": "1/6", "ar": "1/6"}, {"en": "2/6", "fr": "2/6", "ar": "2/6"}, {"en": "3/6", "fr": "3/6", "ar": "3/6"}, {"en": "4/6", "fr": "4/6", "ar": "4/6"}], "correctIndex": 1},
    {"prompt": {"en": "An urn has 5 balls numbered 1 to 5. Probability of drawing an even number?", "fr": "Une urne contient 5 boules numérotées de 1 à 5. Probabilité de tirer un numéro pair ?", "ar": "تحتوي قارورة على 5 كرات مرقّمة من 1 إلى 5. ما احتمال سحب رقم زوجي؟"}, "choices": [{"en": "2/5", "fr": "2/5", "ar": "2/5"}, {"en": "1/5", "fr": "1/5", "ar": "1/5"}, {"en": "3/5", "fr": "3/5", "ar": "3/5"}, {"en": "5/5", "fr": "5/5", "ar": "5/5"}], "correctIndex": 0}
  ]
}'),
('7-stats-probas', 10, 'match_pairs', '{
  "prompt": {"en": "Match each statistics term to its definition", "fr": "Associe chaque terme statistique à sa définition", "ar": "طابق كلّ مصطلح إحصائيّ بتعريفه"},
  "pairs": [
    {"left": {"en": "Total headcount", "fr": "Effectif total", "ar": "العدد الجملي"}, "right": {"en": "The total number of elements in the series", "fr": "Nombre total d''éléments de la série", "ar": "مجموع عناصر السلسلة"}},
    {"left": {"en": "Range", "fr": "Étendue", "ar": "المدى"}, "right": {"en": "Difference between the largest and smallest value", "fr": "Différence entre la plus grande et la plus petite valeur", "ar": "الفرق بين أكبر قيمة وأصغر قيمة"}},
    {"left": {"en": "Mode", "fr": "Mode", "ar": "المنوال"}, "right": {"en": "The most frequent value", "fr": "La valeur la plus fréquente", "ar": "القيمة الأكثر تكرارا"}},
    {"left": {"en": "Frequency", "fr": "Fréquence", "ar": "التواتر"}, "right": {"en": "A value''s headcount divided by the total headcount", "fr": "Effectif d''une valeur divisé par l''effectif total", "ar": "تكرار قيمة مقسوما على العدد الجملي"}}
  ]
}'),
('7-stats-probas', 11, 'number_line', '{
  "prompt": {"en": "Place the frequency 8/40 (as a %) on the line.", "fr": "Place la fréquence 8/40 (en %) sur la ligne.", "ar": "ضع التواتر 8/40 (كنسبة مئوية) على الخطّ."},
  "min": 0, "max": 100, "step": 5, "target": 20, "tolerance": 2
}');
