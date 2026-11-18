-- Лабораторна 2.

--quiz_attempts одна спроба проходження тесту студентом
CREATE TABLE quiz_attempts (
    id           BIGSERIAL PRIMARY KEY,
    quiz_id      INT NOT NULL REFERENCES quizzes(id),
    user_id      INT NOT NULL REFERENCES users(id),
    started_at   TIMESTAMP NOT NULL,
    finished_at  TIMESTAMP NOT NULL,
    duration_sec INT NOT NULL,
    score        NUMERIC(5,2) NOT NULL,
    passed       BOOLEAN NOT NULL,
    CONSTRAINT chk_attempts_duration CHECK (duration_sec >= 0),
    CONSTRAINT chk_attempts_score    CHECK (score BETWEEN 0 AND 100),
    CONSTRAINT chk_attempts_dates    CHECK (finished_at >= started_at)
);

--attempt_answers відповідь на одне питання в межах спроби
CREATE TABLE attempt_answers (
    id             BIGSERIAL PRIMARY KEY,
    attempt_id     BIGINT NOT NULL REFERENCES quiz_attempts(id) ON DELETE CASCADE,
    question_id    INT NOT NULL REFERENCES quiz_questions(id),
    is_correct     BOOLEAN NOT NULL,
    time_spent_sec INT NOT NULL,
    CONSTRAINT uq_answers_attempt_question UNIQUE (attempt_id, question_id),
    CONSTRAINT chk_answers_time CHECK (time_spent_sec >= 0)
);

--attempt_answer_options варіанти, які обрав студент (один або кілька)
CREATE TABLE attempt_answer_options (
    answer_id BIGINT NOT NULL REFERENCES attempt_answers(id) ON DELETE CASCADE,
    option_id INT NOT NULL REFERENCES quiz_options(id),
    PRIMARY KEY (answer_id, option_id)
);


--індекси. Пошук відповідей за спробою вже покриває UNIQUE (attempt_id, question_id)
CREATE INDEX idx_attempts_user_started ON quiz_attempts (user_id, started_at DESC);
CREATE INDEX idx_attempts_quiz         ON quiz_attempts (quiz_id);
CREATE INDEX idx_answers_question      ON attempt_answers (question_id);


--v_attempt_summary дані спроби без відповідей
CREATE OR REPLACE VIEW v_attempt_summary AS
SELECT id AS attempt_id,
       quiz_id,
       user_id,
       started_at,
       finished_at,
       duration_sec,
       score,
       passed
FROM quiz_attempts;


--v_attempt_answers відповіді зі списком обраних варіантів (аналог масиву answers у документі)
CREATE OR REPLACE VIEW v_attempt_answers AS
SELECT aa.attempt_id,
       aa.id AS answer_id,
       aa.question_id,
       aa.is_correct,
       aa.time_spent_sec,
       COALESCE(array_agg(ao.option_id ORDER BY ao.option_id)
                FILTER (WHERE ao.option_id IS NOT NULL), '{}') AS selected_option_ids
FROM attempt_answers aa
LEFT JOIN attempt_answer_options ao ON ao.answer_id = aa.id
GROUP BY aa.id;


--v_attempt_full спроба разом з усіма відповідями (аналог цілого документа)
CREATE OR REPLACE VIEW v_attempt_full AS
SELECT s.attempt_id,
       s.quiz_id,
       s.user_id,
       s.started_at,
       s.finished_at,
       s.duration_sec,
       s.score,
       s.passed,
       a.answer_id,
       a.question_id,
       a.is_correct,
       a.time_spent_sec,
       a.selected_option_ids
FROM v_attempt_summary s
JOIN v_attempt_answers a ON a.attempt_id = s.attempt_id;


--v_quiz_stats статистика по тестах
CREATE OR REPLACE VIEW v_quiz_stats AS
SELECT quiz_id,
       COUNT(*)                                          AS attempts_count,
       ROUND(AVG(score), 2)                              AS avg_score,
       ROUND(100.0 * COUNT(*) FILTER (WHERE passed) / COUNT(*), 2) AS pass_rate,
       ROUND(AVG(duration_sec), 2)                       AS avg_duration_sec
FROM quiz_attempts
GROUP BY quiz_id;


--v_question_stats статистика по питаннях: яке питання найскладніше
CREATE OR REPLACE VIEW v_question_stats AS
SELECT question_id,
       COUNT(*)                                                       AS answers_count,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_correct) / COUNT(*), 2) AS correct_rate,
       ROUND(AVG(time_spent_sec), 2)                                  AS avg_time_sec
FROM attempt_answers
GROUP BY question_id;


--sp_save_quiz_attempt зберігає всю спробу одним викликом.
--На вхід приймає JSON такого ж вигляду, як документ у MongoDB
CREATE OR REPLACE PROCEDURE sp_save_quiz_attempt(p_data JSONB, INOUT p_id BIGINT)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO quiz_attempts (quiz_id, user_id, started_at, finished_at, duration_sec, score, passed)
    VALUES ((p_data ->> 'quizId')::INT,
            (p_data ->> 'userId')::INT,
            (p_data ->> 'startedAt')::TIMESTAMP,
            (p_data ->> 'finishedAt')::TIMESTAMP,
            (p_data ->> 'durationSec')::INT,
            (p_data ->> 'score')::NUMERIC,
            (p_data ->> 'passed')::BOOLEAN)
    RETURNING id INTO p_id;

    WITH ans AS (
        SELECT (a ->> 'questionId')::INT     AS question_id,
               (a ->> 'isCorrect')::BOOLEAN  AS is_correct,
               (a ->> 'timeSpentSec')::INT   AS time_spent_sec,
               a -> 'selectedOptionIds'      AS options
        FROM jsonb_array_elements(p_data -> 'answers') AS a
    ),
    ins AS (
        INSERT INTO attempt_answers (attempt_id, question_id, is_correct, time_spent_sec)
        SELECT p_id, question_id, is_correct, time_spent_sec
        FROM ans
        RETURNING id, question_id
    )
    INSERT INTO attempt_answer_options (answer_id, option_id)
    SELECT ins.id, opt.option_id::INT
    FROM ins
    JOIN ans ON ans.question_id = ins.question_id
    CROSS JOIN LATERAL jsonb_array_elements_text(ans.options) AS opt(option_id);
END;
$$;


-- Перевірка
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('quiz_attempts', 'attempt_answers', 'attempt_answer_options')
ORDER BY table_name;
