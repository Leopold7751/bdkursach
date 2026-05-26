-- ============================================================
-- 02_seed.sql — Наполнение справочников и тестовые данные
-- ============================================================

-- ---- ТИПЫ ВОПРОСОВ ----
INSERT INTO q_types VALUES (sq_q_types.NEXTVAL, 'SINGLE',   'Одиночный выбор');
INSERT INTO q_types VALUES (sq_q_types.NEXTVAL, 'MULTI',    'Множественный выбор');
INSERT INTO q_types VALUES (sq_q_types.NEXTVAL, 'TEXT',     'Текстовый ответ');
INSERT INTO q_types VALUES (sq_q_types.NEXTVAL, 'NUMERIC',  'Числовой ответ');
INSERT INTO q_types VALUES (sq_q_types.NEXTVAL, 'ORDERING', 'Установление порядка');
INSERT INTO q_types VALUES (sq_q_types.NEXTVAL, 'MATCHING', 'Установление соответствия');
INSERT INTO q_types VALUES (sq_q_types.NEXTVAL, 'FILL',     'Заполнение пропуска');

-- ---- СТАТУСЫ ПОПЫТКИ ----
INSERT INTO attempt_statuses VALUES (sq_att_statuses.NEXTVAL, 'IN_PROGRESS', 'В процессе');
INSERT INTO attempt_statuses VALUES (sq_att_statuses.NEXTVAL, 'COMPLETED',   'Завершена');
INSERT INTO attempt_statuses VALUES (sq_att_statuses.NEXTVAL, 'ABANDONED',   'Прервана');

-- ---- РЕЖИМЫ ОБРАТНОЙ СВЯЗИ ----
INSERT INTO feedback_modes VALUES (sq_fb_modes.NEXTVAL, 'NEVER',         'Только итог');
INSERT INTO feedback_modes VALUES (sq_fb_modes.NEXTVAL, 'AFTER_ATTEMPT', 'После попытки');
INSERT INTO feedback_modes VALUES (sq_fb_modes.NEXTVAL, 'PER_QUESTION',  'По каждому вопросу');

-- ---- РЕЗУЛЬТАТЫ ПОПЫТКИ ----
INSERT INTO attempt_results VALUES (sq_att_results.NEXTVAL, 'PASS',    'Зачёт');
INSERT INTO attempt_results VALUES (sq_att_results.NEXTVAL, 'FAIL',    'Незачёт');
INSERT INTO attempt_results VALUES (sq_att_results.NEXTVAL, 'PENDING', 'Не определён');

-- ---- ПРИЧИНЫ ЗАВЕРШЕНИЯ ----
INSERT INTO finish_reasons VALUES (sq_fin_reasons.NEXTVAL, 'MANUAL',       'Завершено вручную');
INSERT INTO finish_reasons VALUES (sq_fin_reasons.NEXTVAL, 'TIME_EXPIRED', 'Истекло время');
INSERT INTO finish_reasons VALUES (sq_fin_reasons.NEXTVAL, 'ABANDONED',    'Покинуто');

-- ---- КАТЕГОРИИ ----
INSERT INTO categories VALUES (sq_categories.NEXTVAL, 'Информационные технологии', 'Общая категория ИТ', NULL);
INSERT INTO categories VALUES (sq_categories.NEXTVAL, 'Базы данных', 'SQL, реляционные БД', 1);
INSERT INTO categories VALUES (sq_categories.NEXTVAL, 'Программирование', 'Языки программирования', 1);
INSERT INTO categories VALUES (sq_categories.NEXTVAL, 'Сети', 'Сетевые технологии', 1);
INSERT INTO categories VALUES (sq_categories.NEXTVAL, 'Безопасность', 'Информационная безопасность', 1);

-- ---- ПОЛЬЗОВАТЕЛИ (пароль: "password" → sha256 заглушка) ----
-- Настоящий хэш будет генерировать Python при регистрации.
-- Здесь — демо-данные с хэшем "password"
INSERT INTO users VALUES (
    sq_users.NEXTVAL, 'admin',
    'Администратор',
    '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8',
    'admin'
);
INSERT INTO users VALUES (
    sq_users.NEXTVAL, 'author1',
    'Иванов И.И.',
    '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8',
    'author'
);
INSERT INTO users VALUES (
    sq_users.NEXTVAL, 'student1',
    'Петров П.П.',
    '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8',
    'student'
);

-- ---- ТЕСТ-ДЕМО ----
INSERT INTO tests (id_test, id_user, id_category, id_mode, title, description,
                   max_score, passing_score, timer_min, is_active, shuffle_q)
VALUES (sq_tests.NEXTVAL, 2, 2,
        (SELECT id_mode FROM feedback_modes WHERE code = 'AFTER_ATTEMPT'),
        'Основы SQL',
        'Базовый тест по языку SQL для студентов первого курса',
        10, 6, 20, 'Y', 'N');

-- ---- ВОПРОСЫ ----
-- Q1: SINGLE
INSERT INTO questions (id_question, id_type, id_category, q_text, difficulty, explanation, max_score)
VALUES (sq_questions.NEXTVAL,
        (SELECT id_type FROM q_types WHERE code = 'SINGLE'),
        2,
        'Какой оператор SQL используется для выборки данных?',
        1, 'Оператор SELECT предназначен для выборки данных из таблиц.', 2);

INSERT INTO options (id_option, id_question, opt_text, is_right) VALUES (sq_options.NEXTVAL, 1, 'SELECT', 'Y');
INSERT INTO options (id_option, id_question, opt_text, is_right) VALUES (sq_options.NEXTVAL, 1, 'INSERT', 'N');
INSERT INTO options (id_option, id_question, opt_text, is_right) VALUES (sq_options.NEXTVAL, 1, 'UPDATE', 'N');
INSERT INTO options (id_option, id_question, opt_text, is_right) VALUES (sq_options.NEXTVAL, 1, 'DELETE', 'N');

-- Q2: MULTI
INSERT INTO questions (id_question, id_type, id_category, q_text, difficulty, explanation, max_score)
VALUES (sq_questions.NEXTVAL,
        (SELECT id_type FROM q_types WHERE code = 'MULTI'),
        2,
        'Какие из перечисленных команд относятся к DDL?',
        2, 'DDL (Data Definition Language): CREATE, ALTER, DROP, TRUNCATE.', 3);

INSERT INTO options (id_option, id_question, opt_text, is_right) VALUES (sq_options.NEXTVAL, 2, 'CREATE', 'Y');
INSERT INTO options (id_option, id_question, opt_text, is_right) VALUES (sq_options.NEXTVAL, 2, 'ALTER',  'Y');
INSERT INTO options (id_option, id_question, opt_text, is_right) VALUES (sq_options.NEXTVAL, 2, 'SELECT', 'N');
INSERT INTO options (id_option, id_question, opt_text, is_right) VALUES (sq_options.NEXTVAL, 2, 'DROP',   'Y');
INSERT INTO options (id_option, id_question, opt_text, is_right) VALUES (sq_options.NEXTVAL, 2, 'UPDATE', 'N');

-- Q3: TEXT
INSERT INTO questions (id_question, id_type, id_category, q_text, difficulty, explanation, max_score)
VALUES (sq_questions.NEXTVAL,
        (SELECT id_type FROM q_types WHERE code = 'TEXT'),
        2,
        'Как называется ограничение, гарантирующее уникальность значений в столбце?',
        2, 'Ответ: UNIQUE. Ограничение UNIQUE запрещает повторяющиеся значения.', 2);
-- правильный ответ для TEXT-вопроса (нужен для is_correct_answer)
INSERT INTO options (id_option, id_question, opt_text, is_right) VALUES (sq_options.NEXTVAL, 3, 'UNIQUE', 'Y');

-- Q4: SINGLE (сложный)
INSERT INTO questions (id_question, id_type, id_category, q_text, difficulty, explanation, max_score)
VALUES (sq_questions.NEXTVAL,
        (SELECT id_type FROM q_types WHERE code = 'SINGLE'),
        2,
        'Что означает аббревиатура ACID в контексте транзакций БД?',
        3, 'ACID: Atomicity, Consistency, Isolation, Durability.', 3);

INSERT INTO options (id_option, id_question, opt_text, is_right) VALUES (sq_options.NEXTVAL, 4, 'Atomicity, Consistency, Isolation, Durability', 'Y');
INSERT INTO options (id_option, id_question, opt_text, is_right) VALUES (sq_options.NEXTVAL, 4, 'Access, Control, Integrity, Data',             'N');
INSERT INTO options (id_option, id_question, opt_text, is_right) VALUES (sq_options.NEXTVAL, 4, 'Atomicity, Concurrency, Index, Durability',     'N');
INSERT INTO options (id_option, id_question, opt_text, is_right) VALUES (sq_options.NEXTVAL, 4, 'Authentication, Consistency, Isolation, Data',  'N');

-- Q5: SINGLE
INSERT INTO questions (id_question, id_type, id_category, q_text, difficulty, explanation, max_score)
VALUES (sq_questions.NEXTVAL,
        (SELECT id_type FROM q_types WHERE code = 'SINGLE'),
        2,
        'Какой тип JOIN возвращает все строки из обеих таблиц, включая несовпадающие?',
        2, 'FULL OUTER JOIN возвращает все строки из обеих таблиц.', 0);
-- max_score = 0 временно — добавим через конструктор

UPDATE questions SET max_score = 2 WHERE id_question = 5;

INSERT INTO options (id_option, id_question, opt_text, is_right) VALUES (sq_options.NEXTVAL, 5, 'FULL OUTER JOIN', 'Y');
INSERT INTO options (id_option, id_question, opt_text, is_right) VALUES (sq_options.NEXTVAL, 5, 'INNER JOIN',      'N');
INSERT INTO options (id_option, id_question, opt_text, is_right) VALUES (sq_options.NEXTVAL, 5, 'LEFT JOIN',       'N');
INSERT INTO options (id_option, id_question, opt_text, is_right) VALUES (sq_options.NEXTVAL, 5, 'CROSS JOIN',      'N');

-- ---- КОНСТРУКТОР ТЕСТА (ручной подбор) ----
INSERT INTO test_builder (id_builder, id_test, id_question, is_auto, q_order, score_weight)
VALUES (sq_test_builder.NEXTVAL, 1, 1, 'N', 1, 2);
INSERT INTO test_builder (id_builder, id_test, id_question, is_auto, q_order, score_weight)
VALUES (sq_test_builder.NEXTVAL, 1, 2, 'N', 2, 3);
INSERT INTO test_builder (id_builder, id_test, id_question, is_auto, q_order, score_weight)
VALUES (sq_test_builder.NEXTVAL, 1, 3, 'N', 3, 2);
INSERT INTO test_builder (id_builder, id_test, id_question, is_auto, q_order, score_weight)
VALUES (sq_test_builder.NEXTVAL, 1, 4, 'N', 4, 3);

COMMIT;
