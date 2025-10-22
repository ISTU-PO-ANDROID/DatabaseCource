--Процедуры без параметров

drop table t

CREATE TABLE t(a float);

CREATE PROCEDURE fill()
AS $$
	TRUNCATE t;
	INSERT INTO t SELECT random() FROM generate_series(1,3);
$$ LANGUAGE sql;

--вызов call
CALL fill();

SELECT * FROM t;

-- аналогично можно сделать через функию
CREATE FUNCTION fill_avg() RETURNS float
AS $$
	TRUNCATE t;
	INSERT INTO t SELECT random() FROM generate_series(1,3);
	SELECT avg(a) FROM t;
$$ LANGUAGE sql;

-- но вызов в контексте выражения
SELECT fill_avg();

--функции не могут управлять транзакциями. 
--Но и в процедурах на языке SQL это не поддерживается (поддерживается при использовании других языков)

DROP PROCEDURE fill();

-- процедура с параметром
CREATE PROCEDURE fill(nrows integer)
AS $$
	TRUNCATE t;
	INSERT INTO t SELECT random() FROM generate_series(1,nrows);
$$ LANGUAGE sql;


--при вызове процедур фактические параметры можно передавать позиционным способом или по имени:
CALL fill(nrows => 5);

SELECT * FROM t;

DROP PROCEDURE fill(integer);

--Процедуры могут также иметь INOUT-параметры, позволяющие возвращать значение. OUT-параметры пока не
--поддерживаются (но будут в PostgreSQL 14)
CREATE PROCEDURE fill(IN nrows integer, INOUT average float)
AS $$
	TRUNCATE t;
	INSERT INTO t SELECT random() FROM generate_series(1,nrows);
	SELECT avg(a) FROM t; -- как в функции
$$ LANGUAGE sql;

--входное значение не используется
CALL fill(5, NULL);

DROP PROCEDURE fill(integer, float);

SELECT version();

--Перегруженные подпрограммы
CREATE FUNCTION maximum(a integer, b integer) RETURNS integer
AS $$
	SELECT CASE WHEN a > b THEN a ELSE b END;
$$ LANGUAGE sql;


SELECT maximum(10, 20);

--аналогичную функцию для трех чисел. 
--Благодаря перегрузке, не надо придумывать для нее какое-то новое название
CREATE FUNCTION maximum(a integer, b integer, c integer)
RETURNS integer
AS $$
	SELECT CASE
	WHEN a > b THEN maximum(a,c)
	ELSE maximum(b,c)
END;
$$ LANGUAGE sql;

--Теперь у нас две функции с одним именем, но разным числом параметров
SELECT 
    p.proname as function_name,
    pg_get_function_arguments(p.oid) as arguments,
    pg_get_function_result(p.oid) as return_type,
    pg_get_functiondef(p.oid) as function_definition
FROM pg_proc p
WHERE p.proname = 'maximum'

--обе работают
SELECT maximum(10, 20), maximum(10, 20, 30);

--Команда CREATE OR REPLACE позволяет создать подпрограмму или заменить существующую, не удаляя ее.
--Поскольку в данном случае функция с такой сигнатурой уже существует, она будет заменена
CREATE OR REPLACE FUNCTION maximum(a integer, b integer, c integer)
RETURNS integer
AS $$
	SELECT CASE
	WHEN a > b THEN
	CASE WHEN a > c THEN a ELSE c END
	ELSE
	CASE WHEN b > c THEN b ELSE c END
	END;
$$ LANGUAGE sql;

--функций все еще две
SELECT 
    p.proname as function_name,
    pg_get_function_arguments(p.oid) as arguments,
    pg_get_function_result(p.oid) as return_type,
    pg_get_functiondef(p.oid) as function_definition
FROM pg_proc p
WHERE p.proname = 'maximum'



--Пусть наша функция работает не только для целых чисел, но и для вещественных.
--Как этого добиться? Можно было бы определить еще такую функцию
CREATE FUNCTION maximum(a real, b real) RETURNS real
AS $$
	SELECT CASE WHEN a > b THEN a ELSE b END;
$$ LANGUAGE sql;

--а теперь три
SELECT 
    p.proname as function_name,
    pg_get_function_arguments(p.oid) as arguments,
    pg_get_function_result(p.oid) as return_type,
    pg_get_functiondef(p.oid) as function_definition
FROM pg_proc p
WHERE p.proname = 'maximum'

--Две из них имеют одинаковое количество параметров, но отличаются их типами
SELECT maximum(10, 20), maximum(1.1, 2.2);

--Но дальше нам придется определить функции и для всех остальных типов данных, при том, что тело функции не
--меняется. И затем придется повторить все то же самое для варианта с тремя параметрами

--Полиморфные функции
DROP FUNCTION maximum(integer, integer);
DROP FUNCTION maximum(integer, integer, integer);
DROP FUNCTION maximum(real, real);

--полиморфный тип anyelement
--Такая функция должна принимать любой тип данных 
--а работать будет с любым типом, для которого определен оператор «больше»
CREATE FUNCTION maximum(a anyelement, b anyelement)
RETURNS anyelement
AS $$
	SELECT CASE WHEN a > b THEN a ELSE b END;
$$ LANGUAGE sql;

--В данном случае строковые литералы могут быть типа char, varchar, text 
--конкретный тип нам неизвестен. 
SELECT maximum('A', 'B');

--можно применить явное приведение типов
SELECT maximum('A'::text, 'B'::text);

--другой пример
SELECT maximum(now(), now() + interval '1 day');


--Важно, чтобы типы обоих параметров совпадали, иначе будет ошибка:
SELECT maximum(1, 'A');


CREATE FUNCTION maximum(
a anyelement,
b anyelement,
c anyelement DEFAULT NULL
) RETURNS anyelement
AS $$
	SELECT CASE
		WHEN c IS NULL THEN
		x
		ELSE
		CASE WHEN x > c THEN x ELSE c END
		END
	FROM (
		SELECT CASE WHEN a > b THEN a ELSE b END
	) max2(x);
$$ LANGUAGE sql;

SELECT maximum(10, 20, 30);

--А так произошел конфликт перегруженных функций
SELECT maximum(10, 20);

--Невозможно понять, имеем ли мы в виду функцию с двумя параметрами, 
--или с тремя (но просто не указали последний)
SELECT 
    p.proname as function_name,
    pg_get_function_arguments(p.oid) as arguments,
    pg_get_function_result(p.oid) as return_type,
    pg_get_functiondef(p.oid) as function_definition
FROM pg_proc p
WHERE p.proname = 'maximum'


--удалим первую функцию за ненадобностью.
DROP FUNCTION maximum(anyelement, anyelement);

--теперь работает
SELECT maximum(10, 20), maximum(10, 20, 30);