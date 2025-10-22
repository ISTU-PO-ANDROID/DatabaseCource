-- функция без параметров
CREATE FUNCTION hello_world() -- имя и пустой список параметров
RETURNS text -- тип возвращаемого значения
AS $$ SELECT 'Hello, world!'; $$ -- тело
LANGUAGE sql;

-- вызов в контексте выражения
select hello_world();

-- кавычки доллары, чтобы не экранировать обычные кавычек
SELECT ' SELECT ''Hello, world!''; ';

SELECT $$ SELECT 'Hello, world!'; $$;

-- кавычки доллары,могут быть вложенными, добавляется произвольный текст
SELECT $func$ SELECT $$Hello, world!$$; $func$;

--тело функции хранится в системном каталоге
SELECT proname, prosrc, prosqlbody FROM pg_proc
WHERE proname = 'hello_world'

-- в стиле стандарта SQL
CREATE OR REPLACE FUNCTION hello_world() RETURNS text
LANGUAGE sql
RETURN 'Hello, world!';

--тело функции сохранено по-другому
--при вызове функции ее команды заново не интерпретируются, а используется заранее разобранный вариант
SELECT proname, prosrc, left(prosqlbody, 100) AS body 
FROM pg_proc 
WHERE proname = 'hello_world'

-- Исходный код в этом случае не хранится, получить его можно функциями
SELECT 
    p.proname as function_name,
    pg_get_function_arguments(p.oid) as arguments,
    pg_get_function_result(p.oid) as return_type,
    pg_get_functiondef(p.oid) as function_definition
FROM pg_proc p
WHERE p.proname = 'hello_world'

--в качестве результата возвращается первая строка, которую вернул последний оператор
CREATE OR REPLACE FUNCTION hello_world() RETURNS text
LANGUAGE sql
BEGIN ATOMIC
	SELECT 'First Line';
	SELECT status from flights;
END;

SELECT hello_world();

--В SQL функциях запрещены:
--команды управления транзакциями (BEGIN, COMMIT, ROLLBACK и т. п.);
--служебные команды (такие, как VACUUM или CREATE INDEX).

-- ERROR: COMMIT is not yet supported in unquoted SQL function body
CREATE FUNCTION do_commit() RETURNS void
LANGUAGE sql
BEGIN ATOMIC COMMIT; END;


-- функции с входными параметрами
CREATE FUNCTION hello(name text) -- формальный параметр
RETURNS text
LANGUAGE sql
RETURN 'Hello, ' || name || '!';


SELECT hello('Alice');

-- достаточно указать тип параметра
DROP FUNCTION hello(text); 

--параметр функции без имени
CREATE FUNCTION hello(text)
RETURNS text
LANGUAGE sql
RETURN 'Hello, ' || $1 || '!'; -- номер вместо имени

SELECT hello('Alice');

DROP FUNCTION hello(text); 

--необязательное ключевое слово IN, обознает входной параметр
-- DEFAULT позволяет определить значение по умолчанию для параметра
--параметры со значениями по умолчанию должны идти в конце всего списка
CREATE FUNCTION hello(
	IN name text, 
	IN greet text DEFAULT 'Dear', 
	IN title text DEFAULT 'Mr')
RETURNS text
LANGUAGE sql
RETURN 'Hello, ' || greet || ' ' || title || ' ' || name || '!';

SELECT hello('Alice', 'Charming', 'Mrs');

SELECT hello('Bob', 'Excellent');

SELECT hello('Bob');


--если формальным параметрам даны имена, можно использовать их при указании фактических параметров
SELECT hello(title => 'Mrs', name => 'Alice');

--Можно совмещать оба способа: часть параметров (начиная с первого) указать позиционно, а оставшиеся — по имени
SELECT hello('Alice', title => 'Mrs');


DROP FUNCTION hello(text, text, text);

--Если функция должна возвращать неопределенное значение, когда хотя бы один из входных параметров не определен, ее
--можно объявить как строгую (STRICT). Тело функции при этом вообще не будет выполняться.
CREATE FUNCTION hello(IN name text, IN title text DEFAULT 'Mr')
RETURNS text
LANGUAGE sql STRICT
RETURN 'Hello, ' || title || ' ' || name || '!';


SELECT hello('Alice', NULL);

DROP FUNCTION hello(text, text);


--Функции с выходными параметрами
CREATE FUNCTION hello(
	IN name text,
	OUT text -- имя можно не указывать, если оно не нужно
)
AS $$
SELECT 'Hello, ' || name || '!';
$$ LANGUAGE sql;

--возвращает строку
SELECT hello('Alice');

DROP FUNCTION hello(text); -- OUT-параметры не указываем

--Можно использовать и RETURNS, и OUT-параметр вместе 
CREATE FUNCTION hello(IN name text, OUT text)
RETURNS text AS $$
SELECT 'Hello, ' || name || '!';
$$ LANGUAGE sql;

--результат снова будет тем же:
SELECT hello('Alice');

DROP FUNCTION hello(text);

--Или даже так, использовав INOUT-параметр:
CREATE FUNCTION hello(INOUT name text)
AS $$
SELECT 'Hello, ' || name || '!';
$$ LANGUAGE sql;

SELECT hello('Alice');

DROP FUNCTION hello(text);

--в RETURNS можно указать только одно значение, 
--выходных параметров может быть несколько.
CREATE FUNCTION hello(
	IN name text,
	OUT greeting text,
	OUT clock timetz)
AS $$
SELECT 'Hello, ' || name || '!', current_time;
$$ LANGUAGE sql;

--функция вернула не одно значение, а сразу несколько.
SELECT hello('Alice');


--Категории изменчивости и изоляция
--1. Функции с изменчивостью volatile на уровне изоляции Read Committed 
--приводят к рассогласованию данных внутри ОДНОГО запроса.
CREATE TABLE t(n integer);

--Сделаем функцию, возвращающую число строк в таблице
CREATE FUNCTION cnt() RETURNS bigint
AS $$
SELECT count(*) FROM t;
$$ VOLATILE LANGUAGE sql;

--вызовем ее несколько раз с задержкой
BEGIN ISOLATION LEVEL READ COMMITTED;

SELECT (SELECT count(*) FROM t), cnt(), pg_sleep(1)
FROM generate_series(1,4);

-- результаты Select и функции отличаются
-- count | cnt | pg_sleep
-- -------+-----+----------
--		0 | 0 |
-- 		0 | 0 |
-- 		0 | 1 |
-- 		0 | 1 |

--в параллельном сеансе вставим в таблицу строку
INSERT INTO t VALUES (1);

rollback;

select * from t

TRUNCATE t;

--При изменчивости stable или immutable, 
--либо использовании более строгих уровней изоляции, такого не происходит
ALTER FUNCTION cnt() STABLE;

--снова вызовем ее несколько раз с задержкой
--теперь колонки count и cnt содержат 0
BEGIN ISOLATION LEVEL READ COMMITTED;

SELECT (SELECT count(*) FROM t), cnt(), pg_sleep(1)
FROM generate_series(1,4);

rollback;

--также в параллельном сеансе вставим в таблицу строку
INSERT INTO t VALUES (1);


--2. Функции с изменчивостью volatile видят все изменения, 
--в том числе сделанные ТЕКУЩИМ, еще не завершенным оператором SQL
ALTER FUNCTION cnt() VOLATILE;

TRUNCATE t;

--вствляем значение функции равное текущему количеству записей
INSERT INTO t SELECT cnt() FROM generate_series(1,5);

-- значения увеличиваются
-- Это верно для любых уровней изоляции
select * from t

--Функции с изменчивостью stable или immutable видят изменения только уже завершенных операторов
ALTER FUNCTION cnt() STABLE;

TRUNCATE t;

--снова выполняем вставку
INSERT INTO t SELECT cnt() FROM generate_series(1,5);

-- значения не увеличиваются, все заполнено 0
select * from t


--Категории изменчивости и оптимизация
--Благодаря дополнительной информации о поведении функции, которую дает указание категории изменчивости,
--оптимизатор может сэкономить на вызовах функции.

--создадим функцию, возвращающую случайное число
CREATE FUNCTION rnd() RETURNS float
AS $$
	SELECT random();
$$ VOLATILE LANGUAGE sql;


--В плане мы видим «честное» обращение к функции generate_series; каждая строка результата сравнивается со
--случайным числом и при необходимости отбрасывается фильтром
-- В некоторых, очень простых, случаях тело функции на языке SQL может быть подставлено прямо в основной SQLоператор на этапе разбора запроса. 
-- В этом случае время на вызов функции не тратится.
-- в плане видим функцию random(), вместо обертки rnd()
--Function Scan on generate_series
--Filter: (random() > '0.5'::double precision)
EXPLAIN (costs off)
SELECT * FROM generate_series(1,10) WHERE rnd() > 0.5;



--ожидаем в среднем получить 5 строк
SELECT * FROM generate_series(1,10) WHERE rnd() > 0.5;


--Функция с изменчивостью stable будет вызвана всего один раз — поскольку мы фактически указали, что ее
--значение не может измениться в пределах оператора
ALTER FUNCTION rnd() STABLE;

--One-Time Filter: (rnd() > '0.5'::double precision)
-- -> Function Scan on generate_series
EXPLAIN (costs off)
SELECT * FROM generate_series(1,10) WHERE rnd() > 0.5;

--с вероятностью 0,5 будем получать 0 или 10 строк
SELECT * FROM generate_series(1,10) WHERE rnd() > 0.5;


ALTER FUNCTION rnd() IMMUTABLE;

--immutable позволяет вычислить функции еще на этапе планирования, поэтому во время
--выполнения никакие фильтры не нужны
--Function Scan on generate_series
EXPLAIN (costs off)
SELECT * FROM generate_series(1,10) WHERE rnd() > 0.5;

--с вероятностью 0,5 будем получать 0 или 10 строк
SELECT * FROM generate_series(1,10) WHERE rnd() > 0.5;

drop function rnd
