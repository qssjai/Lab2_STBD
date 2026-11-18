--тести для уроків, у яких їх ще немає
INSERT INTO quizzes (lesson_id, title, pass_score)
SELECT l.id, 'Тест: ' || l.title, 60
FROM lessons l
WHERE l.is_deleted = FALSE
  AND NOT EXISTS (SELECT 1 FROM quizzes q WHERE q.lesson_id = l.id);

--питання для тестів, у яких їх ще немає
INSERT INTO quiz_questions (quiz_id, text)
SELECT q.id, 'Питання ' || g || ' до теми: ' || q.title
FROM quizzes q
CROSS JOIN generate_series(1, 10) AS g
WHERE NOT EXISTS (SELECT 1 FROM quiz_questions qq WHERE qq.quiz_id = q.id);

--варіанти відповідей для питань, у яких їх ще немає
INSERT INTO quiz_options (question_id, text, is_correct)
SELECT qq.id, 'Варіант ' || o, (o = 1)
FROM quiz_questions qq
CROSS JOIN generate_series(1, 4) AS o
WHERE NOT EXISTS (SELECT 1 FROM quiz_options qo WHERE qo.question_id = qq.id);


-- Перевірка
SELECT (SELECT COUNT(*) FROM quizzes)        AS quizzes,
       (SELECT COUNT(*) FROM quiz_questions) AS questions,
       (SELECT COUNT(*) FROM quiz_options)   AS options;
