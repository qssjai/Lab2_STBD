-- Збережені процедури 

--fn_set_actor запам'ятовує користувача на час поточної транзакції.
--Його читають тригери через fn_current_user_id()
CREATE OR REPLACE FUNCTION fn_set_actor(p_actor_id INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_actor_id IS NOT NULL THEN
        PERFORM set_config('app.current_user_id', p_actor_id::TEXT, TRUE);
    END IF;
END;
$$;


--sp_create_user створює користувача
CREATE OR REPLACE PROCEDURE sp_create_user(
    p_email VARCHAR, p_password_hash VARCHAR, p_first_name VARCHAR,
    p_last_name VARCHAR, p_role_id INT, p_actor_id INT, INOUT p_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_actor(p_actor_id);

    IF EXISTS (SELECT 1 FROM users WHERE lower(email) = lower(p_email)) THEN
        RAISE EXCEPTION 'Користувач з email % уже існує', p_email;
    END IF;

    INSERT INTO users (email, password_hash, first_name, last_name, role_id)
    VALUES (p_email, p_password_hash, p_first_name, p_last_name, p_role_id)
    RETURNING id INTO p_id;
END;
$$;


--sp_update_user змінює ім'я, прізвище та роль активного користувача
CREATE OR REPLACE PROCEDURE sp_update_user(
    p_id INT, p_first_name VARCHAR, p_last_name VARCHAR, p_role_id INT, p_actor_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_actor(p_actor_id);

    UPDATE users
    SET first_name = p_first_name,
        last_name  = p_last_name,
        role_id    = p_role_id
    WHERE id = p_id AND is_deleted = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Активного користувача з id % не знайдено', p_id;
    END IF;
END;
$$;


--sp_soft_delete_user м'яке видалення користувача
CREATE OR REPLACE PROCEDURE sp_soft_delete_user(p_id INT, p_actor_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_actor(p_actor_id);

    UPDATE users SET is_deleted = TRUE
    WHERE id = p_id AND is_deleted = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Активного користувача з id % не знайдено', p_id;
    END IF;
END;
$$;


--sp_create_course створює курс зі статусом draft
CREATE OR REPLACE PROCEDURE sp_create_course(
    p_title VARCHAR, p_description TEXT, p_category_id INT, p_level_id INT,
    p_price NUMERIC, p_actor_id INT, INOUT p_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_actor(p_actor_id);

    INSERT INTO courses (title, description, category_id, level_id, price, status)
    VALUES (p_title, p_description, p_category_id, p_level_id, p_price, 'draft')
    RETURNING id INTO p_id;
END;
$$;


--sp_update_course змінює дані активного курсу
CREATE OR REPLACE PROCEDURE sp_update_course(
    p_id INT, p_title VARCHAR, p_description TEXT, p_category_id INT,
    p_level_id INT, p_price NUMERIC, p_actor_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_actor(p_actor_id);

    UPDATE courses
    SET title = p_title,
        description = p_description,
        category_id = p_category_id,
        level_id = p_level_id,
        price = p_price
    WHERE id = p_id AND is_deleted = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Активного курсу з id % не знайдено', p_id;
    END IF;
END;
$$;


--sp_add_course_instructor призначає викладача на курс
CREATE OR REPLACE PROCEDURE sp_add_course_instructor(
    p_course_id INT, p_user_id INT, p_actor_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_actor(p_actor_id);

    INSERT INTO course_instructors (course_id, user_id)
    VALUES (p_course_id, p_user_id)
    ON CONFLICT DO NOTHING;
END;
$$;


--sp_publish_course публікує курс. Потрібен хоча б один урок
CREATE OR REPLACE PROCEDURE sp_publish_course(p_course_id INT, p_actor_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_actor(p_actor_id);

    IF fn_course_lessons_count(p_course_id) = 0 THEN
        RAISE EXCEPTION 'Неможливо опублікувати курс без уроків';
    END IF;

    UPDATE courses SET status = 'published'
    WHERE id = p_course_id AND is_deleted = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Активного курсу з id % не знайдено', p_course_id;
    END IF;
END;
$$;


--sp_add_module додає модуль до курсу. Якщо позицію не задано, ставиться наступна
CREATE OR REPLACE PROCEDURE sp_add_module(
    p_course_id INT, p_title VARCHAR, p_position INT, p_actor_id INT, INOUT p_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_actor(p_actor_id);

    IF NOT EXISTS (SELECT 1 FROM courses WHERE id = p_course_id AND is_deleted = FALSE) THEN
        RAISE EXCEPTION 'Активного курсу з id % не знайдено', p_course_id;
    END IF;

    IF p_position IS NULL THEN
        SELECT COALESCE(MAX(position), 0) + 1 INTO p_position
        FROM modules WHERE course_id = p_course_id;
    END IF;

    INSERT INTO modules (course_id, title, position)
    VALUES (p_course_id, p_title, p_position)
    RETURNING id INTO p_id;
END;
$$;


--sp_add_lesson додає урок до модуля. Якщо позицію не задано, ставиться наступна
CREATE OR REPLACE PROCEDURE sp_add_lesson(
    p_module_id INT, p_title VARCHAR, p_content TEXT, p_duration_min INT,
    p_position INT, p_actor_id INT, INOUT p_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_actor(p_actor_id);

    IF NOT EXISTS (SELECT 1 FROM modules WHERE id = p_module_id AND is_deleted = FALSE) THEN
        RAISE EXCEPTION 'Активного модуля з id % не знайдено', p_module_id;
    END IF;

    IF p_position IS NULL THEN
        SELECT COALESCE(MAX(position), 0) + 1 INTO p_position
        FROM lessons WHERE module_id = p_module_id AND is_deleted = FALSE;
    END IF;

    INSERT INTO lessons (module_id, title, content, duration_min, position)
    VALUES (p_module_id, p_title, p_content, p_duration_min, p_position)
    RETURNING id INTO p_id;
END;
$$;


--sp_soft_delete_course каскадне м'яке видалення курсу разом з його
--модулями, уроками та завданнями
CREATE OR REPLACE PROCEDURE sp_soft_delete_course(p_course_id INT, p_actor_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_actor(p_actor_id);

    UPDATE courses SET is_deleted = TRUE
    WHERE id = p_course_id AND is_deleted = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Активного курсу з id % не знайдено', p_course_id;
    END IF;

    UPDATE assignments SET is_deleted = TRUE
    WHERE is_deleted = FALSE
      AND lesson_id IN (SELECT l.id FROM lessons l
                        JOIN modules m ON m.id = l.module_id
                        WHERE m.course_id = p_course_id);

    UPDATE lessons SET is_deleted = TRUE
    WHERE is_deleted = FALSE
      AND module_id IN (SELECT id FROM modules WHERE course_id = p_course_id);

    UPDATE modules SET is_deleted = TRUE
    WHERE is_deleted = FALSE AND course_id = p_course_id;
END;
$$;


--sp_restore_course відновлює курс та лише ті модулі, уроки й завдання,
--які були видалені разом з ним (не раніше за курс)
CREATE OR REPLACE PROCEDURE sp_restore_course(p_course_id INT, p_actor_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_deleted_at TIMESTAMP;
BEGIN
    PERFORM fn_set_actor(p_actor_id);

    SELECT deleted_at INTO v_deleted_at
    FROM courses
    WHERE id = p_course_id AND is_deleted = TRUE;

    IF v_deleted_at IS NULL THEN
        RAISE EXCEPTION 'Видаленого курсу з id % не знайдено', p_course_id;
    END IF;

    UPDATE courses SET is_deleted = FALSE WHERE id = p_course_id;

    UPDATE modules SET is_deleted = FALSE
    WHERE course_id = p_course_id AND is_deleted = TRUE AND deleted_at >= v_deleted_at;

    UPDATE lessons SET is_deleted = FALSE
    WHERE is_deleted = TRUE AND deleted_at >= v_deleted_at
      AND module_id IN (SELECT id FROM modules WHERE course_id = p_course_id);

    UPDATE assignments SET is_deleted = FALSE
    WHERE is_deleted = TRUE AND deleted_at >= v_deleted_at
      AND lesson_id IN (SELECT l.id FROM lessons l
                        JOIN modules m ON m.id = l.module_id
                        WHERE m.course_id = p_course_id);
END;
$$;


--sp_enroll_student записує студента на опублікований курс.
--Скасований запис поновлюється
CREATE OR REPLACE PROCEDURE sp_enroll_student(
    p_user_id INT, p_course_id INT, p_actor_id INT, INOUT p_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR;
BEGIN
    PERFORM fn_set_actor(p_actor_id);

    IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id AND is_deleted = FALSE) THEN
        RAISE EXCEPTION 'Активного користувача з id % не знайдено', p_user_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM courses
                   WHERE id = p_course_id AND is_deleted = FALSE AND status = 'published') THEN
        RAISE EXCEPTION 'Курс з id % недоступний для запису', p_course_id;
    END IF;

    SELECT id, status INTO p_id, v_status
    FROM enrollments
    WHERE user_id = p_user_id AND course_id = p_course_id;

    IF p_id IS NULL THEN
        INSERT INTO enrollments (user_id, course_id)
        VALUES (p_user_id, p_course_id)
        RETURNING id INTO p_id;
    ELSIF v_status = 'cancelled' THEN
        UPDATE enrollments SET status = 'active' WHERE id = p_id;
    ELSE
        RAISE EXCEPTION 'Студент уже записаний на цей курс';
    END IF;
END;
$$;


--sp_register_payment реєструє платіж за запис на курс
CREATE OR REPLACE PROCEDURE sp_register_payment(
    p_enrollment_id INT, p_amount NUMERIC, p_status VARCHAR,
    p_actor_id INT, INOUT p_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_actor(p_actor_id);

    IF NOT EXISTS (SELECT 1 FROM enrollments WHERE id = p_enrollment_id) THEN
        RAISE EXCEPTION 'Запис на курс з id % не знайдено', p_enrollment_id;
    END IF;

    INSERT INTO payments (enrollment_id, amount, paid_at, status)
    VALUES (p_enrollment_id, p_amount,
            CASE WHEN p_status = 'paid' THEN CURRENT_TIMESTAMP END,
            p_status)
    RETURNING id INTO p_id;
END;
$$;


--sp_complete_lesson відмічає урок пройденим. Прогрес перераховує тригер
CREATE OR REPLACE PROCEDURE sp_complete_lesson(
    p_enrollment_id INT, p_lesson_id INT, p_actor_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_actor(p_actor_id);

    IF NOT EXISTS (
        SELECT 1
        FROM enrollments e
        JOIN modules m ON m.course_id = e.course_id AND m.is_deleted = FALSE
        JOIN lessons l ON l.module_id = m.id AND l.is_deleted = FALSE
        WHERE e.id = p_enrollment_id
          AND e.status IN ('active', 'completed')
          AND l.id = p_lesson_id
    ) THEN
        RAISE EXCEPTION 'Урок % недоступний для цього запису на курс', p_lesson_id;
    END IF;

    INSERT INTO lesson_progress (enrollment_id, lesson_id)
    VALUES (p_enrollment_id, p_lesson_id)
    ON CONFLICT DO NOTHING;
END;
$$;


--sp_submit_assignment студент здає роботу. Він має бути записаний на курс
CREATE OR REPLACE PROCEDURE sp_submit_assignment(
    p_assignment_id INT, p_student_id INT, p_content TEXT, INOUT p_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_course_id INT;
BEGIN
    PERFORM fn_set_actor(p_student_id);

    SELECT m.course_id INTO v_course_id
    FROM assignments a
    JOIN lessons l ON l.id = a.lesson_id AND l.is_deleted = FALSE
    JOIN modules m ON m.id = l.module_id AND m.is_deleted = FALSE
    WHERE a.id = p_assignment_id AND a.is_deleted = FALSE;

    IF v_course_id IS NULL THEN
        RAISE EXCEPTION 'Активного завдання з id % не знайдено', p_assignment_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM enrollments
                   WHERE user_id = p_student_id AND course_id = v_course_id
                     AND status IN ('active', 'completed')) THEN
        RAISE EXCEPTION 'Студент не записаний на курс цього завдання';
    END IF;

    INSERT INTO submissions (assignment_id, student_id, content)
    VALUES (p_assignment_id, p_student_id, p_content)
    RETURNING id INTO p_id;
END;
$$;


--sp_grade_submission виставляє оцінку. Максимальний бал перевіряє тригер
CREATE OR REPLACE PROCEDURE sp_grade_submission(
    p_submission_id INT, p_score INT, p_grader_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_actor(p_grader_id);

    UPDATE submissions
    SET score = p_score,
        graded_by = p_grader_id,
        graded_at = CURRENT_TIMESTAMP
    WHERE id = p_submission_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Роботу з id % не знайдено', p_submission_id;
    END IF;
END;
$$;


--sp_issue_certificate видає сертифікат після повного проходження курсу
CREATE OR REPLACE PROCEDURE sp_issue_certificate(
    p_enrollment_id INT, p_actor_id INT, INOUT p_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_actor(p_actor_id);

    IF NOT fn_is_course_completed(p_enrollment_id) THEN
        RAISE EXCEPTION 'Курс ще не пройдено повністю';
    END IF;

    IF EXISTS (SELECT 1 FROM certificates WHERE enrollment_id = p_enrollment_id) THEN
        RAISE EXCEPTION 'Сертифікат для цього запису вже видано';
    END IF;

    INSERT INTO certificates (enrollment_id, number)
    VALUES (p_enrollment_id, fn_generate_certificate_number(p_enrollment_id))
    RETURNING id INTO p_id;
END;
$$;


--sp_add_review додає відгук. Права студента перевіряє тригер
CREATE OR REPLACE PROCEDURE sp_add_review(
    p_course_id INT, p_user_id INT, p_rating INT, p_comment TEXT, INOUT p_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_set_actor(p_user_id);

    INSERT INTO reviews (course_id, user_id, rating, comment)
    VALUES (p_course_id, p_user_id, p_rating, p_comment)
    RETURNING id INTO p_id;
END;
$$;


-- Перевірка перелік створених процедур
SELECT routine_name AS procedure_name
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_type = 'PROCEDURE'
ORDER BY routine_name;