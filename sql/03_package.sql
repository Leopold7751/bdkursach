-- ============================================================
-- 03_package.sql — PL/SQL пакет testing_platform
-- Объединяет:
--   • лабораторный интерфейс (ЛР2)  — g_current_attempt + 14 процедур/функций
--   • веб-интерфейс (КР)             — полный CRUD + прохождение теста
-- ============================================================

-- ============================================================
-- СПЕЦИФИКАЦИЯ ПАКЕТА
-- ============================================================
CREATE OR REPLACE PACKAGE testing_platform AS

    -- ── Пакетная переменная (ЛР2: stateful-сессия в SQL*Plus) ────────────
    g_current_attempt  NUMBER := NULL;

    -- ── ЛР2: лабораторный интерфейс ──────────────────────────────────────

    PROCEDURE info;

    PROCEDURE start_test      (v_id_test    NUMBER,
                               v_login      VARCHAR2);

    -- перегрузка add_question: 5 параметров (ЛР2)
    PROCEDURE add_question    (v_id_test    NUMBER,
                               v_text       VARCHAR2,
                               v_type       VARCHAR2,
                               v_difficulty NUMBER,
                               v_max_score  NUMBER);

    PROCEDURE make_question   (v_text       VARCHAR2,
                               v_type       VARCHAR2,
                               v_difficulty NUMBER,
                               v_move       NUMBER);

    PROCEDURE add_to_used     (v_id_question NUMBER);
    PROCEDURE delete_used     (v_id_question NUMBER);

    PROCEDURE answer          (v_id_question NUMBER,
                               v_value       VARCHAR2);

    FUNCTION  is_correct      (v_id_question NUMBER,
                               v_value       VARCHAR2) RETURN NUMBER;

    FUNCTION  is_passed       (v_id_attempt  NUMBER)   RETURN NUMBER;
    FUNCTION  next_question   (v_id_attempt  NUMBER)   RETURN NUMBER;

    PROCEDURE make_finished   (v_id_question NUMBER);
    PROCEDURE clear           (v_id_attempt  NUMBER);
    PROCEDURE check_winner    (v_id_attempt  NUMBER);
    PROCEDURE show_results    (v_id_attempt  NUMBER);

    -- ── Веб-интерфейс: аутентификация ────────────────────────────────────

    FUNCTION  authenticate    (p_login    VARCHAR2,
                               p_pwd_hash VARCHAR2) RETURN NUMBER;

    PROCEDURE register_user   (p_login    VARCHAR2,
                               p_display  VARCHAR2,
                               p_pwd_hash VARCHAR2,
                               p_role     VARCHAR2);

    -- ── Веб-интерфейс: тесты ─────────────────────────────────────────────

    PROCEDURE create_test     (p_id_user     NUMBER,
                               p_title       VARCHAR2,
                               p_description VARCHAR2,
                               p_max_score   NUMBER,
                               p_pass_score  NUMBER,
                               p_timer_min   NUMBER,
                               p_mode_code   VARCHAR2,
                               p_cat_id      NUMBER,
                               p_shuffle     VARCHAR2,
                               p_id_test     OUT NUMBER);

    PROCEDURE publish_test    (p_id_test  NUMBER, p_id_user NUMBER);
    PROCEDURE unpublish_test  (p_id_test  NUMBER, p_id_user NUMBER);
    PROCEDURE delete_test     (p_id_test  NUMBER, p_id_user NUMBER);

    -- перегрузка add_question: 7 параметров с OUT (веб)
    PROCEDURE add_question    (p_type_code   VARCHAR2,
                               p_q_text      VARCHAR2,
                               p_difficulty  NUMBER,
                               p_max_score   NUMBER,
                               p_cat_id      NUMBER,
                               p_explanation VARCHAR2,
                               p_id_question OUT NUMBER);

    PROCEDURE delete_question (p_id_question NUMBER);

    -- ── Веб-интерфейс: варианты ответов ──────────────────────────────────

    PROCEDURE add_option      (p_id_question NUMBER,
                               p_opt_text    VARCHAR2,
                               p_is_right    VARCHAR2,
                               p_position    NUMBER   DEFAULT NULL,
                               p_match_left  VARCHAR2 DEFAULT NULL,
                               p_match_right VARCHAR2 DEFAULT NULL,
                               p_id_option   OUT NUMBER);

    -- ── Веб-интерфейс: конструктор теста ─────────────────────────────────

    PROCEDURE add_to_test     (p_id_test     NUMBER,
                               p_id_question NUMBER,
                               p_order       NUMBER,
                               p_weight      NUMBER);

    PROCEDURE remove_from_test(p_id_test     NUMBER,
                               p_id_question NUMBER);

    -- ── Прохождение теста ────────────────────────────────────────────────

    PROCEDURE start_attempt   (p_id_test    NUMBER,
                               p_id_user    NUMBER,
                               p_id_attempt OUT NUMBER);

    PROCEDURE submit_answer   (p_id_attempt  NUMBER,
                               p_id_question NUMBER,
                               p_id_option   NUMBER   DEFAULT NULL,
                               p_text        VARCHAR2 DEFAULT NULL);

    PROCEDURE finish_attempt  (p_id_attempt  NUMBER,
                               p_reason_code VARCHAR2 DEFAULT 'MANUAL');

    -- ── Курсоры ──────────────────────────────────────────────────────────

    FUNCTION  get_test_questions  (p_id_test    NUMBER,
                                   p_id_attempt NUMBER) RETURN SYS_REFCURSOR;

    FUNCTION  get_attempt_results (p_id_attempt NUMBER) RETURN SYS_REFCURSOR;

    FUNCTION  get_test_stats      (p_id_test    NUMBER) RETURN SYS_REFCURSOR;

    -- ── Утилиты ──────────────────────────────────────────────────────────

    FUNCTION  is_correct_answer   (p_id_question NUMBER,
                                   p_id_option   NUMBER,
                                   p_text        VARCHAR2) RETURN CHAR;

    FUNCTION  calc_score          (p_id_attempt  NUMBER) RETURN NUMBER;

END testing_platform;
/


-- ============================================================
-- ТЕЛО ПАКЕТА
-- ============================================================
CREATE OR REPLACE PACKAGE BODY testing_platform AS

    -- ──────────────────────────────────────────────────────────────────────
    -- ПРИВАТНЫЕ УТИЛИТЫ
    -- ──────────────────────────────────────────────────────────────────────

    FUNCTION get_status_id(p_code VARCHAR2) RETURN NUMBER IS
        v_id NUMBER;
    BEGIN
        SELECT id_status INTO v_id FROM attempt_statuses WHERE code = p_code;
        RETURN v_id;
    END;

    FUNCTION get_result_id(p_code VARCHAR2) RETURN NUMBER IS
        v_id NUMBER;
    BEGIN
        SELECT id_result INTO v_id FROM attempt_results WHERE code = p_code;
        RETURN v_id;
    END;

    FUNCTION get_reason_id(p_code VARCHAR2) RETURN NUMBER IS
        v_id NUMBER;
    BEGIN
        SELECT id_reason INTO v_id FROM finish_reasons WHERE code = p_code;
        RETURN v_id;
    END;

    FUNCTION get_type_id(p_code VARCHAR2) RETURN NUMBER IS
        v_id NUMBER;
    BEGIN
        SELECT id_type INTO v_id FROM q_types WHERE code = p_code;
        RETURN v_id;
    END;

    -- ──────────────────────────────────────────────────────────────────────
    -- ПРОВЕРКА ПРАВИЛЬНОСТИ ОТВЕТА (общая)
    -- SINGLE  : p_id_option — выбранный вариант
    -- MULTI   : p_text      — CSV из id_option (напр. "5,8,12")
    -- TEXT/FILL/NUMERIC : p_text — введённое значение
    -- ──────────────────────────────────────────────────────────────────────
    FUNCTION is_correct_answer(p_id_question NUMBER,
                               p_id_option   NUMBER,
                               p_text        VARCHAR2) RETURN CHAR IS
        v_type_code VARCHAR2(30);
        v_is_right  CHAR(1) := 'N';
        v_etalon    VARCHAR2(4000);
    BEGIN
        SELECT qt.code INTO v_type_code
          FROM questions q
          JOIN q_types   qt ON qt.id_type = q.id_type
         WHERE q.id_question = p_id_question;

        IF v_type_code = 'SINGLE' THEN
            BEGIN
                SELECT NVL(is_right, 'N') INTO v_is_right
                  FROM options
                 WHERE id_option   = p_id_option
                   AND id_question = p_id_question;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN v_is_right := 'N';
            END;

        ELSIF v_type_code = 'MULTI' THEN
            -- p_text содержит CSV выбранных id_option («5,8,12»).
            -- Правильно, если множество выбранных == множеству правильных.
            IF p_text IS NOT NULL THEN
                DECLARE
                    v_correct_cnt NUMBER;
                    v_match_cnt   NUMBER;
                    v_select_cnt  NUMBER;
                BEGIN
                    SELECT COUNT(*) INTO v_correct_cnt
                      FROM options
                     WHERE id_question = p_id_question AND is_right = 'Y';

                    SELECT COUNT(*) INTO v_match_cnt
                      FROM options
                     WHERE id_question = p_id_question
                       AND is_right    = 'Y'
                       AND INSTR(',' || p_text || ',',
                                 ',' || TO_CHAR(id_option) || ',') > 0;

                    SELECT COUNT(*) INTO v_select_cnt
                      FROM options
                     WHERE id_question = p_id_question
                       AND INSTR(',' || p_text || ',',
                                 ',' || TO_CHAR(id_option) || ',') > 0;

                    IF v_correct_cnt  > 0
                       AND v_match_cnt  = v_correct_cnt
                       AND v_select_cnt = v_correct_cnt THEN
                        v_is_right := 'Y';
                    END IF;
                EXCEPTION
                    WHEN OTHERS THEN v_is_right := 'N';
                END;
            ELSIF p_id_option IS NOT NULL THEN
                -- обратная совместимость: единственный вариант
                BEGIN
                    SELECT NVL(is_right, 'N') INTO v_is_right
                      FROM options
                     WHERE id_option   = p_id_option
                       AND id_question = p_id_question;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN v_is_right := 'N';
                END;
            END IF;

        ELSIF v_type_code IN ('TEXT', 'FILL') THEN
            BEGIN
                SELECT opt_text INTO v_etalon
                  FROM options
                 WHERE id_question = p_id_question
                   AND is_right    = 'Y'
                   AND ROWNUM      = 1;

                IF LOWER(TRIM(p_text)) = LOWER(TRIM(v_etalon)) THEN
                    v_is_right := 'Y';
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN v_is_right := 'N';
            END;

        ELSIF v_type_code = 'NUMERIC' THEN
            BEGIN
                SELECT opt_text INTO v_etalon
                  FROM options
                 WHERE id_question = p_id_question
                   AND is_right    = 'Y'
                   AND ROWNUM      = 1;

                IF TO_NUMBER(TRIM(p_text)) = TO_NUMBER(TRIM(v_etalon)) THEN
                    v_is_right := 'Y';
                END IF;
            EXCEPTION
                WHEN OTHERS THEN v_is_right := 'N';
            END;
        END IF;

        RETURN v_is_right;
    END is_correct_answer;

    -- ──────────────────────────────────────────────────────────────────────
    -- РАСЧЁТ ИТОГОВОГО БАЛЛА
    -- ──────────────────────────────────────────────────────────────────────
    FUNCTION calc_score(p_id_attempt NUMBER) RETURN NUMBER IS
        v_score NUMBER;
    BEGIN
        SELECT NVL(SUM(points_earned), 0)
          INTO v_score
          FROM user_answers
         WHERE id_attempt = p_id_attempt;
        RETURN v_score;
    END;

    -- ══════════════════════════════════════════════════════════════════════
    --  ЛР2: ЛАБОРАТОРНЫЙ ИНТЕРФЕЙС
    -- ══════════════════════════════════════════════════════════════════════

    -- ──────────────────────────────────────────────────────────────────────
    -- INFO — информация о пакете
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE info IS
        v_tests    NUMBER;
        v_users    NUMBER;
        v_attempts NUMBER;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('================================================');
        DBMS_OUTPUT.PUT_LINE('  ПЛАТФОРМА ОНЛАЙН-ТЕСТИРОВАНИЯ  v1.0');
        DBMS_OUTPUT.PUT_LINE('  Oracle Database + Flask + Python');
        DBMS_OUTPUT.PUT_LINE('================================================');
        DBMS_OUTPUT.PUT_LINE('Активная попытка : ' ||
                             NVL(TO_CHAR(g_current_attempt), 'не начата'));

        SELECT COUNT(*) INTO v_tests    FROM tests WHERE is_active = 'Y';
        SELECT COUNT(*) INTO v_users    FROM users;
        SELECT COUNT(*) INTO v_attempts FROM attempts;

        DBMS_OUTPUT.PUT_LINE('Активных тестов  : ' || v_tests);
        DBMS_OUTPUT.PUT_LINE('Пользователей    : ' || v_users);
        DBMS_OUTPUT.PUT_LINE('Всего попыток    : ' || v_attempts);
        DBMS_OUTPUT.PUT_LINE('================================================');
    END info;

    -- ──────────────────────────────────────────────────────────────────────
    -- START_TEST — начать попытку по логину студента
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE start_test(v_id_test NUMBER, v_login VARCHAR2) IS
        v_user_id NUMBER;
    BEGIN
        BEGIN
            SELECT id_user INTO v_user_id FROM users WHERE login = v_login;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20100,
                    'Пользователь не найден: ' || v_login);
        END;

        start_attempt(v_id_test, v_user_id, g_current_attempt);

        DBMS_OUTPUT.PUT_LINE('Попытка #' || g_current_attempt || ' начата.');
        DBMS_OUTPUT.PUT_LINE('Тест: ' || v_id_test ||
                             '  |  Студент: ' || v_login);
    END start_test;

    -- ──────────────────────────────────────────────────────────────────────
    -- ADD_QUESTION (ЛР2, 5 параметров) — создать вопрос и добавить в тест
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE add_question(v_id_test    NUMBER,
                           v_text       VARCHAR2,
                           v_type       VARCHAR2,
                           v_difficulty NUMBER,
                           v_max_score  NUMBER) IS
        v_q_id  NUMBER;
        v_order NUMBER;
    BEGIN
        add_question(v_type, v_text, v_difficulty, v_max_score,
                     NULL, NULL, v_q_id);

        SELECT NVL(MAX(q_order), 0) + 1 INTO v_order
          FROM test_builder WHERE id_test = v_id_test;

        add_to_test(v_id_test, v_q_id, v_order, v_max_score);

        DBMS_OUTPUT.PUT_LINE('Вопрос #' || v_q_id ||
                             ' добавлен в тест #' || v_id_test);
    END add_question;

    -- ──────────────────────────────────────────────────────────────────────
    -- MAKE_QUESTION — создать вопрос в банке; v_move=1 → добавить в used
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE make_question(v_text       VARCHAR2,
                            v_type       VARCHAR2,
                            v_difficulty NUMBER,
                            v_move       NUMBER) IS
        v_q_id NUMBER;
    BEGIN
        add_question(v_type, v_text, v_difficulty, 1, NULL, NULL, v_q_id);

        IF v_move = 1 THEN
            add_to_used(v_q_id);
            DBMS_OUTPUT.PUT_LINE('Вопрос #' || v_q_id ||
                                 ' создан и помечен в used_questions.');
        ELSE
            DBMS_OUTPUT.PUT_LINE('Вопрос #' || v_q_id || ' создан.');
        END IF;
    END make_question;

    -- ──────────────────────────────────────────────────────────────────────
    -- ADD_TO_USED / DELETE_USED
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE add_to_used(v_id_question NUMBER) IS
    BEGIN
        INSERT INTO used_questions(id_question) VALUES (v_id_question);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Вопрос #' || v_id_question ||
                             ' добавлен в used_questions.');
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            DBMS_OUTPUT.PUT_LINE('Вопрос #' || v_id_question ||
                                 ' уже в used_questions.');
    END add_to_used;

    PROCEDURE delete_used(v_id_question NUMBER) IS
    BEGIN
        DELETE FROM used_questions WHERE id_question = v_id_question;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Вопрос #' || v_id_question ||
                             ' удалён из used_questions.');
    END delete_used;

    -- ──────────────────────────────────────────────────────────────────────
    -- ANSWER — сохранить ответ в текущей попытке + пометить вопрос finished
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE answer(v_id_question NUMBER, v_value VARCHAR2) IS
        v_type_code VARCHAR2(30);
    BEGIN
        IF g_current_attempt IS NULL THEN
            RAISE_APPLICATION_ERROR(-20110,
                'Попытка не начата. Вызовите start_test().');
        END IF;

        BEGIN
            SELECT qt.code INTO v_type_code
              FROM questions q
              JOIN q_types   qt ON qt.id_type = q.id_type
             WHERE q.id_question = v_id_question;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20111,
                    'Вопрос не найден: ' || v_id_question);
        END;

        IF v_type_code = 'SINGLE' THEN
            submit_answer(g_current_attempt, v_id_question,
                          TO_NUMBER(TRIM(v_value)), NULL);
        ELSE
            submit_answer(g_current_attempt, v_id_question,
                          NULL, v_value);
        END IF;

        make_finished(v_id_question);

        DBMS_OUTPUT.PUT_LINE('Ответ сохранён для вопроса #' ||
                             v_id_question || '.');
    END answer;

    -- ──────────────────────────────────────────────────────────────────────
    -- IS_CORRECT — вернуть 1/0
    -- ──────────────────────────────────────────────────────────────────────
    FUNCTION is_correct(v_id_question NUMBER, v_value VARCHAR2) RETURN NUMBER IS
        v_type_code VARCHAR2(30);
        v_result    CHAR(1);
    BEGIN
        SELECT qt.code INTO v_type_code
          FROM questions q
          JOIN q_types   qt ON qt.id_type = q.id_type
         WHERE q.id_question = v_id_question;

        IF v_type_code = 'SINGLE' THEN
            v_result := is_correct_answer(v_id_question,
                                          TO_NUMBER(TRIM(v_value)), NULL);
        ELSE
            v_result := is_correct_answer(v_id_question, NULL, v_value);
        END IF;

        RETURN CASE WHEN v_result = 'Y' THEN 1 ELSE 0 END;
    EXCEPTION
        WHEN OTHERS THEN RETURN 0;
    END is_correct;

    -- ──────────────────────────────────────────────────────────────────────
    -- IS_PASSED — вернуть 1 если зачёт, 0 иначе
    -- ──────────────────────────────────────────────────────────────────────
    FUNCTION is_passed(v_id_attempt NUMBER) RETURN NUMBER IS
        v_score NUMBER;
        v_pass  NUMBER;
    BEGIN
        v_score := calc_score(v_id_attempt);

        SELECT t.passing_score INTO v_pass
          FROM attempts a
          JOIN tests    t ON t.id_test = a.id_test
         WHERE a.id_attempt = v_id_attempt;

        IF v_pass IS NULL THEN RETURN 1; END IF;
        RETURN CASE WHEN v_score >= v_pass THEN 1 ELSE 0 END;
    EXCEPTION
        WHEN OTHERS THEN RETURN 0;
    END is_passed;

    -- ──────────────────────────────────────────────────────────────────────
    -- NEXT_QUESTION — вернуть id первого незавершённого вопроса
    -- ──────────────────────────────────────────────────────────────────────
    FUNCTION next_question(v_id_attempt NUMBER) RETURN NUMBER IS
        v_q_id NUMBER;
    BEGIN
        SELECT id_question INTO v_q_id
          FROM (
              SELECT ua.id_question
                FROM user_answers ua
               WHERE ua.id_attempt  = v_id_attempt
                 AND ua.is_finished = 'N'
               ORDER BY ua.id_answer
          )
         WHERE ROWNUM = 1;
        RETURN v_q_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;
    END next_question;

    -- ──────────────────────────────────────────────────────────────────────
    -- MAKE_FINISHED — пометить вопрос завершённым в текущей попытке
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE make_finished(v_id_question NUMBER) IS
    BEGIN
        IF g_current_attempt IS NULL THEN
            RAISE_APPLICATION_ERROR(-20112, 'Попытка не начата.');
        END IF;

        UPDATE user_answers
           SET is_finished = 'Y'
         WHERE id_attempt  = g_current_attempt
           AND id_question = v_id_question;
        COMMIT;
    END make_finished;

    -- ──────────────────────────────────────────────────────────────────────
    -- CLEAR — сбросить все ответы попытки
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE clear(v_id_attempt NUMBER) IS
    BEGIN
        UPDATE user_answers
           SET id_option     = NULL,
               answer_text   = NULL,
               is_correct    = 'N',
               points_earned = 0,
               is_finished   = 'N'
         WHERE id_attempt = v_id_attempt;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Ответы попытки #' || v_id_attempt ||
                             ' сброшены.');
    END clear;

    -- ──────────────────────────────────────────────────────────────────────
    -- CHECK_WINNER — вывести итог (зачёт/незачёт)
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE check_winner(v_id_attempt NUMBER) IS
        v_passed NUMBER;
        v_score  NUMBER;
        v_pass   NUMBER;
    BEGIN
        v_passed := is_passed(v_id_attempt);
        v_score  := calc_score(v_id_attempt);

        BEGIN
            SELECT t.passing_score INTO v_pass
              FROM attempts a
              JOIN tests    t ON t.id_test = a.id_test
             WHERE a.id_attempt = v_id_attempt;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN v_pass := NULL;
        END;

        DBMS_OUTPUT.PUT_LINE('=== Попытка #' || v_id_attempt || ' ===');
        DBMS_OUTPUT.PUT_LINE(
            'Набрано: ' || v_score ||
            CASE WHEN v_pass IS NOT NULL
                 THEN '  (порог зачёта: ' || v_pass || ')'
                 ELSE '' END
        );
        IF v_passed = 1 THEN
            DBMS_OUTPUT.PUT_LINE('Результат: ЗАЧЁТ  ✓');
        ELSE
            DBMS_OUTPUT.PUT_LINE('Результат: НЕЗАЧЁТ ✗');
        END IF;
    END check_winner;

    -- ──────────────────────────────────────────────────────────────────────
    -- SHOW_RESULTS — детальный вывод результатов
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE show_results(v_id_attempt NUMBER) IS
        CURSOR c_res IS
            SELECT q.q_text,
                   qt.code            AS q_type,
                   ua.is_correct,
                   ua.points_earned,
                   q.max_score,
                   ua.answer_text,
                   o.opt_text,
                   ua.is_finished
              FROM user_answers ua
              JOIN questions    q  ON q.id_question = ua.id_question
              JOIN q_types      qt ON qt.id_type    = q.id_type
              LEFT JOIN options  o  ON o.id_option   = ua.id_option
             WHERE ua.id_attempt = v_id_attempt
             ORDER BY ua.id_answer;
        v_total NUMBER := 0;
        v_ans   VARCHAR2(200);
    BEGIN
        DBMS_OUTPUT.PUT_LINE('=== Результаты попытки #' ||
                             v_id_attempt || ' ===');
        FOR r IN c_res LOOP
            DBMS_OUTPUT.PUT_LINE('');
            DBMS_OUTPUT.PUT_LINE(
                'Вопрос (' || r.q_type || '): ' ||
                SUBSTR(r.q_text, 1, 80)
            );

            IF r.opt_text IS NOT NULL THEN
                v_ans := r.opt_text;
            ELSIF r.answer_text IS NOT NULL THEN
                v_ans := r.answer_text;
            ELSE
                v_ans := '(не дан)';
            END IF;
            DBMS_OUTPUT.PUT_LINE('  Ответ     : ' || v_ans);
            DBMS_OUTPUT.PUT_LINE(
                '  Правильно : ' || r.is_correct ||
                '   Баллов: '    || NVL(r.points_earned, 0) ||
                ' / '            || r.max_score
            );
            v_total := v_total + NVL(r.points_earned, 0);
        END LOOP;
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('--- ИТОГО: ' || v_total || ' баллов ---');
    END show_results;

    -- ══════════════════════════════════════════════════════════════════════
    --  ВЕБ-ИНТЕРФЕЙС
    -- ══════════════════════════════════════════════════════════════════════

    -- ──────────────────────────────────────────────────────────────────────
    -- AUTHENTICATE
    -- ──────────────────────────────────────────────────────────────────────
    FUNCTION authenticate(p_login VARCHAR2, p_pwd_hash VARCHAR2) RETURN NUMBER IS
        v_id NUMBER;
    BEGIN
        SELECT id_user INTO v_id
          FROM users
         WHERE login    = p_login
           AND pwd_hash = p_pwd_hash;
        RETURN v_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN -1;
    END authenticate;

    -- ──────────────────────────────────────────────────────────────────────
    -- REGISTER_USER
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE register_user(p_login    VARCHAR2,
                            p_display  VARCHAR2,
                            p_pwd_hash VARCHAR2,
                            p_role     VARCHAR2) IS
    BEGIN
        INSERT INTO users (id_user, login, display_name, pwd_hash, role)
        VALUES (sq_users.NEXTVAL, p_login, p_display, p_pwd_hash, p_role);
        COMMIT;
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            RAISE_APPLICATION_ERROR(-20001,
                'Логин уже занят: ' || p_login);
    END register_user;

    -- ──────────────────────────────────────────────────────────────────────
    -- CREATE_TEST
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE create_test(p_id_user     NUMBER,
                          p_title       VARCHAR2,
                          p_description VARCHAR2,
                          p_max_score   NUMBER,
                          p_pass_score  NUMBER,
                          p_timer_min   NUMBER,
                          p_mode_code   VARCHAR2,
                          p_cat_id      NUMBER,
                          p_shuffle     VARCHAR2,
                          p_id_test     OUT NUMBER) IS
        v_mode_id NUMBER;
    BEGIN
        SELECT id_mode INTO v_mode_id
          FROM feedback_modes WHERE code = p_mode_code;

        p_id_test := sq_tests.NEXTVAL;

        INSERT INTO tests (id_test, id_user, id_category, id_mode,
                           title, description, max_score, passing_score,
                           timer_min, is_active, shuffle_q)
        VALUES (p_id_test, p_id_user, p_cat_id, v_mode_id,
                p_title, p_description, p_max_score, p_pass_score,
                p_timer_min, 'N', NVL(p_shuffle, 'N'));
        COMMIT;
    END create_test;

    -- ──────────────────────────────────────────────────────────────────────
    -- PUBLISH / UNPUBLISH / DELETE TEST
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE publish_test(p_id_test NUMBER, p_id_user NUMBER) IS
        v_count NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_count
          FROM test_builder WHERE id_test = p_id_test;

        IF v_count = 0 THEN
            RAISE_APPLICATION_ERROR(-20010,
                'Нельзя опубликовать тест без вопросов');
        END IF;

        UPDATE tests SET is_active = 'Y'
         WHERE id_test = p_id_test AND id_user = p_id_user;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20011, 'Тест не найден или нет прав');
        END IF;
        COMMIT;
    END publish_test;

    PROCEDURE unpublish_test(p_id_test NUMBER, p_id_user NUMBER) IS
    BEGIN
        UPDATE tests SET is_active = 'N'
         WHERE id_test = p_id_test AND id_user = p_id_user;
        COMMIT;
    END unpublish_test;

    PROCEDURE delete_test(p_id_test NUMBER, p_id_user NUMBER) IS
    BEGIN
        DELETE FROM tests
         WHERE id_test = p_id_test AND id_user = p_id_user;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20012, 'Тест не найден или нет прав');
        END IF;
        COMMIT;
    END delete_test;

    -- ──────────────────────────────────────────────────────────────────────
    -- ADD_QUESTION (веб, 7 параметров с OUT)
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE add_question(p_type_code   VARCHAR2,
                           p_q_text      VARCHAR2,
                           p_difficulty  NUMBER,
                           p_max_score   NUMBER,
                           p_cat_id      NUMBER,
                           p_explanation VARCHAR2,
                           p_id_question OUT NUMBER) IS
        v_type_id NUMBER;
    BEGIN
        IF p_q_text IS NULL OR LENGTH(TRIM(p_q_text)) = 0 THEN
            RAISE_APPLICATION_ERROR(-20020,
                'Текст вопроса не может быть пустым');
        END IF;
        IF p_difficulty NOT BETWEEN 1 AND 5 THEN
            RAISE_APPLICATION_ERROR(-20021,
                'Сложность должна быть от 1 до 5');
        END IF;
        IF p_max_score <= 0 THEN
            RAISE_APPLICATION_ERROR(-20022,
                'Балл за вопрос должен быть > 0');
        END IF;

        v_type_id     := get_type_id(p_type_code);
        p_id_question := sq_questions.NEXTVAL;

        INSERT INTO questions (id_question, id_type, id_category,
                               q_text, difficulty, explanation, max_score)
        VALUES (p_id_question, v_type_id, p_cat_id,
                p_q_text, p_difficulty, p_explanation, p_max_score);
        COMMIT;
    END add_question;

    -- ──────────────────────────────────────────────────────────────────────
    -- DELETE_QUESTION
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE delete_question(p_id_question NUMBER) IS
        v_count NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_count
          FROM user_answers ua
          JOIN attempts        a ON a.id_attempt = ua.id_attempt
          JOIN attempt_statuses s ON s.id_status  = a.id_status
         WHERE ua.id_question = p_id_question
           AND s.code         = 'IN_PROGRESS';

        IF v_count > 0 THEN
            RAISE_APPLICATION_ERROR(-20030,
                'Вопрос используется в активной попытке');
        END IF;

        DELETE FROM questions WHERE id_question = p_id_question;
        COMMIT;
    END delete_question;

    -- ──────────────────────────────────────────────────────────────────────
    -- ADD_OPTION
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE add_option(p_id_question NUMBER,
                         p_opt_text    VARCHAR2,
                         p_is_right    VARCHAR2,
                         p_position    NUMBER   DEFAULT NULL,
                         p_match_left  VARCHAR2 DEFAULT NULL,
                         p_match_right VARCHAR2 DEFAULT NULL,
                         p_id_option   OUT NUMBER) IS
    BEGIN
        p_id_option := sq_options.NEXTVAL;
        INSERT INTO options (id_option, id_question, opt_text, is_right,
                             position, match_left, match_right)
        VALUES (p_id_option, p_id_question, p_opt_text,
                NVL(p_is_right, 'N'),
                p_position, p_match_left, p_match_right);
        COMMIT;
    END add_option;

    -- ──────────────────────────────────────────────────────────────────────
    -- ADD_TO_TEST / REMOVE_FROM_TEST
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE add_to_test(p_id_test     NUMBER,
                          p_id_question NUMBER,
                          p_order       NUMBER,
                          p_weight      NUMBER) IS
        v_cnt NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_cnt
          FROM test_builder
         WHERE id_test    = p_id_test
           AND id_question = p_id_question;

        IF v_cnt > 0 THEN
            RAISE_APPLICATION_ERROR(-20040,
                'Вопрос уже добавлен в этот тест');
        END IF;

        INSERT INTO test_builder (id_builder, id_test, id_question,
                                  is_auto, q_order, score_weight)
        VALUES (sq_test_builder.NEXTVAL, p_id_test, p_id_question,
                'N', p_order, p_weight);
        COMMIT;
    END add_to_test;

    PROCEDURE remove_from_test(p_id_test NUMBER, p_id_question NUMBER) IS
    BEGIN
        DELETE FROM test_builder
         WHERE id_test     = p_id_test
           AND id_question = p_id_question;
        COMMIT;
    END remove_from_test;

    -- ──────────────────────────────────────────────────────────────────────
    -- START_ATTEMPT
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE start_attempt(p_id_test    NUMBER,
                            p_id_user    NUMBER,
                            p_id_attempt OUT NUMBER) IS
        v_active    CHAR(1);
        v_in_prog   NUMBER;
    BEGIN
        SELECT is_active INTO v_active FROM tests WHERE id_test = p_id_test;

        IF v_active != 'Y' THEN
            RAISE_APPLICATION_ERROR(-20050, 'Тест не активен');
        END IF;

        -- Вернуть существующую незавершённую попытку
        SELECT COUNT(*) INTO v_in_prog
          FROM attempts          a
          JOIN attempt_statuses  s ON s.id_status = a.id_status
         WHERE a.id_test = p_id_test
           AND a.id_user = p_id_user
           AND s.code    = 'IN_PROGRESS';

        IF v_in_prog > 0 THEN
            SELECT id_attempt INTO p_id_attempt
              FROM (
                  SELECT a.id_attempt
                    FROM attempts          a
                    JOIN attempt_statuses  s ON s.id_status = a.id_status
                   WHERE a.id_test = p_id_test
                     AND a.id_user = p_id_user
                     AND s.code    = 'IN_PROGRESS'
                   ORDER BY a.start_time DESC
              )
             WHERE ROWNUM = 1;
            RETURN;
        END IF;

        p_id_attempt := sq_attempts.NEXTVAL;

        INSERT INTO attempts (id_attempt, id_test, id_user,
                              id_status, start_time)
        VALUES (p_id_attempt, p_id_test, p_id_user,
                get_status_id('IN_PROGRESS'), SYSTIMESTAMP);

        -- Предзаполнение слотов ответов (обеспечивает is_finished)
        INSERT INTO user_answers (id_answer, id_attempt, id_question,
                                  is_correct, points_earned, is_finished)
        SELECT sq_user_answers.NEXTVAL, p_id_attempt, tb.id_question,
               'N', 0, 'N'
          FROM test_builder tb
         WHERE tb.id_test     = p_id_test
           AND tb.id_question IS NOT NULL
           AND tb.is_auto     = 'N';

        COMMIT;
    END start_attempt;

    -- ──────────────────────────────────────────────────────────────────────
    -- SUBMIT_ANSWER
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE submit_answer(p_id_attempt  NUMBER,
                            p_id_question NUMBER,
                            p_id_option   NUMBER   DEFAULT NULL,
                            p_text        VARCHAR2 DEFAULT NULL) IS
        v_correct   CHAR(1);
        v_max_score NUMBER;
        v_points    NUMBER := 0;
        v_status    VARCHAR2(30);
    BEGIN
        SELECT s.code INTO v_status
          FROM attempts          a
          JOIN attempt_statuses  s ON s.id_status = a.id_status
         WHERE a.id_attempt = p_id_attempt;

        IF v_status != 'IN_PROGRESS' THEN
            RAISE_APPLICATION_ERROR(-20060, 'Попытка уже завершена');
        END IF;

        SELECT max_score INTO v_max_score
          FROM questions WHERE id_question = p_id_question;

        v_correct := is_correct_answer(p_id_question, p_id_option, p_text);

        IF v_correct = 'Y' THEN
            v_points := v_max_score;
        END IF;

        UPDATE user_answers
           SET id_option     = p_id_option,
               answer_text   = p_text,
               is_correct    = v_correct,
               points_earned = v_points
         WHERE id_attempt    = p_id_attempt
           AND id_question   = p_id_question;

        IF SQL%ROWCOUNT = 0 THEN
            INSERT INTO user_answers (id_answer, id_attempt, id_question,
                                      id_option, answer_text,
                                      is_correct, points_earned, is_finished)
            VALUES (sq_user_answers.NEXTVAL, p_id_attempt, p_id_question,
                    p_id_option, p_text, v_correct, v_points, 'N');
        END IF;

        COMMIT;
    END submit_answer;

    -- ──────────────────────────────────────────────────────────────────────
    -- FINISH_ATTEMPT
    -- ──────────────────────────────────────────────────────────────────────
    PROCEDURE finish_attempt(p_id_attempt  NUMBER,
                             p_reason_code VARCHAR2 DEFAULT 'MANUAL') IS
        v_score       NUMBER;
        v_pass_score  NUMBER;
        v_result_code VARCHAR2(30);
        v_result_id   NUMBER;
    BEGIN
        v_score := calc_score(p_id_attempt);

        SELECT t.passing_score INTO v_pass_score
          FROM attempts a
          JOIN tests    t ON t.id_test = a.id_test
         WHERE a.id_attempt = p_id_attempt;

        IF v_pass_score IS NULL THEN
            v_result_code := 'PENDING';
        ELSIF v_score >= v_pass_score THEN
            v_result_code := 'PASS';
        ELSE
            v_result_code := 'FAIL';
        END IF;

        v_result_id := get_result_id(v_result_code);

        UPDATE attempts
           SET id_status  = get_status_id('COMPLETED'),
               id_result  = v_result_id,
               id_reason  = get_reason_id(p_reason_code),
               end_time   = SYSTIMESTAMP,
               score      = v_score
         WHERE id_attempt = p_id_attempt;

        COMMIT;
    END finish_attempt;

    -- ──────────────────────────────────────────────────────────────────────
    -- GET_TEST_QUESTIONS
    -- ──────────────────────────────────────────────────────────────────────
    FUNCTION get_test_questions(p_id_test    NUMBER,
                                p_id_attempt NUMBER) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT q.id_question,
                   qt.code                    AS q_type,
                   q.q_text,
                   q.difficulty,
                   q.max_score,
                   q.explanation,
                   tb.q_order,
                   tb.score_weight,
                   NVL(ua.is_correct, 'N')    AS answered_correct,
                   NVL(ua.points_earned, 0)   AS points_earned,
                   ua.id_option               AS chosen_option,
                   ua.answer_text             AS given_text
              FROM test_builder  tb
              JOIN questions     q  ON q.id_question = tb.id_question
              JOIN q_types       qt ON qt.id_type    = q.id_type
              LEFT JOIN user_answers ua
                ON  ua.id_attempt  = p_id_attempt
                AND ua.id_question = q.id_question
             WHERE tb.id_test = p_id_test
               AND tb.is_auto = 'N'
             ORDER BY tb.q_order;
        RETURN v_cur;
    END get_test_questions;

    -- ──────────────────────────────────────────────────────────────────────
    -- GET_ATTEMPT_RESULTS
    -- ──────────────────────────────────────────────────────────────────────
    FUNCTION get_attempt_results(p_id_attempt NUMBER) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT a.id_attempt,
                   a.score,
                   s.code            AS status_code,
                   s.name            AS status_name,
                   r.code            AS result_code,
                   r.name            AS result_name,
                   fn.code           AS reason_code,
                   t.title           AS test_title,
                   t.passing_score,
                   t.max_score,
                   fm.code           AS feedback_mode,
                   a.start_time,
                   a.end_time,
                   u.display_name    AS student_name
              FROM attempts          a
              JOIN attempt_statuses  s  ON s.id_status  = a.id_status
              JOIN tests             t  ON t.id_test    = a.id_test
              JOIN feedback_modes    fm ON fm.id_mode   = t.id_mode
              JOIN users             u  ON u.id_user    = a.id_user
              LEFT JOIN attempt_results r  ON r.id_result  = a.id_result
              LEFT JOIN finish_reasons  fn ON fn.id_reason = a.id_reason
             WHERE a.id_attempt = p_id_attempt;
        RETURN v_cur;
    END get_attempt_results;

    -- ──────────────────────────────────────────────────────────────────────
    -- GET_TEST_STATS
    -- ──────────────────────────────────────────────────────────────────────
    FUNCTION get_test_stats(p_id_test NUMBER) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT COUNT(*)                                             AS total_attempts,
                   SUM(CASE WHEN r.code = 'PASS' THEN 1 ELSE 0 END)   AS passed,
                   SUM(CASE WHEN r.code = 'FAIL' THEN 1 ELSE 0 END)   AS failed,
                   ROUND(AVG(a.score), 2)                              AS avg_score,
                   MAX(a.score)                                        AS max_score,
                   MIN(a.score)                                        AS min_score
              FROM attempts          a
              JOIN attempt_statuses  s ON s.id_status  = a.id_status
              LEFT JOIN attempt_results r ON r.id_result = a.id_result
             WHERE a.id_test = p_id_test
               AND s.code   = 'COMPLETED';
        RETURN v_cur;
    END get_test_stats;

END testing_platform;
/
