--v_active_users активні користувачі з роллю (без password_hash)
CREATE OR REPLACE VIEW v_active_users AS
SELECT u.id,
       u.email,
       u.first_name,
       u.last_name,
       u.first_name || ' ' || u.last_name AS full_name,
       r.name                             AS role_name,
       u.created_at,
       u.updated_at,
       u.updated_by
FROM users u
JOIN roles r ON r.id = u.role_id
WHERE u.is_deleted = FALSE;

--v_course_rating середній рейтинг і кількість відгуків по курсу
CREATE OR REPLACE VIEW v_course_rating AS
SELECT c.id                              AS course_id,
       c.title,
       COUNT(rv.id)                      AS reviews_count,
       ROUND(AVG(rv.rating)::numeric, 2) AS avg_rating
FROM courses c
LEFT JOIN reviews rv ON rv.course_id = c.id
WHERE c.is_deleted = FALSE
GROUP BY c.id, c.title;


--v_active_courses: каталог активних курсів зі зведеними показниками
CREATE OR REPLACE VIEW v_active_courses AS
SELECT c.id,
       c.title,
       c.description,
       c.price,
       c.status,
       cat.name                              AS category_name,
       lv.name                               AS level_name,
       COALESCE(enr.students_count, 0)       AS students_count,
       COALESCE(str.modules_count, 0)        AS modules_count,
       COALESCE(str.lessons_count, 0)        AS lessons_count,
       cr.avg_rating,
       c.created_at,
       c.updated_at,
       c.updated_by
FROM courses c
JOIN categories    cat ON cat.id = c.category_id
JOIN course_levels lv  ON lv.id  = c.level_id
LEFT JOIN (
    SELECT course_id, COUNT(*) AS students_count
    FROM enrollments
    WHERE status <> 'cancelled'
    GROUP BY course_id
) enr ON enr.course_id = c.id
LEFT JOIN (
    SELECT m.course_id,
           COUNT(DISTINCT m.id) AS modules_count,
           COUNT(l.id)          AS lessons_count
    FROM modules m
    LEFT JOIN lessons l ON l.module_id = m.id AND l.is_deleted = FALSE
    WHERE m.is_deleted = FALSE
    GROUP BY m.course_id
) str ON str.course_id = c.id
LEFT JOIN v_course_rating cr ON cr.course_id = c.id
WHERE c.is_deleted = FALSE;


--v_course_instructors курси та їхні викладачі (зв'язок M:N)
CREATE OR REPLACE VIEW v_course_instructors AS
SELECT c.id                              AS course_id,
       c.title                           AS course_title,
       u.id                              AS instructor_id,
       u.first_name || ' ' || u.last_name AS instructor_name,
       u.email                           AS instructor_email
FROM course_instructors ci
JOIN courses c ON c.id = ci.course_id AND c.is_deleted = FALSE
JOIN users   u ON u.id = ci.user_id   AND u.is_deleted = FALSE;


--v_course_structure дерево курс -> модуль -> урок (активні записи)
CREATE OR REPLACE VIEW v_course_structure AS
SELECT c.id           AS course_id,
       c.title        AS course_title,
       m.id           AS module_id,
       m.title        AS module_title,
       m.position     AS module_position,
       l.id           AS lesson_id,
       l.title        AS lesson_title,
       l.position     AS lesson_position,
       l.duration_min
FROM courses c
JOIN modules m      ON m.course_id = c.id AND m.is_deleted = FALSE
LEFT JOIN lessons l ON l.module_id = m.id AND l.is_deleted = FALSE
WHERE c.is_deleted = FALSE;


--v_student_progress прогрес студента по записах на курси
CREATE OR REPLACE VIEW v_student_progress AS
SELECT e.id                               AS enrollment_id,
       u.id                               AS student_id,
       u.first_name || ' ' || u.last_name AS student_name,
       c.id                               AS course_id,
       c.title                            AS course_title,
       e.enrolled_at,
       e.status,
       e.progress,
       COALESCE(done.cnt, 0)              AS completed_lessons,
       COALESCE(total.cnt, 0)             AS total_lessons
FROM enrollments e
JOIN users   u ON u.id = e.user_id   AND u.is_deleted = FALSE
JOIN courses c ON c.id = e.course_id AND c.is_deleted = FALSE
LEFT JOIN (
    SELECT enrollment_id, COUNT(*) AS cnt
    FROM lesson_progress
    GROUP BY enrollment_id
) done ON done.enrollment_id = e.id
LEFT JOIN (
    SELECT m.course_id, COUNT(l.id) AS cnt
    FROM modules m
    JOIN lessons l ON l.module_id = m.id AND l.is_deleted = FALSE
    WHERE m.is_deleted = FALSE
    GROUP BY m.course_id
) total ON total.course_id = c.id;


--v_submissions_overview: здані роботи та статус перевірки
CREATE OR REPLACE VIEW v_submissions_overview AS
SELECT s.id                               AS submission_id,
       a.id                               AS assignment_id,
       a.title                            AS assignment_title,
       a.max_score,
       c.id                               AS course_id,
       c.title                            AS course_title,
       st.id                              AS student_id,
       st.first_name || ' ' || st.last_name AS student_name,
       s.score,
       CASE WHEN s.score IS NULL THEN 'pending' ELSE 'graded' END AS grading_status,
       gr.first_name || ' ' || gr.last_name AS graded_by_name,
       s.graded_at,
       s.created_at                       AS submitted_at
FROM submissions s
JOIN assignments a ON a.id = s.assignment_id AND a.is_deleted = FALSE
JOIN lessons     l ON l.id = a.lesson_id
JOIN modules     m ON m.id = l.module_id
JOIN courses     c ON c.id = m.course_id
JOIN users      st ON st.id = s.student_id
LEFT JOIN users gr ON gr.id = s.graded_by;


--v_course_revenue: виручка по курсах (лише сплачені платежі)
CREATE OR REPLACE VIEW v_course_revenue AS
SELECT c.id                              AS course_id,
       c.title                           AS course_title,
       COUNT(p.id)                       AS payments_count,
       COALESCE(SUM(p.amount), 0)        AS total_revenue
FROM courses c
LEFT JOIN enrollments e ON e.course_id = c.id
LEFT JOIN payments    p ON p.enrollment_id = e.id AND p.status = 'paid'
WHERE c.is_deleted = FALSE
GROUP BY c.id, c.title;

--Перевірка перелік створених представлень
SELECT table_name AS view_name
FROM information_schema.views
WHERE table_schema = 'public'
ORDER BY table_name;