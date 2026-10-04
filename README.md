# Online School Database — SQL Project

A relational database designed for an online education platform using SQLite.

The project models the main processes of an online school: student enrollment, courses, study groups, lessons, homework assignments, submissions, payments, grades, and certificates.

## Project Overview

The goal of the project was to design a structured relational database and implement SQL queries for educational and business analytics.

The database includes 11 interconnected tables and supports reporting on student performance, course popularity, payments, revenue, and learning progress.

## Database Structure

The database contains the following main entities:

- Students and teachers
- Courses and study groups
- Lessons and homework assignments
- Student enrollments
- Homework submissions
- Payments
- Certificates

The database implements:

- 1:1 relationships
- 1:N relationships
- M:N relationships
- Recursive relationships
- Ternary relationships
- Weak entities

The schema is normalized up to Fourth Normal Form (4NF).

## SQL Features

The project demonstrates the use of:

- `INNER JOIN`, `LEFT JOIN`, `NATURAL JOIN`
- `GROUP BY` and `HAVING`
- Aggregate functions: `COUNT`, `AVG`, `MIN`, `MAX`, `SUM`
- Nested and correlated subqueries
- `UNION`, `INTERSECT`, `EXCEPT`
- Common Table Expressions (CTE)
- Window functions: `RANK()`, `SUM() OVER`, `AVG() OVER`
- `CASE` expressions
- Triggers
- Primary and foreign keys
- `CHECK`, `UNIQUE`, and `NOT NULL` constraints
- Cascading `ON DELETE` and `ON UPDATE` actions

## Analytical Queries

The project contains 20 SQL queries for data analysis and reporting, including:

- course popularity analysis
- average, minimum, and maximum grades by course
- course revenue analysis
- students performing above their course average
- student ranking within courses
- cumulative revenue analysis
- course performance comparison using CTEs

## Business Logic

Several triggers automate database logic:

- preventing payments above the course price
- automatically activating enrollment after full payment
- preventing certificate issuance when the final grade is below 60

## Technologies

- SQL
- SQLite
- Relational Database Design
- ER Modeling

## Author

Mari Kalandia  
HSE University — Economics and Statistics
