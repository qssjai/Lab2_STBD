CREATE INDEX idx_users_role_id            ON users (role_id);
CREATE INDEX idx_categories_parent_id     ON categories (parent_id);
CREATE INDEX idx_courses_category_id      ON courses (category_id);
CREATE INDEX idx_courses_level_id         ON courses (level_id);
CREATE INDEX idx_course_instructors_user  ON course_instructors (user_id);
CREATE INDEX idx_enrollments_course_id    ON enrollments (course_id);
CREATE INDEX idx_lesson_progress_lesson   ON lesson_progress (lesson_id);
CREATE INDEX idx_assignments_lesson_id    ON assignments (lesson_id);
CREATE INDEX idx_submissions_assignment   ON submissions (assignment_id);
CREATE INDEX idx_submissions_student      ON submissions (student_id);
CREATE INDEX idx_quizzes_lesson_id        ON quizzes (lesson_id);
CREATE INDEX idx_quiz_questions_quiz_id   ON quiz_questions (quiz_id);
CREATE INDEX idx_quiz_options_question_id ON quiz_options (question_id);
CREATE INDEX idx_payments_enrollment_id   ON payments (enrollment_id);


CREATE INDEX idx_audit_table_record       ON audit_log (table_name, record_id);

-- Активні курси пошук і сортування за назвою
CREATE INDEX idx_courses_title_active
    ON courses (title)
    WHERE is_deleted = FALSE;

-- Активні користувачі пошук за прізвищем та ім'ям
CREATE INDEX idx_users_name_active
    ON users (last_name, first_name)
    WHERE is_deleted = FALSE;

-- Активні модулі курсу в порядку позицій
CREATE INDEX idx_modules_course_active
    ON modules (course_id, position)
    WHERE is_deleted = FALSE;

-- Активні уроки модуля в порядку позицій
CREATE INDEX idx_lessons_module_active
    ON lessons (module_id, position)
    WHERE is_deleted = FALSE;

-- Роботи, які ще не оцінено (черга перевірки викладача)
CREATE INDEX idx_submissions_ungraded
    ON submissions (assignment_id)
    WHERE score IS NULL;

--GIN
CREATE INDEX idx_courses_fts
    ON courses
    USING GIN (to_tsvector('simple', title || ' ' || COALESCE(description, '')));

-- Пошук усередині JSONB журналу аудиту
CREATE INDEX idx_audit_new_data_gin
    ON audit_log
    USING GIN (new_data jsonb_path_ops);

--великі таблиці, де значення зростають разом із часом запису
CREATE INDEX idx_payments_paid_at_brin
    ON payments
    USING BRIN (paid_at);

CREATE INDEX idx_audit_changed_at_brin
    ON audit_log
    USING BRIN (changed_at);

--Перевірка: перелік створених індексів з типами
SELECT tablename,
       indexname,
       substring(indexdef FROM 'USING (\w+)') AS index_type
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;