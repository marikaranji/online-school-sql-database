-- Итоговый проект: база данных онлайн-школы
-- СУБД: SQLite
-- Выполнила: Каландия Мари

PRAGMA foreign_keys = ON;

-- Удаление таблиц для повторного запуска файла
DROP TABLE IF EXISTS certificates;
DROP TABLE IF EXISTS submissions;
DROP TABLE IF EXISTS lesson_homeworks;
DROP TABLE IF EXISTS homeworks;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS enrollments;
DROP TABLE IF EXISTS lessons;
DROP TABLE IF EXISTS study_groups;
DROP TABLE IF EXISTS courses;
DROP TABLE IF EXISTS teachers;
DROP TABLE IF EXISTS students;

-- 1. Студенты
CREATE TABLE students (
    student_id INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    phone TEXT,
    registration_date TEXT NOT NULL,
    student_status TEXT NOT NULL DEFAULT 'active'
        CHECK (student_status IN ('active', 'paused', 'blocked'))
);

-- 2. Преподаватели
CREATE TABLE teachers (
    teacher_id INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    specialization TEXT NOT NULL,
    hire_date TEXT NOT NULL
);

-- 3. Курсы. Рекурсивная связь реализована через prerequisite_course_id:
-- один курс может быть продолжением другого курса.
CREATE TABLE courses (
    course_id INTEGER PRIMARY KEY AUTOINCREMENT,
    course_name TEXT NOT NULL UNIQUE,
    level TEXT NOT NULL CHECK (level IN ('beginner', 'middle', 'advanced')),
    price REAL NOT NULL CHECK (price >= 0),
    teacher_id INTEGER NOT NULL,
    prerequisite_course_id INTEGER,
    FOREIGN KEY (teacher_id) REFERENCES teachers(teacher_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (prerequisite_course_id) REFERENCES courses(course_id)
        ON DELETE SET NULL ON UPDATE CASCADE
);

-- 4. Учебные группы
CREATE TABLE study_groups (
    group_id INTEGER PRIMARY KEY AUTOINCREMENT,
    group_name TEXT NOT NULL UNIQUE,
    course_id INTEGER NOT NULL,
    start_date TEXT NOT NULL,
    max_students INTEGER NOT NULL CHECK (max_students BETWEEN 1 AND 40),
    FOREIGN KEY (course_id) REFERENCES courses(course_id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- 5. Занятия
CREATE TABLE lessons (
    lesson_id INTEGER PRIMARY KEY AUTOINCREMENT,
    course_id INTEGER NOT NULL,
    group_id INTEGER NOT NULL,
    lesson_number INTEGER NOT NULL CHECK (lesson_number > 0),
    topic TEXT NOT NULL,
    lesson_date TEXT NOT NULL,
    UNIQUE (group_id, lesson_number),
    FOREIGN KEY (course_id) REFERENCES courses(course_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (group_id) REFERENCES study_groups(group_id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- 6. Запись студента на курс: таблица реализует связь M:N между students и courses
CREATE TABLE enrollments (
    enrollment_id INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id INTEGER NOT NULL,
    course_id INTEGER NOT NULL,
    group_id INTEGER NOT NULL,
    enrollment_date TEXT NOT NULL,
    enrollment_status TEXT NOT NULL DEFAULT 'заявка'
        CHECK (enrollment_status IN ('заявка', 'активна', 'завершена', 'отменена')),
    final_grade REAL CHECK (final_grade BETWEEN 0 AND 100),
    UNIQUE (student_id, course_id),
    FOREIGN KEY (student_id) REFERENCES students(student_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (course_id) REFERENCES courses(course_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (group_id) REFERENCES study_groups(group_id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- 7. Оплаты
CREATE TABLE payments (
    payment_id INTEGER PRIMARY KEY AUTOINCREMENT,
    enrollment_id INTEGER NOT NULL,
    amount REAL NOT NULL CHECK (amount > 0),
    payment_date TEXT NOT NULL,
    payment_method TEXT NOT NULL CHECK (payment_method IN ('card', 'cash', 'transfer', 'sbp')),
    payment_status TEXT NOT NULL DEFAULT 'ожидает'
        CHECK (payment_status IN ('оплачено', 'ожидает', 'возврат')),
    FOREIGN KEY (enrollment_id) REFERENCES enrollments(enrollment_id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- 8. Домашние задания как банк заданий
CREATE TABLE homeworks (
    homework_id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    difficulty TEXT NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard')),
    max_score REAL NOT NULL CHECK (max_score > 0 AND max_score <= 100)
);

-- 9. Назначение задания на конкретное занятие
CREATE TABLE lesson_homeworks (
    lesson_id INTEGER NOT NULL,
    homework_id INTEGER NOT NULL,
    deadline TEXT NOT NULL,
    PRIMARY KEY (lesson_id, homework_id),
    FOREIGN KEY (lesson_id) REFERENCES lessons(lesson_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (homework_id) REFERENCES homeworks(homework_id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- 10. Сдачи домашних заданий.
-- Это слабая сущность: она не имеет собственного самостоятельного ID
-- и определяется студентом, занятием, заданием и номером попытки.
CREATE TABLE submissions (
    student_id INTEGER NOT NULL,
    lesson_id INTEGER NOT NULL,
    homework_id INTEGER NOT NULL,
    attempt_no INTEGER NOT NULL DEFAULT 1 CHECK (attempt_no > 0),
    submitted_at TEXT NOT NULL,
    score REAL NOT NULL CHECK (score BETWEEN 0 AND 100),
    feedback TEXT,
    PRIMARY KEY (student_id, lesson_id, homework_id, attempt_no),
    FOREIGN KEY (student_id) REFERENCES students(student_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (lesson_id, homework_id) REFERENCES lesson_homeworks(lesson_id, homework_id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- 11. Сертификаты. Связь 1:1 с записью на курс обеспечивается UNIQUE(enrollment_id)
CREATE TABLE certificates (
    certificate_id INTEGER PRIMARY KEY AUTOINCREMENT,
    enrollment_id INTEGER NOT NULL UNIQUE,
    certificate_number TEXT NOT NULL UNIQUE,
    issued_date TEXT NOT NULL,
    result_text TEXT NOT NULL,
    FOREIGN KEY (enrollment_id) REFERENCES enrollments(enrollment_id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- Дополнительное ограничение для оценки 9-10:
-- нельзя внести платеж больше стоимости курса по соответствующей записи.
CREATE TRIGGER trg_payment_not_above_course_price
BEFORE INSERT ON payments
BEGIN
    SELECT CASE
        WHEN NEW.amount > (
            SELECT c.price
            FROM enrollments e
            INNER JOIN courses c ON c.course_id = e.course_id
            WHERE e.enrollment_id = NEW.enrollment_id
        )
        THEN RAISE(ABORT, 'Сумма платежа превышает стоимость курса')
    END;
END;

-- Дополнительное автоматическое действие:
-- если сумма оплаченных платежей достигла стоимости курса, статус записи становится "активна".
CREATE TRIGGER trg_activate_enrollment_after_payment
AFTER INSERT ON payments
WHEN NEW.payment_status = 'оплачено'
BEGIN
    UPDATE enrollments
    SET enrollment_status = 'активна'
    WHERE enrollment_id = NEW.enrollment_id
      AND (
          SELECT SUM(p.amount)
          FROM payments p
          WHERE p.enrollment_id = NEW.enrollment_id
            AND p.payment_status = 'оплачено'
      ) >= (
          SELECT c.price
          FROM enrollments e
          INNER JOIN courses c ON c.course_id = e.course_id
          WHERE e.enrollment_id = NEW.enrollment_id
      );
END;

-- Дополнительный триггер: сертификат можно выдать только при итоговой оценке не ниже 60.
CREATE TRIGGER trg_certificate_min_grade
BEFORE INSERT ON certificates
BEGIN
    SELECT CASE
        WHEN (
            SELECT final_grade
            FROM enrollments
            WHERE enrollment_id = NEW.enrollment_id
        ) < 60
        THEN RAISE(ABORT, 'Сертификат нельзя выдать при оценке ниже 60')
    END;
END;

-- Заполнение таблицы students
INSERT INTO students (full_name, email, phone, registration_date, student_status) VALUES
('Мария Калинина', 'maria.k@mail.com', '+79990000001', '2026-01-10', 'active'),
('Анна Смирнова', 'anna.s@mail.com', '+79990000002', '2026-01-12', 'active'),
('Илья Петров', 'ilya.p@mail.com', '+79990000003', '2026-01-15', 'active'),
('Екатерина Волкова', 'katya.v@mail.com', '+79990000004', '2026-02-01', 'paused'),
('Никита Орлов', 'nikita.o@mail.com', '+79990000005', '2026-02-05', 'active'),
('София Лебедева', 'sofia.l@mail.com', '+79990000006', '2026-02-09', 'active');

-- Заполнение таблицы teachers
INSERT INTO teachers (full_name, email, specialization, hire_date) VALUES
('Ольга Романова', 'romanova@school.ru', 'SQL и базы данных', '2024-09-01'),
('Дмитрий Соколов', 'sokolov@school.ru', 'Python', '2024-10-15'),
('Анна Смирнова', 'anna.teacher@school.ru', 'Визуализация данных', '2025-01-20'),
('Павел Морозов', 'morozov@school.ru', 'Статистика', '2025-03-01'),
('Елена Козлова', 'kozlova@school.ru', 'Машинное обучение', '2025-05-12');

-- Заполнение таблицы courses
INSERT INTO courses (course_name, level, price, teacher_id, prerequisite_course_id) VALUES
('SQL для начинающих', 'beginner', 12000, 1, NULL),
('Python для анализа данных', 'beginner', 15000, 2, NULL),
('Визуализация данных', 'middle', 14000, 3, 2),
('Экономическая статистика', 'middle', 16000, 4, NULL),
('Аналитик данных Junior', 'advanced', 22000, 1, 1),
('Введение в машинное обучение', 'advanced', 25000, 5, 2);

-- Заполнение таблицы study_groups
INSERT INTO study_groups (group_name, course_id, start_date, max_students) VALUES
('SQL-101', 1, '2026-02-10', 20),
('PY-101', 2, '2026-02-12', 20),
('VIS-201', 3, '2026-03-01', 15),
('STAT-201', 4, '2026-03-05', 18),
('DA-301', 5, '2026-04-01', 12),
('ML-301', 6, '2026-04-07', 12);

-- Заполнение таблицы lessons
INSERT INTO lessons (course_id, group_id, lesson_number, topic, lesson_date) VALUES
(1, 1, 1, 'Основы SELECT и фильтрации', '2026-02-10'),
(1, 1, 2, 'JOIN и связи между таблицами', '2026-02-17'),
(2, 2, 1, 'Типы данных и функции Python', '2026-02-12'),
(2, 2, 2, 'Работа с таблицами в pandas', '2026-02-19'),
(3, 3, 1, 'Графики и выбор визуализации', '2026-03-01'),
(4, 4, 1, 'Описательная статистика', '2026-03-05'),
(5, 5, 1, 'Построение аналитического отчета', '2026-04-01'),
(6, 6, 1, 'Логика моделей машинного обучения', '2026-04-07');

-- Заполнение таблицы enrollments
INSERT INTO enrollments (student_id, course_id, group_id, enrollment_date, enrollment_status, final_grade) VALUES
(1, 1, 1, '2026-02-01', 'заявка', 92),
(2, 1, 1, '2026-02-02', 'заявка', 85),
(3, 2, 2, '2026-02-03', 'заявка', 78),
(4, 2, 2, '2026-02-03', 'заявка', 55),
(5, 3, 3, '2026-02-20', 'заявка', 91),
(6, 4, 4, '2026-02-25', 'заявка', 66),
(1, 5, 5, '2026-03-20', 'заявка', 88),
(2, 6, 6, '2026-03-25', 'заявка', 73);

-- Заполнение таблицы payments
INSERT INTO payments (enrollment_id, amount, payment_date, payment_method, payment_status) VALUES
(1, 12000, '2026-02-02', 'card', 'оплачено'),
(2, 12000, '2026-02-03', 'sbp', 'оплачено'),
(3, 15000, '2026-02-04', 'transfer', 'оплачено'),
(4, 7000, '2026-02-04', 'card', 'ожидает'),
(5, 14000, '2026-02-21', 'card', 'оплачено'),
(6, 16000, '2026-02-26', 'cash', 'оплачено'),
(7, 22000, '2026-03-21', 'transfer', 'оплачено'),
(8, 25000, '2026-03-26', 'sbp', 'оплачено');

-- Заполнение таблицы homeworks
INSERT INTO homeworks (title, difficulty, max_score) VALUES
('Фильтрация данных в SELECT', 'easy', 100),
('Практика INNER JOIN и LEFT JOIN', 'medium', 100),
('Мини-проект на Python', 'medium', 100),
('Построение графиков', 'easy', 100),
('Расчет описательных статистик', 'medium', 100),
('Аналитическая записка', 'hard', 100),
('Классификация наблюдений', 'hard', 100);

-- Заполнение таблицы lesson_homeworks
INSERT INTO lesson_homeworks (lesson_id, homework_id, deadline) VALUES
(1, 1, '2026-02-15'),
(2, 2, '2026-02-22'),
(3, 3, '2026-02-18'),
(5, 4, '2026-03-08'),
(6, 5, '2026-03-12'),
(7, 6, '2026-04-08'),
(8, 7, '2026-04-14');

-- Заполнение таблицы submissions
INSERT INTO submissions (student_id, lesson_id, homework_id, attempt_no, submitted_at, score, feedback) VALUES
(1, 1, 1, 1, '2026-02-14 18:30', 95, 'Отличная работа'),
(2, 1, 1, 1, '2026-02-15 10:10', 88, 'Хорошо'),
(1, 2, 2, 1, '2026-02-21 20:00', 91, 'Верно выполнены JOIN'),
(2, 2, 2, 1, '2026-02-22 19:40', 82, 'Есть мелкие ошибки'),
(3, 3, 3, 1, '2026-02-17 21:15', 79, 'Нужно улучшить оформление'),
(4, 3, 3, 1, '2026-02-18 22:00', 54, 'Слабая работа'),
(5, 5, 4, 1, '2026-03-07 17:00', 93, 'Хороший выбор графиков'),
(6, 6, 5, 1, '2026-03-11 16:30', 68, 'Базовые расчеты верны'),
(1, 7, 6, 1, '2026-04-07 19:00', 87, 'Сильная аналитика'),
(2, 8, 7, 1, '2026-04-13 18:50', 74, 'Нужно больше интерпретации');

-- Заполнение таблицы certificates
INSERT INTO certificates (enrollment_id, certificate_number, issued_date, result_text) VALUES
(1, 'CERT-SQL-001', '2026-03-01', 'Курс успешно завершен'),
(2, 'CERT-SQL-002', '2026-03-01', 'Курс успешно завершен'),
(3, 'CERT-PY-001', '2026-03-05', 'Курс успешно завершен'),
(5, 'CERT-VIS-001', '2026-03-20', 'Курс успешно завершен'),
(6, 'CERT-STAT-001', '2026-03-25', 'Курс успешно завершен');

-- Дополнительное изменение структуры таблицы для демонстрации ALTER
ALTER TABLE homeworks ADD COLUMN comment TEXT DEFAULT 'без комментария';

---------------------------------------------------------------------
-- SQL-запросы для изменения данных и получения отчетов
---------------------------------------------------------------------

-- 1. Список студентов, курсов, групп и преподавателей.
-- Используются SELECT, DISTINCT, INNER JOIN, ORDER BY.
SELECT DISTINCT
    s.full_name AS student,
    c.course_name AS course,
    g.group_name AS study_group,
    t.full_name AS teacher
FROM students s
INNER JOIN enrollments e ON e.student_id = s.student_id
INNER JOIN courses c ON c.course_id = e.course_id
INNER JOIN study_groups g ON g.group_id = e.group_id
INNER JOIN teachers t ON t.teacher_id = c.teacher_id
ORDER BY c.course_name, s.full_name;

-- 2. Количество студентов на каждом курсе.
-- Используются COUNT, GROUP BY, HAVING, ORDER BY.
SELECT
    c.course_name,
    COUNT(e.student_id) AS students_count
FROM courses c
LEFT JOIN enrollments e ON e.course_id = c.course_id
GROUP BY c.course_id, c.course_name
HAVING COUNT(e.student_id) >= 1
ORDER BY students_count DESC;

-- 3. Средняя, минимальная и максимальная итоговая оценка по курсам.
-- Используются AVG, MIN, MAX, GROUP BY.
SELECT
    c.course_name,
    ROUND(AVG(e.final_grade), 2) AS avg_grade,
    MIN(e.final_grade) AS min_grade,
    MAX(e.final_grade) AS max_grade
FROM courses c
INNER JOIN enrollments e ON e.course_id = c.course_id
GROUP BY c.course_id, c.course_name
ORDER BY avg_grade DESC;

-- 4. Выручка по курсам и текстовая классификация результата.
-- Используются SUM, CASE, LEFT JOIN, GROUP BY.
SELECT
    c.course_name,
    COALESCE(SUM(CASE WHEN p.payment_status = 'оплачено' THEN p.amount ELSE 0 END), 0) AS revenue,
    CASE
        WHEN COALESCE(SUM(CASE WHEN p.payment_status = 'оплачено' THEN p.amount ELSE 0 END), 0) >= 20000
            THEN 'высокая выручка'
        ELSE 'обычная выручка'
    END AS revenue_group
FROM courses c
LEFT JOIN enrollments e ON e.course_id = c.course_id
LEFT JOIN payments p ON p.enrollment_id = e.enrollment_id
GROUP BY c.course_id, c.course_name
ORDER BY revenue DESC;

-- 5. Платежи с текстовым пояснением через IF-аналог SQLite: IIF().
-- Используются IIF, INNER JOIN, ORDER BY.
SELECT
    s.full_name,
    c.course_name,
    p.amount,
    p.payment_status,
    IIF(p.payment_status = 'оплачено', 'доступ открыт', 'нужна проверка') AS access_status
FROM payments p
INNER JOIN enrollments e ON e.enrollment_id = p.enrollment_id
INNER JOIN students s ON s.student_id = e.student_id
INNER JOIN courses c ON c.course_id = e.course_id
ORDER BY p.payment_date;

-- 6. Курсы дороже средней стоимости всех курсов.
-- Вложенный запрос 1. Используются SELECT, WHERE, AVG, ORDER BY.
SELECT
    course_name,
    price
FROM courses
WHERE price > (
    SELECT AVG(price)
    FROM courses
)
ORDER BY price DESC;

-- 7. Студенты, чья оценка выше средней оценки по их курсу.
-- Вложенный запрос 2. Используются коррелированный подзапрос, AVG, INNER JOIN.
SELECT
    s.full_name,
    c.course_name,
    e.final_grade
FROM enrollments e
INNER JOIN students s ON s.student_id = e.student_id
INNER JOIN courses c ON c.course_id = e.course_id
WHERE e.final_grade > (
    SELECT AVG(e2.final_grade)
    FROM enrollments e2
    WHERE e2.course_id = e.course_id
)
ORDER BY e.final_grade DESC;

-- 8. Студенты, которые получили сертификат.
-- Вложенный запрос 3. Используются IN, SELECT, ORDER BY.
SELECT
    full_name,
    email
FROM students
WHERE student_id IN (
    SELECT e.student_id
    FROM enrollments e
    WHERE e.enrollment_id IN (
        SELECT enrollment_id
        FROM certificates
    )
)
ORDER BY full_name;

-- 9. Курсы, по которым нет выданных сертификатов.
-- Вложенный запрос 4. Используются NOT IN, SELECT.
SELECT
    course_name
FROM courses
WHERE course_id NOT IN (
    SELECT e.course_id
    FROM enrollments e
    WHERE e.enrollment_id IN (
        SELECT enrollment_id
        FROM certificates
    )
);

-- 10. Список имен студентов и преподавателей без повторов.
-- Используется UNION.
SELECT full_name FROM students
UNION
SELECT full_name FROM teachers
ORDER BY full_name;

-- 11. Имена, которые встречаются и среди студентов, и среди преподавателей.
-- Используется INTERSECT.
SELECT full_name FROM students
INTERSECT
SELECT full_name FROM teachers;

-- 12. Аналог MINUS в SQLite: студенты, которых нет среди преподавателей.
-- В SQLite вместо MINUS используется оператор EXCEPT.
SELECT full_name FROM students
EXCEPT
SELECT full_name FROM teachers
ORDER BY full_name;

-- 13. NATURAL JOIN для курсов и преподавателей по общему полю teacher_id.
-- Используется NATURAL JOIN.
SELECT
    course_name,
    full_name AS teacher,
    specialization
FROM courses
NATURAL JOIN teachers
ORDER BY course_name;

-- 14. Обновление статуса ожидающего платежа.
-- Используется UPDATE с вложенным SELECT.
UPDATE payments
SET payment_status = 'оплачено'
WHERE payment_id = (
    SELECT payment_id
    FROM payments
    WHERE payment_status = 'ожидает'
    ORDER BY payment_date
    LIMIT 1
);

-- 15. Студенты, у которых хотя бы одна работа выше средней оценки за все сдачи.
-- Вложенный запрос 5. Используются IN, AVG, DISTINCT.
SELECT DISTINCT
    s.full_name
FROM students s
WHERE s.student_id IN (
    SELECT sub.student_id
    FROM submissions sub
    WHERE sub.score > (
        SELECT AVG(score)
        FROM submissions
    )
)
ORDER BY s.full_name;

-- 16. Группы с максимальным количеством записанных студентов.
-- Вложенный запрос 6. Используются COUNT, GROUP BY, HAVING.
SELECT
    g.group_name,
    COUNT(e.student_id) AS students_count
FROM study_groups g
LEFT JOIN enrollments e ON e.group_id = g.group_id
GROUP BY g.group_id, g.group_name
HAVING COUNT(e.student_id) = (
    SELECT MAX(group_size)
    FROM (
        SELECT COUNT(*) AS group_size
        FROM enrollments
        GROUP BY group_id
    )
);

---------------------------------------------------------------------
-- Оконные функции
---------------------------------------------------------------------

-- 17. Рейтинг студентов внутри каждого курса по итоговой оценке.
SELECT
    c.course_name,
    s.full_name,
    e.final_grade,
    RANK() OVER (PARTITION BY c.course_id ORDER BY e.final_grade DESC) AS rank_in_course
FROM enrollments e
INNER JOIN students s ON s.student_id = e.student_id
INNER JOIN courses c ON c.course_id = e.course_id
ORDER BY c.course_name, rank_in_course;

-- 18. Накопительная выручка по датам платежей.
SELECT
    payment_id,
    payment_date,
    amount,
    SUM(amount) OVER (ORDER BY payment_date, payment_id) AS running_revenue
FROM payments
WHERE payment_status = 'оплачено'
ORDER BY payment_date, payment_id;

-- 19. Средняя оценка по курсу без сворачивания строк.
SELECT
    c.course_name,
    s.full_name,
    e.final_grade,
    ROUND(AVG(e.final_grade) OVER (PARTITION BY c.course_id), 2) AS avg_grade_in_course
FROM enrollments e
INNER JOIN students s ON s.student_id = e.student_id
INNER JOIN courses c ON c.course_id = e.course_id
ORDER BY c.course_name, e.final_grade DESC;

---------------------------------------------------------------------
-- CTE для оценки 9-10
---------------------------------------------------------------------

-- 20. CTE: курсы, где средняя оценка выше общей средней оценки по платформе.
WITH course_avg AS (
    SELECT
        course_id,
        AVG(final_grade) AS avg_grade
    FROM enrollments
    GROUP BY course_id
), global_avg AS (
    SELECT AVG(final_grade) AS platform_avg
    FROM enrollments
)
SELECT
    c.course_name,
    ROUND(ca.avg_grade, 2) AS avg_grade,
    ROUND(ga.platform_avg, 2) AS platform_avg
FROM course_avg ca
INNER JOIN courses c ON c.course_id = ca.course_id
CROSS JOIN global_avg ga
WHERE ca.avg_grade > ga.platform_avg
ORDER BY ca.avg_grade DESC;
