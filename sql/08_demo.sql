-- 1. Представлення (views)

-- 1.1 Каталог активних курсів
SELECT * FROM v_active_courses ORDER BY id;

-- 1.2 Курси та викладачі
SELECT * FROM v_course_instructors ORDER BY course_title, instructor_name;

-- 1.3 Прогрес студентів
SELECT student_name, course_title, status, progress, completed_lessons, total_lessons
FROM v_student_progress
ORDER BY course_title, student_name;

-- 1.4 Здані роботи та статус перевірки
SELECT student_name, assignment_title, score, max_score, grading_status, graded_by_name
FROM v_submissions_overview
ORDER BY submission_id;

-- 1.5 Виручка по курсах
SELECT * FROM v_course_revenue ORDER BY total_revenue DESC;

-- 1.6 Структура курсу (курс, модуль, урок)
SELECT * FROM v_course_structure
ORDER BY course_id, module_position, lesson_position;

-- 1.7 Рейтинг курсів
SELECT * FROM v_course_rating ORDER BY avg_rating DESC NULLS LAST;

-- 1.8 Активні користувачі з ролями
SELECT * FROM v_active_users ORDER BY role_name, last_name;


-- 2. Функції

-- 2.1 Прогрес: значення з функції порівнюється зі збереженим у таблиці
SELECT sp.student_name,
       sp.course_title,
       fn_course_progress(sp.enrollment_id)     AS progress_by_function,
       sp.progress                              AS progress_stored,
       fn_is_course_completed(sp.enrollment_id) AS is_completed
FROM v_student_progress sp
ORDER BY sp.course_title, sp.student_name;

-- 2.2 Середній результат студентів за оціненими завданнями (%)
SELECT u.full_name, fn_student_avg_score(u.id) AS avg_score_percent
FROM v_active_users u
WHERE u.role_name = 'student'
ORDER BY avg_score_percent DESC;

-- 2.3 Рейтинг і кількість уроків по курсах
SELECT c.title,
       fn_course_avg_rating(c.id)    AS avg_rating,
       fn_course_lessons_count(c.id) AS lessons_count
FROM courses c
WHERE c.is_deleted = FALSE
ORDER BY c.title;

-- 2.4 Повнотекстовий пошук курсів
SELECT * FROM fn_search_courses('sql');

-- 2.5 Номер сертифіката та виданий сертифікат
SELECT c.id, c.number, c.issued_at, fn_generate_certificate_number(c.enrollment_id) AS generated_number
FROM certificates c;


-- 3. Soft delete

-- 3.1 М'яко видалені записи: курс, модуль, урок та хто їх видалив
SELECT 'courses' AS table_name, c.id, c.title AS name, c.deleted_at, u.full_name AS deleted_by
FROM courses c LEFT JOIN v_active_users u ON u.id = c.deleted_by
WHERE c.is_deleted = TRUE
UNION ALL
SELECT 'modules', m.id, m.title, m.deleted_at, u.full_name
FROM modules m LEFT JOIN v_active_users u ON u.id = m.deleted_by
WHERE m.is_deleted = TRUE
UNION ALL
SELECT 'lessons', l.id, l.title, l.deleted_at, u.full_name
FROM lessons l LEFT JOIN v_active_users u ON u.id = l.deleted_by
WHERE l.is_deleted = TRUE;

-- 3.2 Спроба фізичного видалення. Очікується помилка від тригера
DELETE FROM courses WHERE title LIKE 'Тестовий курс%';

-- 3.3 Відновлення курсу та повторне видалення
DO $$
DECLARE
    k INT;
    a INT;
BEGIN
    SELECT id INTO k FROM courses WHERE title LIKE 'Тестовий курс%';
    SELECT id INTO a FROM users WHERE email = 'admin@courses.ua';

    CALL sp_restore_course(k, a);
    RAISE NOTICE 'Після відновлення: курс видалений = %, модулів видалено = %, уроків видалено = %',
        (SELECT is_deleted FROM courses WHERE id = k),
        (SELECT COUNT(*) FROM modules WHERE course_id = k AND is_deleted),
        (SELECT COUNT(*) FROM lessons l JOIN modules m ON m.id = l.module_id
         WHERE m.course_id = k AND l.is_deleted);

    CALL sp_soft_delete_course(k, a);
    RAISE NOTICE 'Після видалення: курс видалений = %, модулів видалено = %, уроків видалено = %',
        (SELECT is_deleted FROM courses WHERE id = k),
        (SELECT COUNT(*) FROM modules WHERE course_id = k AND is_deleted),
        (SELECT COUNT(*) FROM lessons l JOIN modules m ON m.id = l.module_id
         WHERE m.course_id = k AND l.is_deleted);
END;
$$;


-- 4. Дата та автор останньої зміни, журнал аудиту

-- 4.1 Змінюємо ціну курсу від імені викладача
DO $$
DECLARE
    k INT; c INT; l INT; d TEXT; i1 INT;
BEGIN
    SELECT id, category_id, level_id, description INTO k, c, l, d
    FROM courses WHERE title = 'SQL та PostgreSQL з нуля';
    SELECT id INTO i1 FROM users WHERE email = 'shevchuk@courses.ua';

    CALL sp_update_course(k, 'SQL та PostgreSQL з нуля', d, c, l, 1250, i1);
END;
$$;

-- 4.2 Результат: updated_at та updated_by заповнені тригером
SELECT c.title, c.price, c.created_at, c.updated_at, u.full_name AS updated_by
FROM courses c
LEFT JOIN v_active_users u ON u.id = c.updated_by
WHERE c.title = 'SQL та PostgreSQL з нуля';

-- 4.3 Журнал аудиту: старе та нове значення ціни
SELECT a.id, a.table_name, a.record_id, a.action, u.full_name AS changed_by, a.changed_at,
       a.old_data ->> 'price' AS old_price,
       a.new_data ->> 'price' AS new_price
FROM audit_log a
LEFT JOIN v_active_users u ON u.id = a.changed_by
WHERE a.table_name = 'courses' AND a.action = 'UPDATE'
ORDER BY a.id DESC
LIMIT 5;

-- 4.4 Кількість записів аудиту по таблицях і діях
SELECT table_name, action, COUNT(*) AS records
FROM audit_log
GROUP BY table_name, action
ORDER BY table_name, action;


-- 5. Бізнес-правила. Кожен блок має завершитися помилкою (це нормально)

-- 5.1 Оцінка вища за максимальний бал
DO $$
DECLARE
    s INT; g INT;
BEGIN
    SELECT submission_id INTO s FROM v_submissions_overview
    WHERE grading_status = 'pending' LIMIT 1;
    SELECT id INTO g FROM users WHERE email = 'shevchuk@courses.ua';
    CALL sp_grade_submission(s, 150, g);
END;
$$;

-- 5.2 Відгук від студента, який не записаний на курс
DO $$
DECLARE
    k INT; u INT; r INT;
BEGIN
    SELECT id INTO k FROM courses WHERE title = 'SQL та PostgreSQL з нуля';
    SELECT id INTO u FROM users WHERE email = 'oleh@student.ua';
    CALL sp_add_review(k, u, 5, 'Відгук без запису на курс', r);
END;
$$;

-- 5.3 Повторний запис на той самий курс
DO $$
DECLARE
    k INT; u INT; a INT; e INT;
BEGIN
    SELECT id INTO k FROM courses WHERE title = 'SQL та PostgreSQL з нуля';
    SELECT id INTO u FROM users WHERE email = 'sofiia@student.ua';
    SELECT id INTO a FROM users WHERE email = 'admin@courses.ua';
    CALL sp_enroll_student(u, k, a, e);
END;
$$;

-- 5.4 Публікація курсу без уроків
DO $$
DECLARE
    k INT; c INT; l INT; a INT;
BEGIN
    SELECT id INTO c FROM categories WHERE name = 'Дизайн';
    SELECT id INTO l FROM course_levels WHERE name = 'Початковий';
    SELECT id INTO a FROM users WHERE email = 'admin@courses.ua';
    CALL sp_create_course('Порожній курс', NULL, c, l, 0, a, k);
    CALL sp_publish_course(k, a);
END;
$$;

-- 5.5 Видача сертифіката студенту, який не пройшов курс
DO $$
DECLARE
    e INT; a INT; cert INT;
BEGIN
    SELECT enrollment_id INTO e FROM v_student_progress
    WHERE student_name = 'Дора Жук' LIMIT 1;
    SELECT id INTO a FROM users WHERE email = 'admin@courses.ua';
    CALL sp_issue_certificate(e, a, cert);
END;
$$;


-- 6. Підсумок: кількість об'єктів бази даних
SELECT 'Таблиці' AS object_type, COUNT(*) AS total
FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
UNION ALL
SELECT 'Представлення', COUNT(*) FROM information_schema.views WHERE table_schema = 'public'
UNION ALL
SELECT 'Функції', COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prokind = 'f'
UNION ALL
SELECT 'Збережені процедури', COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prokind = 'p'
UNION ALL
SELECT 'Тригери', COUNT(*) FROM pg_trigger WHERE NOT tgisinternal
UNION ALL
SELECT 'Індекси', COUNT(*) FROM pg_indexes WHERE schemaname = 'public';


-- 7. Ефективність індексів (EXPLAIN ANALYZE)

-- 7.0 Генерація: 50 000 курсів і 300 000 платежів

ALTER TABLE courses  DISABLE TRIGGER USER;
ALTER TABLE payments DISABLE TRIGGER USER;

DELETE FROM payments WHERE status = 'failed' AND amount = 0.01;
DELETE FROM courses  WHERE title LIKE 'Demo course %';

CREATE INDEX IF NOT EXISTS idx_courses_fts
    ON courses
    USING GIN (to_tsvector('simple', title || ' ' || COALESCE(description, '')));

CREATE INDEX IF NOT EXISTS idx_courses_title_active
    ON courses (title)
    WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_payments_paid_at_brin
    ON payments
    USING BRIN (paid_at);

INSERT INTO courses (title, description, category_id, level_id, price, status)
SELECT 'Demo course ' || g || CASE WHEN g % 500 = 0 THEN ' postgresql' ELSE '' END,
       'Опис демонстраційного курсу номер ' || g,
       (SELECT id FROM categories WHERE name = 'Програмування'),
       (SELECT id FROM course_levels WHERE name = 'Початковий'),
       (g % 100) * 10,
       'published'
FROM generate_series(1, 50000) AS g;

INSERT INTO payments (enrollment_id, amount, paid_at, status)
SELECT (SELECT id FROM enrollments ORDER BY id LIMIT 1),
       0.01,
       TIMESTAMP '2025-01-01' + g * INTERVAL '2 minutes',
       'failed'
FROM generate_series(1, 300000) AS g;

ALTER TABLE courses  ENABLE TRIGGER USER;
ALTER TABLE payments ENABLE TRIGGER USER;

ANALYZE courses;
ANALYZE payments;

-- перевірка: має бути 50000 і 300000
SELECT (SELECT COUNT(*) FROM courses  WHERE title LIKE 'Demo course %')           AS demo_courses,
       (SELECT COUNT(*) FROM payments WHERE status = 'failed' AND amount = 0.01) AS demo_payments;

-- 7.1 GIN: повнотекстовий пошук. СПОЧАТКУ БЕЗ ІНДЕКСУ
DROP INDEX idx_courses_fts;

EXPLAIN ANALYZE
SELECT id, title FROM courses
WHERE to_tsvector('simple', title || ' ' || COALESCE(description, ''))
      @@ plainto_tsquery('simple', 'postgresql');

-- 7.2 GIN: ТЕПЕР З ІНДЕКСОМ
CREATE INDEX idx_courses_fts
    ON courses
    USING GIN (to_tsvector('simple', title || ' ' || COALESCE(description, '')));

ANALYZE courses;

EXPLAIN ANALYZE
SELECT id, title FROM courses
WHERE to_tsvector('simple', title || ' ' || COALESCE(description, ''))
      @@ plainto_tsquery('simple', 'postgresql');

-- 7.3 Partial B-tree: пошук активного курсу за назвою. БЕЗ ІНДЕКСУ
DROP INDEX idx_courses_title_active;

EXPLAIN ANALYZE
SELECT id, title FROM courses
WHERE is_deleted = FALSE AND title = 'Demo course 25000';

-- 7.4 Partial B-tree: З ІНДЕКСОМ
CREATE INDEX idx_courses_title_active
    ON courses (title)
    WHERE is_deleted = FALSE;

ANALYZE courses;

EXPLAIN ANALYZE
SELECT id, title FROM courses
WHERE is_deleted = FALSE AND title = 'Demo course 25000';

-- 7.5 BRIN: платежі за добу. БЕЗ ІНДЕКСУ
DROP INDEX idx_payments_paid_at_brin;

EXPLAIN ANALYZE
SELECT COUNT(*), SUM(amount) FROM payments
WHERE paid_at >= '2025-06-01' AND paid_at < '2025-06-02';

-- 7.6 BRIN: З ІНДЕКСОМ
CREATE INDEX idx_payments_paid_at_brin
    ON payments
    USING BRIN (paid_at);

ANALYZE payments;

EXPLAIN ANALYZE
SELECT COUNT(*), SUM(amount) FROM payments
WHERE paid_at >= '2025-06-01' AND paid_at < '2025-06-02';

-- 7.7 Розмір індексів: BRIN значно менший за B-tree і GIN
SELECT indexrelname AS index_name,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE indexrelname IN ('idx_courses_fts', 'idx_courses_title_active', 'idx_payments_paid_at_brin')
ORDER BY indexrelname;

-- 7.8 Очищення: видаляємо згенеровані дані (тригер заборони DELETE тимчасово вимикаємо)
ALTER TABLE courses  DISABLE TRIGGER USER;
ALTER TABLE payments DISABLE TRIGGER USER;

DELETE FROM payments WHERE status = 'failed' AND amount = 0.01;
DELETE FROM courses  WHERE title LIKE 'Demo course %';

ALTER TABLE courses  ENABLE TRIGGER USER;
ALTER TABLE payments ENABLE TRIGGER USER;

ANALYZE courses;
ANALYZE payments;

-- 7.9 Перевірка: тригерів, що лишилися вимкненими, не має бути (порожній результат)
SELECT tgrelid::regclass AS table_name, tgname, tgenabled
FROM pg_trigger
WHERE NOT tgisinternal AND tgenabled <> 'O';