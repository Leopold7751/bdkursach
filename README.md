# QuizPlatform — Платформа онлайн-тестирования

Oracle DB (PL/SQL) + Flask (Python) + Docker

---

## Архитектура

```
quiz_platform/
├── docker-compose.yml          # Оркестрация: Oracle XE + Flask
├── sql/
│   ├── 01_ddl.sql              # Таблицы, последовательности, индексы
│   ├── 02_seed.sql             # Справочники + тестовые данные
│   └── 03_package.sql          # PL/SQL пакет testing_platform
└── app/
    ├── Dockerfile
    ├── requirements.txt
    ├── app.py                  # Flask роуты
    ├── db.py                   # Слой Oracle (python-oracledb)
    └── templates/              # HTML (Jinja2)
        ├── base.html
        ├── index.html
        ├── login.html / register.html
        ├── tests_list.html / test_detail.html
        ├── attempt.html        # Прохождение теста (с таймером)
        ├── results.html        # Результаты с разбором
        ├── my_attempts.html
        ├── author_tests.html / author_test_edit.html / author_test_form.html
        ├── author_questions.html / author_question_form.html
```

---

## Быстрый старт (Docker)

```bash
# 1. Клонируй / распакуй проект
cd quiz_platform

# 2. Запусти контейнеры (первый раз ~3-5 минут — Oracle инициализируется)
docker compose up -d

# 3. Следи за логами Oracle
docker logs -f quiz_oracle

# 4. Когда Oracle поднялся — приложение доступно:
# http://localhost:5000
```

Oracle автоматически выполнит SQL-скрипты из `./sql/` при первом старте.

---

## Без Docker (локально)

### 1. Oracle XE

Установи [Oracle XE 21c](https://www.oracle.com/database/technologies/xe-downloads.html)
или используй существующий экземпляр.

Выполни скрипты в нужной схеме:
```sql
-- В SQL*Plus / SQLcl / SQL Developer:
@sql/01_ddl.sql
@sql/02_seed.sql
@sql/03_package.sql
```

### 2. Python

```bash
cd app
pip install -r requirements.txt

# Настрой переменные окружения:
export DB_USER=quiz_user
export DB_PASSWORD=quiz_pass
export DB_HOST=localhost
export DB_PORT=1521
export DB_SERVICE=XEPDB1

python app.py
# → http://localhost:5000
```

---

## Схема БД

### Основные таблицы
| Таблица | Назначение |
|---------|-----------|
| `users` | Пользователи (student / author / admin) |
| `tests` | Тесты с параметрами |
| `questions` | Банк вопросов (отдельно от тестов) |
| `options` | Варианты ответов |
| `test_builder` | Связь теста с вопросами (конструктор) |
| `attempts` | Попытки прохождения |
| `user_answers` | Ответы участников |

### Справочники
| Таблица | Значения |
|---------|---------|
| `q_types` | SINGLE, MULTI, TEXT, NUMERIC, ORDERING, MATCHING, FILL |
| `attempt_statuses` | IN_PROGRESS, COMPLETED, ABANDONED |
| `feedback_modes` | NEVER, AFTER_ATTEMPT, PER_QUESTION |
| `attempt_results` | PASS, FAIL, PENDING |
| `finish_reasons` | MANUAL, TIME_EXPIRED, ABANDONED |
| `categories` | Иерархические категории вопросов/тестов |

### PL/SQL пакет `testing_platform`
Весь бизнес-процесс — в Oracle:
- `authenticate` — аутентификация по логину + SHA-256 хэшу
- `register_user` — регистрация с проверкой уникальности логина
- `create_test` / `publish_test` / `unpublish_test` / `delete_test`
- `add_question` / `delete_question` / `add_option`
- `add_to_test` / `remove_from_test` — управление конструктором
- `start_attempt` — создаёт попытку, предзаполняет заготовки ответов
- `submit_answer` — проверяет ответ, начисляет баллы
- `finish_attempt` — подсчитывает итог, выставляет PASS/FAIL
- `is_correct_answer` — логика проверки по типу вопроса
- `calc_score` — суммирует набранные баллы

---

## Демо-аккаунты (пароль: `password`)

| Логин | Роль | Возможности |
|-------|------|------------|
| `admin` | Администратор | Все функции |
| `author1` | Составитель | Создание тестов, банк вопросов |
| `student1` | Студент | Прохождение тестов |

---

## Возможности платформы

**Составитель:**
- Создание тестов с настройкой таймера, проходного балла, режима ОС
- Банк вопросов (7 типов) — независим от конкретного теста
- Конструктор теста — ручная привязка вопросов с указанием порядка и веса
- Публикация / снятие с публикации
- Просмотр статистики попыток

**Студент:**
- Прохождение теста с навигацией по вопросам
- Таймер с автоматическим завершением
- Сохранение ответов через AJAX (без перезагрузки страницы)
- Просмотр детального разбора (зависит от режима ОС теста)
- История всех своих попыток

---

## Связь с курсовой работой (КР) и ЛР2

| Элемент КР/ЛР | Реализация |
|---------------|-----------|
| 13 сущностей из КР | Полностью (справочники + основные) |
| ER / KB / FA-диаграммы | DDL в `01_ddl.sql` |
| PL/SQL пакет из ЛР2 | Расширен в `03_package.sql` |
| Нормализация (3НФ) | Соблюдена: справочники, суррогатные ключи |
| Рекурсивная связь | `categories.id_parent → categories.id_category` |
