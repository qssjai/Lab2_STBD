-- Групування записане всередині функції, тому умова на спробу діє до групування
CREATE OR REPLACE FUNCTION fn_attempt_answers(p_attempt_id BIGINT)
RETURNS TABLE (
    answer_id           BIGINT,
    question_id         INT,
    is_correct          BOOLEAN,
    time_spent_sec      INT,
    selected_option_ids INT[]
)
LANGUAGE sql
STABLE
AS $$
    SELECT aa.id,
           aa.question_id,
           aa.is_correct,
           aa.time_spent_sec,
           COALESCE(array_agg(ao.option_id ORDER BY ao.option_id)
                    FILTER (WHERE ao.option_id IS NOT NULL), '{}')
    FROM attempt_answers aa
    LEFT JOIN attempt_answer_options ao ON ao.answer_id = aa.id
    WHERE aa.attempt_id = p_attempt_id
    GROUP BY aa.id;
$$;


EXPLAIN (ANALYZE, BUFFERS)
SELECT f.* FROM v_attempt_full f
WHERE f.attempt_id IN (
    SELECT attempt_id FROM v_attempt_summary
    WHERE user_id = (SELECT MIN(user_id) FROM v_attempt_summary)
    ORDER BY started_at DESC
    LIMIT 20);


EXPLAIN (ANALYZE, BUFFERS)
SELECT f.*
FROM (SELECT attempt_id FROM v_attempt_summary
      WHERE user_id = (SELECT MIN(user_id) FROM v_attempt_summary)
      ORDER BY started_at DESC
      LIMIT 20) s
CROSS JOIN LATERAL (SELECT * FROM v_attempt_full WHERE attempt_id = s.attempt_id) f;


EXPLAIN (ANALYZE, BUFFERS)
SELECT s.attempt_id, s.quiz_id, s.user_id, s.started_at, s.finished_at,
       s.duration_sec, s.score, s.passed,
       a.answer_id, a.question_id, a.is_correct, a.time_spent_sec, a.selected_option_ids
FROM (SELECT * FROM v_attempt_summary
      WHERE user_id = (SELECT MIN(user_id) FROM v_attempt_summary)
      ORDER BY started_at DESC
      LIMIT 20) s
CROSS JOIN LATERAL fn_attempt_answers(s.attempt_id) a;
