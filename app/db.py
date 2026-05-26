"""
db.py — Слой работы с Oracle через python-oracledb (thin mode).
Все обращения к БД идут через этот модуль.
"""
import os
import oracledb
from contextlib import contextmanager

# ── Параметры подключения (берутся из переменных окружения) ──────────────────
DB_USER     = os.environ.get("DB_USER", "system")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "oracle")
DB_HOST     = os.environ.get("DB_HOST", "localhost")
DB_PORT     = int(os.environ.get("DB_PORT", 1521))
DB_SERVICE  = os.environ.get("DB_SERVICE", "XEPDB1")

# ── Пул соединений ────────────────────────────────────────────────────────────
_pool: oracledb.ConnectionPool | None = None


def init_pool():
    """Инициализация пула при старте Flask-приложения."""
    global _pool
    _pool = oracledb.create_pool(
        user=DB_USER,
        password=DB_PASSWORD,
        host=DB_HOST,
        port=DB_PORT,
        service_name=DB_SERVICE,
        min=2,
        max=10,
        increment=1,
    )


@contextmanager
def get_conn():
    """Контекстный менеджер: берёт соединение из пула, возвращает обратно."""
    conn = _pool.acquire()
    try:
        yield conn
    finally:
        _pool.release(conn)


# ── Вспомогательные функции ───────────────────────────────────────────────────

def _row_to_dict(cursor, row):
    """Конвертация строки курсора в словарь по именам колонок."""
    return {desc[0].lower(): val for desc, val in zip(cursor.description, row)}


def _fetchall_dicts(cursor):
    return [_row_to_dict(cursor, row) for row in cursor.fetchall()]


def _fetchone_dict(cursor):
    row = cursor.fetchone()
    if row is None:
        return None
    return _row_to_dict(cursor, row)


# ── API для Flask-роутов ─────────────────────────────────────────────────────

def authenticate(login: str, pwd_hash: str) -> int:
    """Возвращает id_user или -1."""
    with get_conn() as conn:
        with conn.cursor() as cur:
            result = cur.var(int)
            cur.execute(
                "BEGIN :r := testing_platform.authenticate(:l, :p); END;",
                r=result, l=login, p=pwd_hash
            )
            return result.getvalue()


def get_user(user_id: int) -> dict | None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id_user, login, display_name, role FROM users WHERE id_user = :1",
                [user_id]
            )
            return _fetchone_dict(cur)


def register_user(login: str, display: str, pwd_hash: str, role: str):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "BEGIN testing_platform.register_user(:1,:2,:3,:4); END;",
                [login, display, pwd_hash, role]
            )
            conn.commit()


# ── Тесты ────────────────────────────────────────────────────────────────────

def get_active_tests() -> list[dict]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT t.id_test, t.title, t.description, t.max_score,
                       t.passing_score, t.timer_min, t.is_active,
                       u.display_name AS author,
                       c.name AS category,
                       fm.name AS feedback_mode,
                       (SELECT COUNT(*) FROM test_builder tb
                        WHERE tb.id_test = t.id_test) AS q_count
                  FROM tests t
                  JOIN users         u  ON u.id_user  = t.id_user
                  JOIN feedback_modes fm ON fm.id_mode = t.id_mode
                  LEFT JOIN categories c ON c.id_category = t.id_category
                 WHERE t.is_active = 'Y'
                 ORDER BY t.id_test DESC
            """)
            return _fetchall_dicts(cur)


def get_all_tests_for_author(user_id: int) -> list[dict]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT t.id_test, t.title, t.description, t.max_score,
                       t.passing_score, t.timer_min, t.is_active,
                       fm.name AS feedback_mode,
                       c.name AS category,
                       (SELECT COUNT(*) FROM test_builder tb
                        WHERE tb.id_test = t.id_test) AS q_count
                  FROM tests t
                  JOIN feedback_modes fm ON fm.id_mode = t.id_mode
                  LEFT JOIN categories c ON c.id_category = t.id_category
                 WHERE t.id_user = :1
                 ORDER BY t.id_test DESC
            """, [user_id])
            return _fetchall_dicts(cur)


def get_test(test_id: int) -> dict | None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT t.id_test, t.title, t.description, t.max_score,
                       t.passing_score, t.timer_min, t.is_active,
                       t.shuffle_q, t.id_user,
                       u.display_name AS author,
                       fm.code AS feedback_code, fm.name AS feedback_mode,
                       c.name AS category
                  FROM tests t
                  JOIN users          u  ON u.id_user  = t.id_user
                  JOIN feedback_modes fm ON fm.id_mode = t.id_mode
                  LEFT JOIN categories c ON c.id_category = t.id_category
                 WHERE t.id_test = :1
            """, [test_id])
            return _fetchone_dict(cur)


def create_test(user_id, title, description, max_score, pass_score,
                timer_min, mode_code, cat_id, shuffle) -> int:
    with get_conn() as conn:
        with conn.cursor() as cur:
            out_id = cur.var(int)
            cur.execute("""
                BEGIN testing_platform.create_test(
                    :1,:2,:3,:4,:5,:6,:7,:8,:9,:10
                ); END;
            """, [user_id, title, description, max_score, pass_score,
                  timer_min, mode_code, cat_id, shuffle, out_id])
            conn.commit()
            return out_id.getvalue()


def publish_test(test_id: int, user_id: int):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "BEGIN testing_platform.publish_test(:1,:2); END;",
                [test_id, user_id]
            )
            conn.commit()


def unpublish_test(test_id: int, user_id: int):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "BEGIN testing_platform.unpublish_test(:1,:2); END;",
                [test_id, user_id]
            )
            conn.commit()


def delete_test(test_id: int, user_id: int):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "BEGIN testing_platform.delete_test(:1,:2); END;",
                [test_id, user_id]
            )
            conn.commit()


# ── Вопросы ───────────────────────────────────────────────────────────────────

def get_all_questions() -> list[dict]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT q.id_question, q.q_text, q.difficulty,
                       q.max_score, q.explanation,
                       qt.code AS q_type, qt.name AS type_name,
                       c.name AS category
                  FROM questions q
                  JOIN q_types  qt ON qt.id_type      = q.id_type
                  LEFT JOIN categories c ON c.id_category = q.id_category
                 ORDER BY q.id_question DESC
            """)
            return _fetchall_dicts(cur)


def get_question(q_id: int) -> dict | None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT q.id_question, q.q_text, q.difficulty,
                       q.max_score, q.explanation,
                       qt.code AS q_type, qt.name AS type_name,
                       c.name AS category, q.id_category
                  FROM questions q
                  JOIN q_types  qt ON qt.id_type      = q.id_type
                  LEFT JOIN categories c ON c.id_category = q.id_category
                 WHERE q.id_question = :1
            """, [q_id])
            return _fetchone_dict(cur)


def get_options_for_question(q_id: int) -> list[dict]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT id_option, opt_text, is_right,
                       position, match_left, match_right
                  FROM options
                 WHERE id_question = :1
                 ORDER BY NVL(position, id_option)
            """, [q_id])
            return _fetchall_dicts(cur)


def add_question(type_code, q_text, difficulty, max_score, cat_id, explanation) -> int:
    with get_conn() as conn:
        with conn.cursor() as cur:
            out_id = cur.var(int)
            cur.execute("""
                BEGIN testing_platform.add_question(
                    :1,:2,:3,:4,:5,:6,:7
                ); END;
            """, [type_code, q_text, difficulty, max_score, cat_id, explanation, out_id])
            conn.commit()
            return out_id.getvalue()


def add_option(q_id, opt_text, is_right, position=None,
               match_left=None, match_right=None) -> int:
    with get_conn() as conn:
        with conn.cursor() as cur:
            out_id = cur.var(int)
            cur.execute("""
                BEGIN testing_platform.add_option(
                    :1,:2,:3,:4,:5,:6,:7
                ); END;
            """, [q_id, opt_text, is_right, position, match_left, match_right, out_id])
            conn.commit()
            return out_id.getvalue()


def delete_question(q_id: int):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "BEGIN testing_platform.delete_question(:1); END;",
                [q_id]
            )
            conn.commit()


def add_to_test(test_id, q_id, order_num, weight):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "BEGIN testing_platform.add_to_test(:1,:2,:3,:4); END;",
                [test_id, q_id, order_num, weight]
            )
            conn.commit()


def remove_from_test(test_id, q_id):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "BEGIN testing_platform.remove_from_test(:1,:2); END;",
                [test_id, q_id]
            )
            conn.commit()


def get_test_builder_questions(test_id: int) -> list[dict]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT tb.id_builder, tb.q_order, tb.score_weight,
                       q.id_question, q.q_text, q.difficulty,
                       qt.code AS q_type, qt.name AS type_name
                  FROM test_builder tb
                  JOIN questions q  ON q.id_question = tb.id_question
                  JOIN q_types   qt ON qt.id_type    = q.id_type
                 WHERE tb.id_test = :1
                 ORDER BY tb.q_order
            """, [test_id])
            return _fetchall_dicts(cur)


# ── Попытки ───────────────────────────────────────────────────────────────────

def start_attempt(test_id: int, user_id: int) -> int:
    with get_conn() as conn:
        with conn.cursor() as cur:
            out_id = cur.var(int)
            cur.execute(
                "BEGIN testing_platform.start_attempt(:1,:2,:3); END;",
                [test_id, user_id, out_id]
            )
            conn.commit()
            return out_id.getvalue()


def get_attempt(attempt_id: int) -> dict | None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            ref = cur.var(oracledb.DB_TYPE_CURSOR)
            cur.execute(
                "BEGIN :r := testing_platform.get_attempt_results(:1); END;",
                r=ref, **{"1": attempt_id}
            )
            # Некорректный биндинг — используем прямой SELECT
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT a.id_attempt, a.score,
                       s.code AS status_code, s.name AS status_name,
                       r.code AS result_code, r.name AS result_name,
                       fn.code AS reason_code,
                       t.title AS test_title, t.passing_score, t.max_score,
                       fm.code AS feedback_mode,
                       a.start_time, a.end_time,
                       u.display_name AS student_name,
                       a.id_test, a.id_user
                  FROM attempts          a
                  JOIN attempt_statuses  s  ON s.id_status  = a.id_status
                  JOIN tests             t  ON t.id_test    = a.id_test
                  JOIN feedback_modes    fm ON fm.id_mode   = t.id_mode
                  JOIN users             u  ON u.id_user    = a.id_user
                  LEFT JOIN attempt_results r  ON r.id_result  = a.id_result
                  LEFT JOIN finish_reasons  fn ON fn.id_reason = a.id_reason
                 WHERE a.id_attempt = :1
            """, [attempt_id])
            return _fetchone_dict(cur)


def get_attempt_questions(test_id: int, attempt_id: int) -> list[dict]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT q.id_question,
                       qt.code AS q_type,
                       q.q_text, q.difficulty, q.max_score, q.explanation,
                       tb.q_order, tb.score_weight,
                       NVL(ua.is_correct, 'N')  AS answered_correct,
                       NVL(ua.points_earned, 0) AS points_earned,
                       ua.id_option             AS chosen_option,
                       ua.answer_text           AS given_text
                  FROM test_builder  tb
                  JOIN questions     q  ON q.id_question = tb.id_question
                  JOIN q_types       qt ON qt.id_type    = q.id_type
                  LEFT JOIN user_answers ua
                    ON  ua.id_attempt  = :attempt_id
                    AND ua.id_question = q.id_question
                 WHERE tb.id_test = :test_id
                   AND tb.is_auto = 'N'
                 ORDER BY tb.q_order
            """, attempt_id=attempt_id, test_id=test_id)
            return _fetchall_dicts(cur)


def submit_answer(attempt_id: int, q_id: int,
                  option_id: int | None = None, text: str | None = None):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                BEGIN testing_platform.submit_answer(:1,:2,:3,:4); END;
            """, [attempt_id, q_id, option_id, text])
            conn.commit()


def finish_attempt(attempt_id: int, reason: str = "MANUAL"):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "BEGIN testing_platform.finish_attempt(:1,:2); END;",
                [attempt_id, reason]
            )
            conn.commit()


def get_user_attempts(user_id: int) -> list[dict]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT a.id_attempt, a.score, a.start_time, a.end_time,
                       s.code AS status_code, s.name AS status_name,
                       r.code AS result_code, r.name AS result_name,
                       t.title AS test_title, t.max_score, t.passing_score
                  FROM attempts          a
                  JOIN attempt_statuses  s ON s.id_status = a.id_status
                  JOIN tests             t ON t.id_test   = a.id_test
                  LEFT JOIN attempt_results r ON r.id_result = a.id_result
                 WHERE a.id_user = :1
                 ORDER BY a.start_time DESC
            """, [user_id])
            return _fetchall_dicts(cur)


def get_answer_details(attempt_id: int) -> list[dict]:
    """Детализация ответов — для разбора после теста."""
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT ua.id_question, ua.is_correct, ua.points_earned,
                       ua.answer_text, ua.id_option,
                       q.q_text, q.max_score, q.explanation,
                       qt.code AS q_type,
                       o.opt_text AS chosen_text
                  FROM user_answers ua
                  JOIN questions    q  ON q.id_question = ua.id_question
                  JOIN q_types      qt ON qt.id_type    = q.id_type
                  LEFT JOIN options o  ON o.id_option   = ua.id_option
                 WHERE ua.id_attempt = :1
                 ORDER BY q.id_question
            """, [attempt_id])
            return _fetchall_dicts(cur)


# ── Справочники ───────────────────────────────────────────────────────────────

def get_feedback_modes() -> list[dict]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id_mode, code, name FROM feedback_modes ORDER BY id_mode")
            return _fetchall_dicts(cur)


def get_categories() -> list[dict]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT id_category, name, description, id_parent
                  FROM categories ORDER BY id_category
            """)
            return _fetchall_dicts(cur)


def get_q_types() -> list[dict]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id_type, code, name FROM q_types ORDER BY id_type")
            return _fetchall_dicts(cur)


def get_test_stats(test_id: int) -> dict | None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT COUNT(*)                                          AS total_attempts,
                       SUM(CASE WHEN r.code='PASS' THEN 1 ELSE 0 END)  AS passed,
                       SUM(CASE WHEN r.code='FAIL' THEN 1 ELSE 0 END)  AS failed,
                       ROUND(AVG(a.score), 2)                           AS avg_score,
                       MAX(a.score)                                     AS max_score_res,
                       MIN(a.score)                                     AS min_score_res
                  FROM attempts          a
                  JOIN attempt_statuses  s ON s.id_status  = a.id_status
                  LEFT JOIN attempt_results r ON r.id_result = a.id_result
                 WHERE a.id_test = :1
                   AND s.code   = 'COMPLETED'
            """, [test_id])
            return _fetchone_dict(cur)


# ── Статистика и графики ──────────────────────────────────────────────────

def get_score_distribution(test_id: int) -> list[dict]:
    """Все завершённые баллы по тесту (для гистограммы)."""
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT a.score, t.max_score
                  FROM attempts          a
                  JOIN attempt_statuses  s ON s.id_status = a.id_status
                  JOIN tests             t ON t.id_test   = a.id_test
                 WHERE a.id_test = :1
                   AND s.code   = 'COMPLETED'
                   AND a.score  IS NOT NULL
                 ORDER BY a.score
            """, [test_id])
            return _fetchall_dicts(cur)


def get_question_correctness(test_id: int) -> list[dict]:
    """Процент правильных ответов по каждому вопросу теста."""
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT q.id_question,
                       SUBSTR(q.q_text, 1, 45)                              AS q_short,
                       COUNT(ua.id_answer)                                   AS total_answered,
                       SUM(CASE WHEN ua.is_correct='Y' THEN 1 ELSE 0 END)   AS correct_count,
                       ROUND(
                           SUM(CASE WHEN ua.is_correct='Y' THEN 1 ELSE 0 END)
                           * 100.0 / NULLIF(COUNT(ua.id_answer), 0), 1
                       )                                                     AS pct_correct
                  FROM test_builder    tb
                  JOIN questions       q  ON q.id_question = tb.id_question
                  JOIN user_answers    ua ON ua.id_question = q.id_question
                  JOIN attempts        a  ON a.id_attempt  = ua.id_attempt
                  JOIN attempt_statuses s ON s.id_status   = a.id_status
                 WHERE tb.id_test = :1
                   AND s.code    = 'COMPLETED'
                 GROUP BY q.id_question, SUBSTR(q.q_text, 1, 45), tb.q_order
                 ORDER BY tb.q_order
            """, [test_id])
            return _fetchall_dicts(cur)


def get_platform_overview() -> dict | None:
    """Агрегированная сводка по всей платформе."""
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    (SELECT COUNT(*) FROM tests WHERE is_active = 'Y')      AS active_tests,
                    (SELECT COUNT(*) FROM users)                              AS total_users,
                    (SELECT COUNT(*) FROM attempts)                          AS total_attempts,
                    (SELECT COUNT(*)
                       FROM attempts a
                       JOIN attempt_statuses s ON s.id_status = a.id_status
                      WHERE s.code = 'COMPLETED')                           AS completed_attempts,
                    (SELECT COUNT(*)
                       FROM attempts a
                       JOIN attempt_statuses  s ON s.id_status = a.id_status
                       JOIN attempt_results   r ON r.id_result = a.id_result
                      WHERE s.code = 'COMPLETED' AND r.code = 'PASS')       AS passed_attempts
                  FROM DUAL
            """)
            return _fetchone_dict(cur)


def get_tests_attempt_counts() -> list[dict]:
    """Топ-10 активных тестов по числу попыток."""
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT t.id_test,
                       t.title,
                       COUNT(a.id_attempt)                                   AS attempt_count,
                       SUM(CASE WHEN r.code='PASS' THEN 1 ELSE 0 END)       AS pass_count,
                       SUM(CASE WHEN r.code='FAIL' THEN 1 ELSE 0 END)       AS fail_count
                  FROM tests t
                  LEFT JOIN attempts          a  ON a.id_test    = t.id_test
                  LEFT JOIN attempt_statuses  s  ON s.id_status  = a.id_status
                                                AND s.code       = 'COMPLETED'
                  LEFT JOIN attempt_results   r  ON r.id_result  = a.id_result
                 WHERE t.is_active = 'Y'
                 GROUP BY t.id_test, t.title
                 ORDER BY attempt_count DESC
                 FETCH FIRST 10 ROWS ONLY
            """)
            return _fetchall_dicts(cur)
