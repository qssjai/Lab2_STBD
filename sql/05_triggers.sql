-- Тригери

--fn_trg_set_created заповнює created_by під час вставки
CREATE OR REPLACE FUNCTION fn_trg_set_created()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.created_at := COALESCE(NEW.created_at, CURRENT_TIMESTAMP);
    NEW.created_by := COALESCE(NEW.created_by, fn_current_user_id());
    RETURN NEW;
END;
$$;


--fn_trg_set_updated заповнює updated_at та updated_by під час зміни запису
CREATE OR REPLACE FUNCTION fn_trg_set_updated()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    NEW.updated_by := COALESCE(fn_current_user_id(), NEW.updated_by);
    RETURN NEW;
END;
$$;


--fn_trg_soft_delete_fill заповнює deleted_at та deleted_by,
--коли is_deleted змінюється на TRUE, і очищає їх при відновленні запису
CREATE OR REPLACE FUNCTION fn_trg_soft_delete_fill()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.is_deleted = TRUE AND OLD.is_deleted = FALSE THEN
        NEW.deleted_at := CURRENT_TIMESTAMP;
        NEW.deleted_by := COALESCE(fn_current_user_id(), NEW.deleted_by);
    ELSIF NEW.is_deleted = FALSE AND OLD.is_deleted = TRUE THEN
        NEW.deleted_at := NULL;
        NEW.deleted_by := NULL;
    END IF;
    RETURN NEW;
END;
$$;


--fn_trg_prevent_hard_delete забороняє фізичне видалення з таблиць із soft delete
CREATE OR REPLACE FUNCTION fn_trg_prevent_hard_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Фізичне видалення з таблиці % заборонено. Використовуйте soft delete (is_deleted = TRUE).', TG_TABLE_NAME;
END;
$$;


--fn_trg_audit записує кожну вставку, зміну та видалення в audit_log (JSONB).
--password_hash у журнал не потрапляє
CREATE OR REPLACE FUNCTION fn_trg_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_old JSONB;
    v_new JSONB;
    v_id  INT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_new := to_jsonb(NEW) - 'password_hash';
        v_id  := (v_new ->> 'id')::INT;
    ELSIF TG_OP = 'UPDATE' THEN
        v_old := to_jsonb(OLD) - 'password_hash';
        v_new := to_jsonb(NEW) - 'password_hash';
        v_id  := (v_new ->> 'id')::INT;
        IF v_old = v_new THEN
            RETURN NULL;
        END IF;
    ELSE
        v_old := to_jsonb(OLD) - 'password_hash';
        v_id  := (v_old ->> 'id')::INT;
    END IF;

    INSERT INTO audit_log (table_name, record_id, action, changed_by, old_data, new_data)
    VALUES (TG_TABLE_NAME, v_id, TG_OP, fn_current_user_id(), v_old, v_new);

    RETURN NULL;
END;
$$;


--fn_trg_recalc_progress перераховує прогрес запису на курс після
--додавання або видалення пройденого уроку. При 100% статус стає completed
CREATE OR REPLACE FUNCTION fn_trg_recalc_progress()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_enrollment_id INT;
    v_progress      NUMERIC;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_enrollment_id := OLD.enrollment_id;
    ELSE
        v_enrollment_id := NEW.enrollment_id;
    END IF;

    v_progress := fn_course_progress(v_enrollment_id);

    UPDATE enrollments
    SET progress = v_progress,
        status = CASE
                     WHEN v_progress >= 100 AND status = 'active' THEN 'completed'
                     WHEN v_progress < 100 AND status = 'completed' THEN 'active'
                     ELSE status
                 END
    WHERE id = v_enrollment_id;

    RETURN NULL;
END;
$$;


--fn_trg_submission_check перевіряє, що оцінка не перевищує максимальний бал,
--і автоматично ставить graded_at та graded_by при першому виставленні оцінки
CREATE OR REPLACE FUNCTION fn_trg_submission_check()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_max INT;
BEGIN
    IF NEW.score IS NOT NULL THEN
        SELECT max_score INTO v_max
        FROM assignments
        WHERE id = NEW.assignment_id;

        IF NEW.score > v_max THEN
            RAISE EXCEPTION 'Оцінка % перевищує максимальний бал завдання (%)', NEW.score, v_max;
        END IF;

        IF TG_OP = 'INSERT' OR OLD.score IS NULL THEN
            NEW.graded_at := COALESCE(NEW.graded_at, CURRENT_TIMESTAMP);
            NEW.graded_by := COALESCE(NEW.graded_by, fn_current_user_id());
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


--fn_trg_review_check дозволяє залишити відгук лише студенту, записаному на курс
CREATE OR REPLACE FUNCTION fn_trg_review_check()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM enrollments
        WHERE user_id = NEW.user_id
          AND course_id = NEW.course_id
          AND status <> 'cancelled'
    ) THEN
        RAISE EXCEPTION 'Відгук може залишити лише студент, записаний на курс';
    END IF;
    RETURN NEW;
END;
$$;


--створення тригерів. created_by для таблиць з аудитом створення
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['users', 'courses', 'lessons', 'submissions', 'reviews']
    LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%s_set_created BEFORE INSERT ON %I
             FOR EACH ROW EXECUTE FUNCTION fn_trg_set_created()', t, t);
        EXECUTE format(
            'CREATE TRIGGER trg_%s_set_updated BEFORE UPDATE ON %I
             FOR EACH ROW EXECUTE FUNCTION fn_trg_set_updated()', t, t);
    END LOOP;
END;
$$;


--тригери soft delete: автозаповнення полів та заборона DELETE
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['users', 'courses', 'modules', 'lessons', 'assignments']
    LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%s_soft_delete BEFORE UPDATE ON %I
             FOR EACH ROW EXECUTE FUNCTION fn_trg_soft_delete_fill()', t, t);
        EXECUTE format(
            'CREATE TRIGGER trg_%s_no_hard_delete BEFORE DELETE ON %I
             FOR EACH ROW EXECUTE FUNCTION fn_trg_prevent_hard_delete()', t, t);
    END LOOP;
END;
$$;


--тригери журналу аудиту
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['users', 'courses', 'modules', 'lessons', 'assignments',
                             'submissions', 'reviews', 'enrollments', 'payments']
    LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%s_audit AFTER INSERT OR UPDATE OR DELETE ON %I
             FOR EACH ROW EXECUTE FUNCTION fn_trg_audit()', t, t);
    END LOOP;
END;
$$;


--тригер перерахунку прогресу
CREATE TRIGGER trg_lesson_progress_recalc
AFTER INSERT OR DELETE ON lesson_progress
FOR EACH ROW EXECUTE FUNCTION fn_trg_recalc_progress();


--тригер перевірки оцінки
CREATE TRIGGER trg_submissions_check
BEFORE INSERT OR UPDATE ON submissions
FOR EACH ROW EXECUTE FUNCTION fn_trg_submission_check();


--тригер перевірки відгуку
CREATE TRIGGER trg_reviews_check
BEFORE INSERT ON reviews
FOR EACH ROW EXECUTE FUNCTION fn_trg_review_check();


-- Перевірка перелік створених тригерів
SELECT event_object_table AS table_name,
       trigger_name,
       string_agg(event_manipulation, ', ') AS events
FROM information_schema.triggers
WHERE trigger_schema = 'public'
GROUP BY event_object_table, trigger_name
ORDER BY event_object_table, trigger_name;