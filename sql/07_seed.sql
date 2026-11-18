-- Тестові дані

-- довідники
INSERT INTO roles (name) VALUES ('student'), ('instructor'), ('admin')
ON CONFLICT (name) DO NOTHING;

INSERT INTO course_levels (name) VALUES ('Початковий'), ('Середній'), ('Просунутий')
ON CONFLICT (name) DO NOTHING;

INSERT INTO categories (name, parent_id)
SELECT 'Програмування', NULL
WHERE NOT EXISTS (SELECT 1 FROM categories WHERE name = 'Програмування');

INSERT INTO categories (name, parent_id)
SELECT 'Бази даних', id FROM categories
WHERE name = 'Програмування'
  AND NOT EXISTS (SELECT 1 FROM categories WHERE name = 'Бази даних');

INSERT INTO categories (name, parent_id)
SELECT 'Дизайн', NULL
WHERE NOT EXISTS (SELECT 1 FROM categories WHERE name = 'Дизайн');

INSERT INTO categories (name, parent_id)
SELECT 'Аналіз даних', NULL
WHERE NOT EXISTS (SELECT 1 FROM categories WHERE name = 'Аналіз даних');


-- основні дані через збережені процедури
DO $$
DECLARE
    r_admin INT; r_instr INT; r_student INT;
    l_beg INT; l_mid INT; l_adv INT;
    c_prog INT; c_db INT; c_design INT; c_ds INT;

    u_admin INT; u_i1 INT; u_i2 INT;
    u_s1 INT; u_s2 INT; u_s3 INT; u_s4 INT; u_s5 INT;

    k1 INT; k2 INT; k3 INT; k4 INT; k5 INT;
    v_id INT; v_m INT; v_q INT; v_qq INT;
    a1 INT; a2 INT; a3 INT;
    sb1 INT; sb2 INT; sb3 INT; sb4 INT; sb5 INT;
    e_s1c1 INT; e_s1c2 INT; e_s2c1 INT; e_s3c1 INT; e_s3c3 INT; e_s4c2 INT; e_s5c3 INT;
    rec RECORD;
BEGIN
    SELECT id INTO r_admin   FROM roles WHERE name = 'admin';
    SELECT id INTO r_instr   FROM roles WHERE name = 'instructor';
    SELECT id INTO r_student FROM roles WHERE name = 'student';

    SELECT id INTO l_beg FROM course_levels WHERE name = 'Початковий';
    SELECT id INTO l_mid FROM course_levels WHERE name = 'Середній';
    SELECT id INTO l_adv FROM course_levels WHERE name = 'Просунутий';

    SELECT id INTO c_prog   FROM categories WHERE name = 'Програмування';
    SELECT id INTO c_db     FROM categories WHERE name = 'Бази даних';
    SELECT id INTO c_design FROM categories WHERE name = 'Дизайн';
    SELECT id INTO c_ds     FROM categories WHERE name = 'Аналіз даних';

    -- користувачі
    CALL sp_create_user('admin@courses.ua',   'hash_admin', 'Олена',  'Коваль',    r_admin,   NULL,    u_admin);
    CALL sp_create_user('shevchuk@courses.ua','hash_i1',    'Андрій', 'Шевчук',    r_instr,   u_admin, u_i1);
    CALL sp_create_user('ivanenko@courses.ua','hash_i2',    'Марія',  'Іваненко',  r_instr,   u_admin, u_i2);
    CALL sp_create_user('sofiia@student.ua',  'hash_s1',    'Софія',  'Макарова',  r_student, u_admin, u_s1);
    CALL sp_create_user('dora@student.ua',    'hash_s2',    'Дора',   'Жук',       r_student, u_admin, u_s2);
    CALL sp_create_user('taras@student.ua',   'hash_s3',    'Тарас',  'Бондар',    r_student, u_admin, u_s3);
    CALL sp_create_user('iryna@student.ua',   'hash_s4',    'Ірина',  'Мельник',   r_student, u_admin, u_s4);
    CALL sp_create_user('oleh@student.ua',    'hash_s5',    'Олег',   'Петренко',  r_student, u_admin, u_s5);

    INSERT INTO user_profiles (user_id, bio, phone, birth_date) VALUES
        (u_i1, 'Архітектор баз даних, 10 років досвіду', '+380501112233', '1985-04-12'),
        (u_i2, 'UX-дизайнерка та менторка',              '+380671234567', '1990-09-30'),
        (u_s1, 'Студентка 2 курсу КНУ',                  '+380931112200', '2005-06-15');

    -- курс 1: SQL
    CALL sp_create_course('SQL та PostgreSQL з нуля',
        'Вступний курс з реляційних баз даних та мови SQL', c_db, l_beg, 1200, u_i1, k1);
    CALL sp_add_course_instructor(k1, u_i1, u_admin);
    CALL sp_add_module(k1, 'Основи SQL', NULL, u_i1, v_m);
    CALL sp_add_lesson(v_m, 'Вступ до реляційних БД', 'Таблиці, ключі та зв''язки', 30, NULL, u_i1, v_id);
    CALL sp_add_lesson(v_m, 'SELECT і фільтрація',     'Вибірка даних, WHERE, ORDER BY', 45, NULL, u_i1, v_id);
    CALL sp_add_lesson(v_m, 'JOIN',                    'З''єднання таблиць', 50, NULL, u_i1, v_id);
    CALL sp_add_module(k1, 'Складні запити', NULL, u_i1, v_m);
    CALL sp_add_lesson(v_m, 'Підзапити',               'Вкладені запити та CTE', 40, NULL, u_i1, v_id);
    CALL sp_add_lesson(v_m, 'Агрегація і GROUP BY',    'COUNT, SUM, AVG, HAVING', 40, NULL, u_i1, v_id);
    CALL sp_publish_course(k1, u_i1);

    -- курс 2: C#
    CALL sp_create_course('C# для початківців',
        'Основи мови C# та об''єктно-орієнтованого програмування', c_prog, l_beg, 1500, u_i1, k2);
    CALL sp_add_course_instructor(k2, u_i1, u_admin);
    CALL sp_add_course_instructor(k2, u_i2, u_admin);
    CALL sp_add_module(k2, 'Синтаксис', NULL, u_i1, v_m);
    CALL sp_add_lesson(v_m, 'Змінні і типи',     'Типи даних C#', 30, NULL, u_i1, v_id);
    CALL sp_add_lesson(v_m, 'Умови і цикли',     'if, switch, for, while', 35, NULL, u_i1, v_id);
    CALL sp_add_module(k2, 'ООП', NULL, u_i1, v_m);
    CALL sp_add_lesson(v_m, 'Класи та екземпляри', 'Поля, методи, конструктори', 45, NULL, u_i1, v_id);
    CALL sp_add_lesson(v_m, 'Інтерфейси',          'Абстракція та поліморфізм', 40, NULL, u_i1, v_id);
    CALL sp_publish_course(k2, u_i1);

    -- курс 3: дизайн
    CALL sp_create_course('Основи UI-дизайну',
        'Колір, типографіка та прототипування інтерфейсів', c_design, l_mid, 900, u_i2, k3);
    CALL sp_add_course_instructor(k3, u_i2, u_admin);
    CALL sp_add_module(k3, 'Теорія', NULL, u_i2, v_m);
    CALL sp_add_lesson(v_m, 'Колір і типографіка', 'Палітри та шрифтові пари', 30, NULL, u_i2, v_id);
    CALL sp_add_module(k3, 'Практика', NULL, u_i2, v_m);
    CALL sp_add_lesson(v_m, 'Прототипування', 'Створення макетів у Figma', 60, NULL, u_i2, v_id);
    CALL sp_publish_course(k3, u_i2);

    -- курс 4: чернетка (не опублікований)
    CALL sp_create_course('Python для аналізу даних',
        'Pandas, NumPy та візуалізація', c_ds, l_adv, 2000, u_i2, k4);
    CALL sp_add_course_instructor(k4, u_i2, u_admin);
    CALL sp_add_module(k4, 'Pandas', NULL, u_i2, v_m);
    CALL sp_add_lesson(v_m, 'Вступ до Pandas', 'Series та DataFrame', 45, NULL, u_i2, v_id);

    -- курс 5: тестовий, одразу м'яко видаляється (демонстрація soft delete)
    CALL sp_create_course('Тестовий курс (видалений)', NULL, c_prog, l_beg, 0, u_admin, k5);
    CALL sp_add_module(k5, 'Тестовий модуль', NULL, u_admin, v_m);
    CALL sp_add_lesson(v_m, 'Тестовий урок', NULL, 10, NULL, u_admin, v_id);
    CALL sp_soft_delete_course(k5, u_admin);

    -- завдання
    INSERT INTO assignments (lesson_id, title, max_score, due_date)
    SELECT lesson_id, 'Практика: SELECT-запити', 100, CURRENT_TIMESTAMP + INTERVAL '14 days'
    FROM v_course_structure WHERE lesson_title = 'SELECT і фільтрація'
    RETURNING id INTO a1;

    INSERT INTO assignments (lesson_id, title, max_score, due_date)
    SELECT lesson_id, 'Практика: JOIN', 100, CURRENT_TIMESTAMP + INTERVAL '21 days'
    FROM v_course_structure WHERE lesson_title = 'JOIN'
    RETURNING id INTO a2;

    INSERT INTO assignments (lesson_id, title, max_score, due_date)
    SELECT lesson_id, 'Калькулятор на C#', 50, CURRENT_TIMESTAMP + INTERVAL '14 days'
    FROM v_course_structure WHERE lesson_title = 'Класи та екземпляри'
    RETURNING id INTO a3;

    -- тест до уроку JOIN
    INSERT INTO quizzes (lesson_id, title, pass_score)
    SELECT lesson_id, 'Тест: JOIN', 60
    FROM v_course_structure WHERE lesson_title = 'JOIN'
    RETURNING id INTO v_q;

    INSERT INTO quiz_questions (quiz_id, text)
    VALUES (v_q, 'Який оператор поєднує рядки двох таблиць за умовою?')
    RETURNING id INTO v_qq;
    INSERT INTO quiz_options (question_id, text, is_correct) VALUES
        (v_qq, 'JOIN', TRUE), (v_qq, 'GROUP BY', FALSE), (v_qq, 'LIMIT', FALSE);

    INSERT INTO quiz_questions (quiz_id, text)
    VALUES (v_q, 'Який JOIN повертає всі рядки лівої таблиці?')
    RETURNING id INTO v_qq;
    INSERT INTO quiz_options (question_id, text, is_correct) VALUES
        (v_qq, 'LEFT JOIN', TRUE), (v_qq, 'INNER JOIN', FALSE), (v_qq, 'CROSS JOIN', FALSE);

    -- записи студентів на курси
    CALL sp_enroll_student(u_s1, k1, u_admin, e_s1c1);
    CALL sp_enroll_student(u_s1, k2, u_admin, e_s1c2);
    CALL sp_enroll_student(u_s2, k1, u_admin, e_s2c1);
    CALL sp_enroll_student(u_s3, k1, u_admin, e_s3c1);
    CALL sp_enroll_student(u_s3, k3, u_admin, e_s3c3);
    CALL sp_enroll_student(u_s4, k2, u_admin, e_s4c2);
    CALL sp_enroll_student(u_s5, k3, u_admin, e_s5c3);

    -- платежі
    CALL sp_register_payment(e_s1c1, 1200, 'paid', u_admin, v_id);
    CALL sp_register_payment(e_s1c2, 1500, 'paid', u_admin, v_id);
    CALL sp_register_payment(e_s2c1, 1200, 'paid', u_admin, v_id);
    CALL sp_register_payment(e_s3c1, 1200, 'paid', u_admin, v_id);
    CALL sp_register_payment(e_s3c3,  900, 'paid', u_admin, v_id);
    CALL sp_register_payment(e_s4c2, 1500, 'paid', u_admin, v_id);
    CALL sp_register_payment(e_s5c3,  900, 'pending', u_admin, v_id);

    -- пройдені уроки (прогрес рахує тригер)
    FOR rec IN SELECT lesson_id FROM v_course_structure
               WHERE course_id = k1 ORDER BY module_position, lesson_position LOOP
        CALL sp_complete_lesson(e_s1c1, rec.lesson_id, u_s1);
    END LOOP;

    FOR rec IN SELECT lesson_id FROM v_course_structure
               WHERE course_id = k2 ORDER BY module_position, lesson_position LIMIT 2 LOOP
        CALL sp_complete_lesson(e_s1c2, rec.lesson_id, u_s1);
    END LOOP;

    FOR rec IN SELECT lesson_id FROM v_course_structure
               WHERE course_id = k1 ORDER BY module_position, lesson_position LIMIT 3 LOOP
        CALL sp_complete_lesson(e_s2c1, rec.lesson_id, u_s2);
    END LOOP;

    FOR rec IN SELECT lesson_id FROM v_course_structure
               WHERE course_id = k1 ORDER BY module_position, lesson_position LIMIT 1 LOOP
        CALL sp_complete_lesson(e_s3c1, rec.lesson_id, u_s3);
    END LOOP;

    FOR rec IN SELECT lesson_id FROM v_course_structure
               WHERE course_id = k2 ORDER BY module_position, lesson_position LIMIT 1 LOOP
        CALL sp_complete_lesson(e_s4c2, rec.lesson_id, u_s4);
    END LOOP;

    -- здані роботи та оцінки
    CALL sp_submit_assignment(a1, u_s1, 'Мої запити до таблиць courses та users', sb1);
    CALL sp_submit_assignment(a2, u_s1, 'Запити з INNER та LEFT JOIN', sb2);
    CALL sp_submit_assignment(a1, u_s2, 'Розв''язок практичного завдання', sb3);
    CALL sp_submit_assignment(a1, u_s3, 'Виконане завдання з SELECT', sb4);
    CALL sp_submit_assignment(a3, u_s1, 'Консольний калькулятор', sb5);

    CALL sp_grade_submission(sb1, 95, u_i1);
    CALL sp_grade_submission(sb2, 88, u_i1);
    CALL sp_grade_submission(sb3, 70, u_i1);
    CALL sp_grade_submission(sb5, 45, u_i1);
    -- sb4 (Тарас) залишається неоціненою

    -- сертифікат для студентки, яка пройшла курс повністю
    CALL sp_issue_certificate(e_s1c1, u_admin, v_id);

    -- відгуки
    CALL sp_add_review(k1, u_s1, 5, 'Дуже зрозуміло та по справі', v_id);
    CALL sp_add_review(k1, u_s2, 4, 'Добрий курс, хотілося б більше практики', v_id);
    CALL sp_add_review(k2, u_s1, 5, 'Чудове пояснення ООП', v_id);
    CALL sp_add_review(k2, u_s4, 4, NULL, v_id);
    CALL sp_add_review(k3, u_s3, 4, 'Корисна практика у Figma', v_id);
END;
$$;


-- Перевірка кількість записів у таблицях
SELECT 'roles' AS table_name, COUNT(*) AS rows_count FROM roles
UNION ALL SELECT 'users', COUNT(*) FROM users
UNION ALL SELECT 'categories', COUNT(*) FROM categories
UNION ALL SELECT 'courses', COUNT(*) FROM courses
UNION ALL SELECT 'modules', COUNT(*) FROM modules
UNION ALL SELECT 'lessons', COUNT(*) FROM lessons
UNION ALL SELECT 'enrollments', COUNT(*) FROM enrollments
UNION ALL SELECT 'lesson_progress', COUNT(*) FROM lesson_progress
UNION ALL SELECT 'assignments', COUNT(*) FROM assignments
UNION ALL SELECT 'submissions', COUNT(*) FROM submissions
UNION ALL SELECT 'quizzes', COUNT(*) FROM quizzes
UNION ALL SELECT 'payments', COUNT(*) FROM payments
UNION ALL SELECT 'reviews', COUNT(*) FROM reviews
UNION ALL SELECT 'certificates', COUNT(*) FROM certificates
UNION ALL SELECT 'audit_log', COUNT(*) FROM audit_log;