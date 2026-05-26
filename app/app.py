"""
app.py — Flask-приложение платформы онлайн-тестирования.
Вся бизнес-логика делегируется в Oracle (пакет testing_platform).
"""
import hashlib
import io
import base64
from functools import wraps
from flask import (Flask, render_template, request, redirect,
                   url_for, session, flash, jsonify)

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

import db

app = Flask(__name__)
app.secret_key = "quiz_platform_secret_2026"


# ── Генерация matplotlib-графиков ─────────────────────────────────────────────
_BG      = '#0d0e13'
_SURFACE = '#1a1d2a'
_TEXT    = '#e8eaf0'
_MUTED   = '#7b7f96'
_ACCENT  = '#5d6dff'
_SUCCESS = '#2de8a0'
_DANGER  = '#ff6b6b'
_WARNING = '#ffd166'
_BORDER  = '#252838'


def _chart_to_b64(fig) -> str:
    buf = io.BytesIO()
    fig.savefig(buf, format='png', bbox_inches='tight',
                facecolor=_BG, edgecolor='none', dpi=110)
    buf.seek(0)
    result = base64.b64encode(buf.read()).decode('utf-8')
    plt.close(fig)
    return result


def _make_pass_fail_pie(passed: int, failed: int) -> str:
    fig, ax = plt.subplots(figsize=(5, 4))
    fig.patch.set_facecolor(_BG)
    ax.set_facecolor(_BG)
    passed = passed or 0
    failed = failed or 0
    if passed + failed == 0:
        ax.text(0.5, 0.5, 'Нет данных', ha='center', va='center',
                color=_MUTED, fontsize=12, transform=ax.transAxes)
        ax.axis('off')
        return _chart_to_b64(fig)
    wedges, texts, autotexts = ax.pie(
        [passed, failed],
        labels=['Зачёт', 'Незачёт'],
        colors=[_SUCCESS, _DANGER],
        explode=(0.05, 0),
        autopct='%1.1f%%',
        startangle=90,
        textprops={'color': _TEXT, 'fontsize': 11},
        pctdistance=0.8,
    )
    for at in autotexts:
        at.set_color(_BG)
        at.set_fontsize(10)
        at.set_fontweight('bold')
    ax.set_title('Зачёт / Незачёт', color=_TEXT, fontsize=13, pad=12)
    return _chart_to_b64(fig)


def _make_score_histogram(scores: list, max_score: float) -> str:
    fig, ax = plt.subplots(figsize=(7, 4))
    fig.patch.set_facecolor(_BG)
    ax.set_facecolor(_SURFACE)
    if not scores:
        ax.text(0.5, 0.5, 'Нет данных', ha='center', va='center',
                color=_MUTED, fontsize=12, transform=ax.transAxes)
        ax.axis('off')
        return _chart_to_b64(fig)
    n_bins = min(10, max(5, len(scores) // 2 + 1))
    ax.hist(scores, bins=n_bins, color=_ACCENT, edgecolor=_BG,
            linewidth=0.8, alpha=0.85, range=(0, max_score or 10))
    ax.set_xlabel('Баллы', color=_MUTED, fontsize=10)
    ax.set_ylabel('Число попыток', color=_MUTED, fontsize=10)
    ax.set_title('Распределение баллов', color=_TEXT, fontsize=13, pad=12)
    ax.tick_params(colors=_MUTED)
    for spine in ax.spines.values():
        spine.set_color(_BORDER)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.set_xlim(0, max_score or 10)
    return _chart_to_b64(fig)


def _make_question_bar(labels: list, pcts: list) -> str:
    if not labels:
        return ''
    fig, ax = plt.subplots(figsize=(8, max(3, len(labels) * 0.55 + 1.5)))
    fig.patch.set_facecolor(_BG)
    ax.set_facecolor(_SURFACE)
    y = range(len(labels))
    colors = [_SUCCESS if p >= 70 else (_WARNING if p >= 40 else _DANGER)
              for p in pcts]
    bars = ax.barh(list(y), pcts, color=colors, edgecolor=_BG,
                   linewidth=0.5, height=0.6)
    ax.set_yticks(list(y))
    ax.set_yticklabels(labels, color=_MUTED, fontsize=9)
    ax.set_xlabel('% правильных ответов', color=_MUTED, fontsize=10)
    ax.set_title('Правильность по вопросам', color=_TEXT, fontsize=13, pad=12)
    ax.set_xlim(0, 105)
    ax.tick_params(axis='x', colors=_MUTED)
    for spine in ax.spines.values():
        spine.set_color(_BORDER)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    for bar, pct in zip(bars, pcts):
        ax.text(min(pct + 1, 98), bar.get_y() + bar.get_height() / 2,
                f'{pct:.0f}%', va='center', ha='left',
                color=_TEXT, fontsize=9, fontweight='bold')
    plt.tight_layout()
    return _chart_to_b64(fig)


def _make_tests_bar(titles: list, counts: list) -> str:
    if not titles:
        return ''
    fig, ax = plt.subplots(figsize=(8, max(3, len(titles) * 0.55 + 1.5)))
    fig.patch.set_facecolor(_BG)
    ax.set_facecolor(_SURFACE)
    y = range(len(titles))
    ax.barh(list(y), counts, color=_ACCENT, edgecolor=_BG,
            linewidth=0.5, height=0.6, alpha=0.85)
    short = [t[:42] + '…' if len(t) > 42 else t for t in titles]
    ax.set_yticks(list(y))
    ax.set_yticklabels(short, color=_MUTED, fontsize=9)
    ax.set_xlabel('Количество попыток', color=_MUTED, fontsize=10)
    ax.set_title('Популярность тестов', color=_TEXT, fontsize=13, pad=12)
    ax.tick_params(axis='x', colors=_MUTED)
    for spine in ax.spines.values():
        spine.set_color(_BORDER)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    plt.tight_layout()
    return _chart_to_b64(fig)


# ── Хэширование пароля ────────────────────────────────────────────────────────
def hash_password(pwd: str) -> str:
    return hashlib.sha256(pwd.encode()).hexdigest()


# ── Декораторы доступа ────────────────────────────────────────────────────────
def login_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        if "user_id" not in session:
            flash("Необходимо войти в систему", "warning")
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return wrapper


def author_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        if session.get("role") not in ("author", "admin"):
            flash("Доступ только для составителей", "danger")
            return redirect(url_for("index"))
        return f(*args, **kwargs)
    return login_required(wrapper)


# ── Главная страница ──────────────────────────────────────────────────────────
@app.route("/")
def index():
    tests = db.get_active_tests()
    return render_template("index.html", tests=tests)


# ── Авторизация ───────────────────────────────────────────────────────────────
@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        login_val = request.form.get("login", "").strip()
        password  = request.form.get("password", "")
        pwd_hash  = hash_password(password)

        user_id = db.authenticate(login_val, pwd_hash)
        if user_id > 0:
            user = db.get_user(user_id)
            session["user_id"]     = user_id
            session["login"]       = user["login"]
            session["display_name"]= user["display_name"]
            session["role"]        = user["role"]
            flash(f"Добро пожаловать, {user['display_name']}!", "success")
            return redirect(url_for("index"))
        else:
            flash("Неверный логин или пароль", "danger")

    return render_template("login.html")


@app.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        login_val   = request.form.get("login", "").strip()
        display     = request.form.get("display_name", "").strip()
        password    = request.form.get("password", "")
        role        = request.form.get("role", "student")

        if not login_val or not password or not display:
            flash("Заполните все поля", "danger")
            return render_template("register.html")

        try:
            db.register_user(login_val, display, hash_password(password), role)
            flash("Регистрация успешна! Войдите в систему.", "success")
            return redirect(url_for("login"))
        except Exception as e:
            flash(str(e), "danger")

    return render_template("register.html")


@app.route("/logout")
def logout():
    session.clear()
    flash("Вы вышли из системы", "info")
    return redirect(url_for("index"))


# ── Каталог тестов (для студентов) ───────────────────────────────────────────
@app.route("/tests")
@login_required
def tests_list():
    tests = db.get_active_tests()
    return render_template("tests_list.html", tests=tests)


@app.route("/tests/<int:test_id>")
@login_required
def test_detail(test_id):
    test = db.get_test(test_id)
    if not test:
        flash("Тест не найден", "danger")
        return redirect(url_for("tests_list"))
    questions = db.get_test_builder_questions(test_id)
    stats = db.get_test_stats(test_id)
    return render_template("test_detail.html", test=test,
                           questions=questions, stats=stats)


# ── Прохождение теста ─────────────────────────────────────────────────────────
@app.route("/attempt/start/<int:test_id>", methods=["POST"])
@login_required
def start_attempt(test_id):
    try:
        attempt_id = db.start_attempt(test_id, session["user_id"])
        return redirect(url_for("attempt_view", attempt_id=attempt_id))
    except Exception as e:
        flash(str(e), "danger")
        return redirect(url_for("test_detail", test_id=test_id))


@app.route("/attempt/<int:attempt_id>")
@login_required
def attempt_view(attempt_id):
    attempt = db.get_attempt(attempt_id)
    if not attempt:
        flash("Попытка не найдена", "danger")
        return redirect(url_for("tests_list"))

    # Защита: только владелец попытки
    if attempt["id_user"] != session["user_id"]:
        flash("Нет доступа к этой попытке", "danger")
        return redirect(url_for("tests_list"))

    if attempt["status_code"] != "IN_PROGRESS":
        return redirect(url_for("attempt_results", attempt_id=attempt_id))

    questions = db.get_attempt_questions(attempt["id_test"], attempt_id)
    options_map = {}
    for q in questions:
        options_map[q["id_question"]] = db.get_options_for_question(q["id_question"])

    return render_template("attempt.html",
                           attempt=attempt,
                           questions=questions,
                           options_map=options_map)


@app.route("/attempt/<int:attempt_id>/answer", methods=["POST"])
@login_required
def submit_answer(attempt_id):
    attempt = db.get_attempt(attempt_id)
    if not attempt or attempt["id_user"] != session["user_id"]:
        return jsonify({"error": "Нет доступа"}), 403

    q_id      = int(request.form.get("q_id"))
    option_id = request.form.get("option_id")
    text      = request.form.get("text")

    option_id = int(option_id) if option_id else None
    text      = text.strip() if text else None

    try:
        db.submit_answer(attempt_id, q_id, option_id, text)
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 400


@app.route("/attempt/<int:attempt_id>/finish", methods=["POST"])
@login_required
def finish_attempt(attempt_id):
    attempt = db.get_attempt(attempt_id)
    if not attempt or attempt["id_user"] != session["user_id"]:
        flash("Нет доступа", "danger")
        return redirect(url_for("index"))

    reason = request.form.get("reason", "MANUAL")
    try:
        db.finish_attempt(attempt_id, reason)
    except Exception as e:
        flash(str(e), "danger")

    return redirect(url_for("attempt_results", attempt_id=attempt_id))


@app.route("/attempt/<int:attempt_id>/results")
@login_required
def attempt_results(attempt_id):
    attempt = db.get_attempt(attempt_id)
    if not attempt:
        flash("Попытка не найдена", "danger")
        return redirect(url_for("tests_list"))

    if attempt["id_user"] != session["user_id"] and session.get("role") not in ("author","admin"):
        flash("Нет доступа", "danger")
        return redirect(url_for("index"))

    details = []
    if attempt["feedback_mode"] in ("AFTER_ATTEMPT", "PER_QUESTION"):
        details = db.get_answer_details(attempt_id)
        for d in details:
            if d["q_type"] in ("SINGLE", "MULTI"):
                opts = db.get_options_for_question(d["id_question"])
                d["all_options"] = opts

    return render_template("results.html", attempt=attempt, details=details)


# ── История попыток пользователя ─────────────────────────────────────────────
@app.route("/my/attempts")
@login_required
def my_attempts():
    attempts = db.get_user_attempts(session["user_id"])
    return render_template("my_attempts.html", attempts=attempts)


# ── Кабинет составителя ───────────────────────────────────────────────────────
@app.route("/author/tests")
@author_required
def author_tests():
    tests = db.get_all_tests_for_author(session["user_id"])
    return render_template("author_tests.html", tests=tests)


@app.route("/author/tests/new", methods=["GET", "POST"])
@author_required
def author_test_new():
    if request.method == "POST":
        try:
            test_id = db.create_test(
                user_id     = session["user_id"],
                title       = request.form["title"],
                description = request.form.get("description"),
                max_score   = float(request.form["max_score"]),
                pass_score  = float(request.form["pass_score"]) if request.form.get("pass_score") else None,
                timer_min   = int(request.form["timer_min"]) if request.form.get("timer_min") else None,
                mode_code   = request.form["mode_code"],
                cat_id      = int(request.form["cat_id"]) if request.form.get("cat_id") else None,
                shuffle     = request.form.get("shuffle", "N"),
            )
            flash("Тест создан!", "success")
            return redirect(url_for("author_test_edit", test_id=test_id))
        except Exception as e:
            flash(str(e), "danger")

    modes = db.get_feedback_modes()
    cats  = db.get_categories()
    return render_template("author_test_form.html", test=None,
                           modes=modes, cats=cats)


@app.route("/author/tests/<int:test_id>/edit")
@author_required
def author_test_edit(test_id):
    test = db.get_test(test_id)
    if not test or test["id_user"] != session["user_id"]:
        flash("Тест не найден или нет прав", "danger")
        return redirect(url_for("author_tests"))

    builder_qs = db.get_test_builder_questions(test_id)
    all_qs     = db.get_all_questions()
    stats      = db.get_test_stats(test_id)
    return render_template("author_test_edit.html",
                           test=test, builder_qs=builder_qs,
                           all_qs=all_qs, stats=stats)


@app.route("/author/tests/<int:test_id>/publish", methods=["POST"])
@author_required
def author_publish(test_id):
    try:
        db.publish_test(test_id, session["user_id"])
        flash("Тест опубликован", "success")
    except Exception as e:
        flash(str(e), "danger")
    return redirect(url_for("author_test_edit", test_id=test_id))


@app.route("/author/tests/<int:test_id>/unpublish", methods=["POST"])
@author_required
def author_unpublish(test_id):
    db.unpublish_test(test_id, session["user_id"])
    flash("Тест снят с публикации", "info")
    return redirect(url_for("author_test_edit", test_id=test_id))


@app.route("/author/tests/<int:test_id>/delete", methods=["POST"])
@author_required
def author_delete_test(test_id):
    try:
        db.delete_test(test_id, session["user_id"])
        flash("Тест удалён", "info")
    except Exception as e:
        flash(str(e), "danger")
    return redirect(url_for("author_tests"))


@app.route("/author/tests/<int:test_id>/add_question", methods=["POST"])
@author_required
def author_add_question_to_test(test_id):
    q_id   = int(request.form["q_id"])
    order  = int(request.form.get("order", 1))
    weight = float(request.form.get("weight", 1))
    try:
        db.add_to_test(test_id, q_id, order, weight)
        flash("Вопрос добавлен в тест", "success")
    except Exception as e:
        flash(str(e), "danger")
    return redirect(url_for("author_test_edit", test_id=test_id))


@app.route("/author/tests/<int:test_id>/remove_question/<int:q_id>", methods=["POST"])
@author_required
def author_remove_question_from_test(test_id, q_id):
    try:
        db.remove_from_test(test_id, q_id)
        flash("Вопрос удалён из теста", "info")
    except Exception as e:
        flash(str(e), "danger")
    return redirect(url_for("author_test_edit", test_id=test_id))


# ── Банк вопросов ─────────────────────────────────────────────────────────────
@app.route("/author/questions")
@author_required
def author_questions():
    questions = db.get_all_questions()
    return render_template("author_questions.html", questions=questions)


@app.route("/author/questions/new", methods=["GET", "POST"])
@author_required
def author_question_new():
    if request.method == "POST":
        try:
            q_id = db.add_question(
                type_code   = request.form["type_code"],
                q_text      = request.form["q_text"],
                difficulty  = int(request.form["difficulty"]),
                max_score   = float(request.form["max_score"]),
                cat_id      = int(request.form["cat_id"]) if request.form.get("cat_id") else None,
                explanation = request.form.get("explanation"),
            )
            # Добавляем варианты ответов
            _save_options_from_form(q_id, request.form)

            flash("Вопрос создан!", "success")
            return redirect(url_for("author_questions"))
        except Exception as e:
            flash(str(e), "danger")

    types = db.get_q_types()
    cats  = db.get_categories()
    return render_template("author_question_form.html",
                           question=None, types=types, cats=cats,
                           options=[])


@app.route("/author/questions/<int:q_id>/delete", methods=["POST"])
@author_required
def author_delete_question(q_id):
    try:
        db.delete_question(q_id)
        flash("Вопрос удалён", "info")
    except Exception as e:
        flash(str(e), "danger")
    return redirect(url_for("author_questions"))


def _save_options_from_form(q_id, form):
    """Парсинг вариантов ответов из формы."""
    # Ожидаем: opt_text_1, opt_right_1, opt_text_2, ...
    i = 1
    while f"opt_text_{i}" in form:
        text     = form.get(f"opt_text_{i}", "").strip()
        is_right = "Y" if form.get(f"opt_right_{i}") else "N"
        pos      = form.get(f"opt_pos_{i}")
        ml       = form.get(f"opt_mleft_{i}", "").strip() or None
        mr       = form.get(f"opt_mright_{i}", "").strip() or None

        if text:
            db.add_option(q_id, text, is_right,
                          int(pos) if pos else None, ml, mr)
        i += 1


# ── Статистика платформы ─────────────────────────────────────────────────────
@app.route("/stats")
@login_required
def platform_stats():
    if session.get("role") not in ("author", "admin"):
        flash("Доступ только для составителей и администраторов", "danger")
        return redirect(url_for("index"))

    overview = db.get_platform_overview()
    tests    = db.get_tests_attempt_counts()
    charts   = {}

    if overview:
        completed = overview.get("completed_attempts") or 0
        passed    = overview.get("passed_attempts") or 0
        failed    = completed - passed
        charts["pass_fail"] = _make_pass_fail_pie(passed, failed)

    if tests:
        titles = [t["title"] for t in tests]
        counts = [t["attempt_count"] or 0 for t in tests]
        charts["tests_bar"] = _make_tests_bar(titles, counts)

    return render_template("stats.html",
                           overview=overview, tests=tests, charts=charts)


@app.route("/author/tests/<int:test_id>/stats")
@author_required
def test_stats_view(test_id):
    test = db.get_test(test_id)
    if not test or test["id_user"] != session["user_id"]:
        flash("Тест не найден или нет прав", "danger")
        return redirect(url_for("author_tests"))

    stats      = db.get_test_stats(test_id)
    score_data = db.get_score_distribution(test_id)
    q_data     = db.get_question_correctness(test_id)
    charts     = {}

    if stats:
        charts["pass_fail"] = _make_pass_fail_pie(
            stats.get("passed") or 0,
            stats.get("failed") or 0,
        )
    if score_data:
        scores    = [float(r["score"]) for r in score_data if r["score"] is not None]
        max_score = float(score_data[0]["max_score"]) if score_data else (test["max_score"] or 10)
        if scores:
            charts["histogram"] = _make_score_histogram(scores, max_score)
    if q_data:
        labels = [f"В{i+1}: {r['q_short']}" for i, r in enumerate(q_data)]
        pcts   = [float(r["pct_correct"] or 0) for r in q_data]
        charts["q_bar"] = _make_question_bar(labels, pcts)

    return render_template("test_stats.html",
                           test=test, stats=stats,
                           q_data=q_data, charts=charts)


# ── Старт ─────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    db.init_pool()
    app.run(host="0.0.0.0", port=5000, debug=True)
