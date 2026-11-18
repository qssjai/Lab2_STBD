DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;

--Користувачі
CREATE TABLE roles (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE users (
    id            SERIAL PRIMARY KEY,
    email         VARCHAR(150) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    first_name    VARCHAR(100) NOT NULL,
    last_name     VARCHAR(100) NOT NULL,
    role_id       INT NOT NULL REFERENCES roles(id),
    -- аудит
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by    INT,
    updated_at    TIMESTAMP,
    updated_by    INT,
    -- soft delete
    is_deleted    BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at    TIMESTAMP,
    deleted_by    INT,
    CONSTRAINT chk_users_email CHECK (email LIKE '%_@_%._%'),
    CONSTRAINT chk_users_deleted CHECK (
        (is_deleted = FALSE AND deleted_at IS NULL)
        OR (is_deleted = TRUE AND deleted_at IS NOT NULL)
    )
);

ALTER TABLE users
    ADD CONSTRAINT fk_users_created_by FOREIGN KEY (created_by) REFERENCES users(id),
    ADD CONSTRAINT fk_users_updated_by FOREIGN KEY (updated_by) REFERENCES users(id),
    ADD CONSTRAINT fk_users_deleted_by FOREIGN KEY (deleted_by) REFERENCES users(id);

CREATE TABLE user_profiles (
    user_id    INT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    bio        TEXT,
    phone      VARCHAR(30),
    birth_date DATE,
    CONSTRAINT chk_profiles_birth CHECK (birth_date IS NULL OR birth_date < CURRENT_DATE)
);

--Каталог
CREATE TABLE categories (
    id        SERIAL PRIMARY KEY,
    name      VARCHAR(100) NOT NULL,
    parent_id INT REFERENCES categories(id) ON DELETE SET NULL,
    CONSTRAINT chk_categories_self CHECK (parent_id IS NULL OR parent_id <> id)
);

CREATE TABLE course_levels (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE courses (
    id          SERIAL PRIMARY KEY,
    title       VARCHAR(200) NOT NULL,
    description TEXT,
    category_id INT NOT NULL REFERENCES categories(id),
    level_id    INT NOT NULL REFERENCES course_levels(id),
    price       NUMERIC(10,2) NOT NULL DEFAULT 0,
    status      VARCHAR(20) NOT NULL DEFAULT 'draft',
    -- аудит
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by  INT REFERENCES users(id),
    updated_at  TIMESTAMP,
    updated_by  INT REFERENCES users(id),
    -- soft delete
    is_deleted  BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at  TIMESTAMP,
    deleted_by  INT REFERENCES users(id),
    CONSTRAINT chk_courses_price  CHECK (price >= 0),
    CONSTRAINT chk_courses_status CHECK (status IN ('draft', 'published', 'archived')),
    CONSTRAINT chk_courses_deleted CHECK (
        (is_deleted = FALSE AND deleted_at IS NULL)
        OR (is_deleted = TRUE AND deleted_at IS NOT NULL)
    )
);

CREATE TABLE course_instructors (
    course_id INT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    user_id   INT NOT NULL REFERENCES users(id),
    PRIMARY KEY (course_id, user_id)
);


--Контент курсу
CREATE TABLE modules (
    id         SERIAL PRIMARY KEY,
    course_id  INT NOT NULL REFERENCES courses(id),
    title      VARCHAR(200) NOT NULL,
    position   INT NOT NULL,
    -- soft delete
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMP,
    deleted_by INT REFERENCES users(id),
    CONSTRAINT chk_modules_position CHECK (position > 0),
    CONSTRAINT chk_modules_deleted CHECK (
        (is_deleted = FALSE AND deleted_at IS NULL)
        OR (is_deleted = TRUE AND deleted_at IS NOT NULL)
    )
);

CREATE TABLE lessons (
    id           SERIAL PRIMARY KEY,
    module_id    INT NOT NULL REFERENCES modules(id),
    title        VARCHAR(200) NOT NULL,
    content      TEXT,
    duration_min INT,
    position     INT NOT NULL,
    -- аудит
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by   INT REFERENCES users(id),
    updated_at   TIMESTAMP,
    updated_by   INT REFERENCES users(id),
    -- soft delete
    is_deleted   BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at   TIMESTAMP,
    deleted_by   INT REFERENCES users(id),
    CONSTRAINT chk_lessons_duration CHECK (duration_min IS NULL OR duration_min > 0),
    CONSTRAINT chk_lessons_position CHECK (position > 0),
    CONSTRAINT chk_lessons_deleted CHECK (
        (is_deleted = FALSE AND deleted_at IS NULL)
        OR (is_deleted = TRUE AND deleted_at IS NOT NULL)
    )
);


--Навчання
CREATE TABLE enrollments (
    id          SERIAL PRIMARY KEY,
    user_id     INT NOT NULL REFERENCES users(id),
    course_id   INT NOT NULL REFERENCES courses(id),
    enrolled_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status      VARCHAR(20) NOT NULL DEFAULT 'active',
    progress    NUMERIC(5,2) NOT NULL DEFAULT 0,
    CONSTRAINT uq_enrollments_user_course UNIQUE (user_id, course_id),
    CONSTRAINT chk_enrollments_status CHECK (status IN ('active', 'completed', 'cancelled')),
    CONSTRAINT chk_enrollments_progress CHECK (progress BETWEEN 0 AND 100)
);

CREATE TABLE lesson_progress (
    enrollment_id INT NOT NULL REFERENCES enrollments(id) ON DELETE CASCADE,
    lesson_id     INT NOT NULL REFERENCES lessons(id),
    completed_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (enrollment_id, lesson_id)
);


--Завдання
CREATE TABLE assignments (
    id         SERIAL PRIMARY KEY,
    lesson_id  INT NOT NULL REFERENCES lessons(id),
    title      VARCHAR(200) NOT NULL,
    max_score  INT NOT NULL,
    due_date   TIMESTAMP,
    -- soft delete
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMP,
    deleted_by INT REFERENCES users(id),
    CONSTRAINT chk_assignments_score CHECK (max_score > 0),
    CONSTRAINT chk_assignments_deleted CHECK (
        (is_deleted = FALSE AND deleted_at IS NULL)
        OR (is_deleted = TRUE AND deleted_at IS NOT NULL)
    )
);

CREATE TABLE submissions (
    id            SERIAL PRIMARY KEY,
    assignment_id INT NOT NULL REFERENCES assignments(id),
    student_id    INT NOT NULL REFERENCES users(id),
    content       TEXT,
    score         INT,
    graded_by     INT REFERENCES users(id),
    graded_at     TIMESTAMP,
    -- аудит
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by    INT REFERENCES users(id),
    updated_at    TIMESTAMP,
    updated_by    INT REFERENCES users(id),
    CONSTRAINT chk_submissions_score CHECK (score IS NULL OR score >= 0)
);


--Тести
CREATE TABLE quizzes (
    id         SERIAL PRIMARY KEY,
    lesson_id  INT NOT NULL REFERENCES lessons(id),
    title      VARCHAR(200) NOT NULL,
    pass_score INT NOT NULL,
    CONSTRAINT chk_quizzes_pass CHECK (pass_score BETWEEN 0 AND 100)
);

CREATE TABLE quiz_questions (
    id      SERIAL PRIMARY KEY,
    quiz_id INT NOT NULL REFERENCES quizzes(id) ON DELETE CASCADE,
    text    TEXT NOT NULL
);

CREATE TABLE quiz_options (
    id          SERIAL PRIMARY KEY,
    question_id INT NOT NULL REFERENCES quiz_questions(id) ON DELETE CASCADE,
    text        VARCHAR(500) NOT NULL,
    is_correct  BOOLEAN NOT NULL DEFAULT FALSE
);


--Взаємодія
CREATE TABLE reviews (
    id         SERIAL PRIMARY KEY,
    course_id  INT NOT NULL REFERENCES courses(id),
    user_id    INT NOT NULL REFERENCES users(id),
    rating     INT NOT NULL,
    comment    TEXT,
    -- аудит
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by INT REFERENCES users(id),
    updated_at TIMESTAMP,
    updated_by INT REFERENCES users(id),
    CONSTRAINT uq_reviews_course_user UNIQUE (course_id, user_id),
    CONSTRAINT chk_reviews_rating CHECK (rating BETWEEN 1 AND 5)
);

CREATE TABLE payments (
    id            SERIAL PRIMARY KEY,
    enrollment_id INT NOT NULL REFERENCES enrollments(id),
    amount        NUMERIC(10,2) NOT NULL,
    paid_at       TIMESTAMP,
    status        VARCHAR(20) NOT NULL DEFAULT 'pending',
    CONSTRAINT chk_payments_amount CHECK (amount >= 0),
    CONSTRAINT chk_payments_status CHECK (status IN ('pending', 'paid', 'failed', 'refunded'))
);

CREATE TABLE certificates (
    id            SERIAL PRIMARY KEY,
    enrollment_id INT NOT NULL UNIQUE REFERENCES enrollments(id),
    issued_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    number        VARCHAR(50) NOT NULL UNIQUE
);


--Службова таблиця аудиту
CREATE TABLE audit_log (
    id         BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    record_id  INT NOT NULL,
    action     VARCHAR(10) NOT NULL,
    changed_by INT REFERENCES users(id),
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    old_data   JSONB,
    new_data   JSONB,
    CONSTRAINT chk_audit_action CHECK (action IN ('INSERT', 'UPDATE', 'DELETE'))
);