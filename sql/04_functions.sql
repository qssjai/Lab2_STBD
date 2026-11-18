-- Користувацькі функції
CREATE OR REPLACE FUNCTION fn_current_user_id()
RETURNS INT
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.current_user_id', TRUE), '')::INT;
$$;

--fn_course_lessons_count кількість активних уроків курсу
CREATE OR REPLACE FUNCTION fn_course_lessons_count(p_course_id INT)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
    SELECT COUNT(l.id)::INT
    FROM modules m
    JOIN lessons l ON l.module_id = m.id AND l.is_deleted = FALSE
    WHERE m.course_id = p_course_id
      AND m.is_deleted = FALSE;
$$;


--fn_course_progress: відсоток проходження курсу за записом (0..100).
--враховуються лише активні (не видалені) уроки.
CREATE OR REPLACE FUNCTION fn_course_progress(p_enrollment_id INT)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_course_id INT;
    v_total     INT;
    v_done      INT;
BEGIN
    SELECT course_id INTO v_course_id
    FROM enrollments
    WHERE id = p_enrollment_id;

    IF v_course_id IS NULL THEN
        RETURN 0;
    END IF;

    v_total := fn_course_lessons_count(v_course_id);
    IF v_total = 0 THEN
        RETURN 0;
    END IF;

    SELECT COUNT(*) INTO v_done
    FROM lesson_progress lp
    JOIN lessons l ON l.id = lp.lesson_id AND l.is_deleted = FALSE
    JOIN modules m ON m.id = l.module_id  AND m.is_deleted = FALSE
    WHERE lp.enrollment_id = p_enrollment_id
      AND m.course_id = v_course_id;

    RETURN ROUND(v_done * 100.0 / v_total, 2);
END;
$$;


--fn_is_course_completed чи пройдено всі уроки курсу
CREATE OR REPLACE FUNCTION fn_is_course_completed(p_enrollment_id INT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT fn_course_progress(p_enrollment_id) >= 100;
$$;


--fn_course_avg_rating середній рейтинг курсу (NULL, якщо відгуків немає)
CREATE OR REPLACE FUNCTION fn_course_avg_rating(p_course_id INT)
RETURNS NUMERIC
LANGUAGE sql
STABLE
AS $$
    SELECT ROUND(AVG(rating)::NUMERIC, 2)
    FROM reviews
    WHERE course_id = p_course_id;
$$;


--fn_student_avg_score середній результат студента за оціненими
--завданнями у відсотках від максимального балу (0, якщо оцінок немає)
CREATE OR REPLACE FUNCTION fn_student_avg_score(p_user_id INT)
RETURNS NUMERIC
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(ROUND(AVG(s.score * 100.0 / a.max_score), 2), 0)
    FROM submissions s
    JOIN assignments a ON a.id = s.assignment_id
    WHERE s.student_id = p_user_id
      AND s.score IS NOT NULL;
$$;


--fn_generate_certificate_number номер сертифіката виду CERT-2026-000015
CREATE OR REPLACE FUNCTION fn_generate_certificate_number(p_enrollment_id INT)
RETURNS VARCHAR
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT 'CERT-' || to_char(CURRENT_DATE, 'YYYY') || '-' || lpad(p_enrollment_id::TEXT, 6, '0');
$$;


--fn_search_courses повнотекстовий пошук курсів.
CREATE OR REPLACE FUNCTION fn_search_courses(p_query TEXT)
RETURNS TABLE (
    id          INT,
    title       VARCHAR,
    description TEXT,
    price       NUMERIC,
    rank        REAL
)
LANGUAGE sql
STABLE
AS $$
    SELECT c.id,
           c.title,
           c.description,
           c.price,
           ts_rank(
               to_tsvector('simple', c.title || ' ' || COALESCE(c.description, '')),
               plainto_tsquery('simple', p_query)
           ) AS rank
    FROM courses c
    WHERE c.is_deleted = FALSE
      AND to_tsvector('simple', c.title || ' ' || COALESCE(c.description, ''))
          @@ plainto_tsquery('simple', p_query)
    ORDER BY rank DESC, c.title;
$$;


-- Перевірка перелік створених функцій
SELECT routine_name AS function_name,
       data_type    AS returns
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_type = 'FUNCTION'
ORDER BY routine_name;