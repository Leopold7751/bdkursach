-- ============================================================
-- ПЛАТФОРМА ОНЛАЙН-ТЕСТИРОВАНИЯ
-- 01_ddl.sql — Таблицы, последовательности, ограничения
-- Схема объединяет ЛР2 (рабочая логика) + КР (справочники)
-- ============================================================

-- ---- СПРАВОЧНИКИ ----

-- Типы вопросов
CREATE TABLE q_types (
    id_type   NUMBER        PRIMARY KEY,
    code      VARCHAR2(30)  NOT NULL UNIQUE,
    name      VARCHAR2(100) NOT NULL
);

-- Статусы попытки
CREATE TABLE attempt_statuses (
    id_status NUMBER        PRIMARY KEY,
    code      VARCHAR2(30)  NOT NULL UNIQUE,
    name      VARCHAR2(100) NOT NULL
);

-- Режимы обратной связи
CREATE TABLE feedback_modes (
    id_mode NUMBER        PRIMARY KEY,
    code    VARCHAR2(30)  NOT NULL UNIQUE,
    name    VARCHAR2(100) NOT NULL
);

-- Результаты попытки
CREATE TABLE attempt_results (
    id_result NUMBER        PRIMARY KEY,
    code      VARCHAR2(30)  NOT NULL UNIQUE,
    name      VARCHAR2(100) NOT NULL
);

-- Причины завершения
CREATE TABLE finish_reasons (
    id_reason NUMBER        PRIMARY KEY,
    code      VARCHAR2(30)  NOT NULL UNIQUE,
    name      VARCHAR2(100) NOT NULL
);

-- ---- ПОСЛЕДОВАТЕЛЬНОСТИ ДЛЯ СПРАВОЧНИКОВ ----
CREATE SEQUENCE sq_q_types        START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE sq_att_statuses   START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE sq_fb_modes       START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE sq_att_results    START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE sq_fin_reasons    START WITH 1 INCREMENT BY 1 NOCACHE;

-- ---- КАТЕГОРИИ (иерархические) ----
CREATE TABLE categories (
    id_category   NUMBER          PRIMARY KEY,
    name          VARCHAR2(100)   NOT NULL UNIQUE,
    description   VARCHAR2(2000),
    id_parent     NUMBER          REFERENCES categories(id_category)
);
CREATE SEQUENCE sq_categories START WITH 1 INCREMENT BY 1 NOCACHE;

-- ---- ПОЛЬЗОВАТЕЛИ ----
CREATE TABLE users (
    id_user       NUMBER          PRIMARY KEY,
    login         VARCHAR2(64)    NOT NULL UNIQUE,
    display_name  VARCHAR2(128)   NOT NULL,
    pwd_hash      VARCHAR2(256)   NOT NULL,
    role          VARCHAR2(20)    NOT NULL
        CHECK (role IN ('author', 'student', 'admin'))
);
CREATE SEQUENCE sq_users START WITH 1 INCREMENT BY 1 NOCACHE;

-- ---- ТЕСТЫ ----
CREATE TABLE tests (
    id_test       NUMBER          PRIMARY KEY,
    id_user       NUMBER          NOT NULL REFERENCES users(id_user),
    id_category   NUMBER          REFERENCES categories(id_category),
    id_mode       NUMBER          NOT NULL REFERENCES feedback_modes(id_mode),
    title         VARCHAR2(200)   NOT NULL,
    description   VARCHAR2(2000),
    max_score     NUMBER(8,2)     NOT NULL,
    passing_score NUMBER(8,2),
    timer_min     NUMBER(4),
    is_active     CHAR(1)         NOT NULL DEFAULT 'N' CHECK (is_active IN ('Y','N')),
    shuffle_q     CHAR(1)         NOT NULL DEFAULT 'N' CHECK (shuffle_q IN ('Y','N')),
    UNIQUE (id_user, title)
);
CREATE SEQUENCE sq_tests START WITH 1 INCREMENT BY 1 NOCACHE;

-- ---- ВОПРОСЫ (БАНК) ----
CREATE TABLE questions (
    id_question   NUMBER          PRIMARY KEY,
    id_type       NUMBER          NOT NULL REFERENCES q_types(id_type),
    id_category   NUMBER          REFERENCES categories(id_category),
    q_text        VARCHAR2(4000)  NOT NULL,
    difficulty    NUMBER(1)       NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
    explanation   VARCHAR2(2000),
    max_score     NUMBER(6,2)     NOT NULL DEFAULT 1
);
CREATE SEQUENCE sq_questions START WITH 1 INCREMENT BY 1 NOCACHE;

-- ---- ВАРИАНТЫ ОТВЕТОВ ----
CREATE TABLE options (
    id_option     NUMBER          PRIMARY KEY,
    id_question   NUMBER          NOT NULL REFERENCES questions(id_question) ON DELETE CASCADE,
    opt_text      VARCHAR2(4000)  NOT NULL,
    is_right      CHAR(1)         NOT NULL DEFAULT 'N' CHECK (is_right IN ('Y','N')),
    -- для MATCHING
    match_left    VARCHAR2(4000),
    match_right   VARCHAR2(4000),
    -- для ORDERING
    position      NUMBER(4)
);
CREATE SEQUENCE sq_options START WITH 1 INCREMENT BY 1 NOCACHE;

-- ---- КОНСТРУКТОР ТЕСТА (связь теста с вопросами) ----
CREATE TABLE test_builder (
    id_builder    NUMBER          PRIMARY KEY,
    id_test       NUMBER          NOT NULL REFERENCES tests(id_test) ON DELETE CASCADE,
    id_question   NUMBER          REFERENCES questions(id_question),   -- NULL при автоподборе
    is_auto       CHAR(1)         NOT NULL DEFAULT 'N' CHECK (is_auto IN ('Y','N')),
    q_order       NUMBER(4),
    score_weight  NUMBER(6,2),
    -- фильтры автоподбора
    auto_count    NUMBER(4),
    auto_type     NUMBER          REFERENCES q_types(id_type),
    auto_category NUMBER          REFERENCES categories(id_category),
    auto_diff     NUMBER(1)       CHECK (auto_diff BETWEEN 1 AND 5)
);
CREATE SEQUENCE sq_test_builder START WITH 1 INCREMENT BY 1 NOCACHE;

-- ---- ПОПЫТКИ ----
CREATE TABLE attempts (
    id_attempt    NUMBER          PRIMARY KEY,
    id_test       NUMBER          NOT NULL REFERENCES tests(id_test),
    id_user       NUMBER          NOT NULL REFERENCES users(id_user),
    id_status     NUMBER          NOT NULL REFERENCES attempt_statuses(id_status),
    id_result     NUMBER          REFERENCES attempt_results(id_result),
    id_reason     NUMBER          REFERENCES finish_reasons(id_reason),
    start_time    TIMESTAMP       NOT NULL,
    end_time      TIMESTAMP,
    score         NUMBER(8,2)
);
CREATE SEQUENCE sq_attempts START WITH 1 INCREMENT BY 1 NOCACHE;

-- ---- ОТВЕТЫ УЧАСТНИКОВ ----
CREATE TABLE user_answers (
    id_answer     NUMBER          PRIMARY KEY,
    id_attempt    NUMBER          NOT NULL REFERENCES attempts(id_attempt) ON DELETE CASCADE,
    id_question   NUMBER          NOT NULL REFERENCES questions(id_question),
    id_option     NUMBER          REFERENCES options(id_option),   -- NULL для TEXT/MULTI
    answer_text   VARCHAR2(4000),                                   -- NULL для CHOICE; CSV для MULTI
    is_correct    CHAR(1)         NOT NULL DEFAULT 'N' CHECK (is_correct IN ('Y','N')),
    points_earned NUMBER(6,2)     NOT NULL DEFAULT 0,
    is_finished   CHAR(1)         NOT NULL DEFAULT 'N' CHECK (is_finished IN ('Y','N'))
);
CREATE SEQUENCE sq_user_answers START WITH 1 INCREMENT BY 1 NOCACHE;

-- ============================================================
-- ИНДЕКСЫ
-- ============================================================
CREATE INDEX idx_tests_user     ON tests(id_user);
CREATE INDEX idx_questions_type ON questions(id_type);
CREATE INDEX idx_options_q      ON options(id_question);
CREATE INDEX idx_builder_test   ON test_builder(id_test);
CREATE INDEX idx_attempts_test  ON attempts(id_test);
CREATE INDEX idx_attempts_user  ON attempts(id_user);
CREATE INDEX idx_answers_attempt ON user_answers(id_attempt);
CREATE INDEX idx_answers_q      ON user_answers(id_question);

-- ---- ВСПОМОГАТЕЛЬНАЯ ТАБЛИЦА-МАРКЕР (ЛР2: add_to_used / delete_used) ----
CREATE TABLE used_questions (
    id_question   NUMBER          PRIMARY KEY,
    CONSTRAINT fk_used_q FOREIGN KEY (id_question)
        REFERENCES questions(id_question) ON DELETE CASCADE
);
