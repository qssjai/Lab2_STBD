-- Представлення довідників для C#-застосунку
-- Застосунок читає дані лише через views, тому довідникам теж потрібні представлення

--v_categories довідник категорій
CREATE OR REPLACE VIEW v_categories AS
SELECT id, name, parent_id
FROM categories;

--v_course_levels довідник рівнів складності
CREATE OR REPLACE VIEW v_course_levels AS
SELECT id, name
FROM course_levels;

--v_roles довідник ролей
CREATE OR REPLACE VIEW v_roles AS
SELECT id, name
FROM roles;

-- Перевірка
SELECT table_name AS view_name
FROM information_schema.views
WHERE table_schema = 'public'
ORDER BY table_name;