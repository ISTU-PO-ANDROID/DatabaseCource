--Создадим «универсальную» триггерную функцию, которая описывает контекст, в котором она вызвана
drop function describe;
CREATE OR REPLACE FUNCTION describe() RETURNS trigger
AS $$
DECLARE
rec record;
str text := '';
BEGIN
	IF TG_LEVEL = 'ROW' THEN
		CASE TG_OP
			WHEN 'DELETE' THEN rec := OLD; str := OLD::text;
			WHEN 'UPDATE' THEN rec := NEW; str := OLD || ' -> ' || NEW;
			WHEN 'INSERT' THEN rec := NEW; str := NEW::text;
		END CASE;
	END IF;
	RAISE NOTICE '% % % %: %',
		TG_TABLE_NAME, TG_WHEN, TG_OP, TG_LEVEL, str;
	RETURN rec;
END;
$$ LANGUAGE plpgsql;

drop table t;

CREATE TABLE t(
	id integer PRIMARY KEY,
	s text
);

--Триггеры на уровне оператора, до
CREATE TRIGGER t_before_stmt
	BEFORE INSERT OR UPDATE OR DELETE -- события
	ON t 								-- таблица
	FOR EACH STATEMENT 					-- уровень
	EXECUTE FUNCTION describe(); 		-- триггерная функция

--Триггеры на уровне оператора, после
CREATE TRIGGER t_after_stmt
	AFTER INSERT OR UPDATE OR DELETE ON t
	FOR EACH STATEMENT EXECUTE FUNCTION describe();

--на уровне строк, до
CREATE TRIGGER t_before_row
	BEFORE INSERT OR UPDATE OR DELETE ON t
	FOR EACH ROW EXECUTE FUNCTION describe();

--на уровне строк, после
CREATE TRIGGER t_after_row
	AFTER INSERT OR UPDATE OR DELETE ON t
	FOR EACH ROW EXECUTE FUNCTION describe();

--Пробуем вставку
INSERT INTO t VALUES (1,'aaa');

--транзакция прерывается
INSERT INTO t VALUES (1,'aaa'), (2, 'bbb');

select * from t;

--на truncate нет триггеров
truncate table t;

--вставка нескольких записей
INSERT INTO t VALUES (1,'aaa'), (2, 'bbb');

--изменение
UPDATE t SET s = 'ссс' where id=1;

--Триггеры на уровне оператора сработают даже если команда не обработала ни одной строки
UPDATE t SET s = 'ccc' where id = 0;

select * from t;

--оператор INSERT с предложением ON CONFLICT приводит к тому, что 
--срабатывают BEFORE триггеры и на вставку, и на обновление
INSERT INTO t VALUES (1,'ddd'), (3,'eee')
ON CONFLICT(id) DO UPDATE SET s = EXCLUDED.s;

select * from t;

--удаление
DELETE FROM t WHERE id=2;

--триггерная функция, показывающая содержимое переходных таблиц
--используем имена old_table и new_table, которые будут объявлены при создании триггера
drop function transition;

CREATE OR REPLACE FUNCTION transition() RETURNS trigger
AS $$
DECLARE
rec record;
BEGIN
	IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN
		RAISE NOTICE 'Старое состояние:';
		FOR rec IN SELECT * FROM old_table LOOP
			RAISE NOTICE '%', rec;
		END LOOP;
	END IF;
	IF TG_OP = 'UPDATE' OR TG_OP = 'INSERT' THEN
		RAISE NOTICE 'Новое состояние:';
		FOR rec IN SELECT * FROM new_table LOOP
			RAISE NOTICE '%', rec;
		END LOOP;
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

drop table trans;

CREATE TABLE trans(
	id integer PRIMARY KEY,
	n integer
);

INSERT INTO trans VALUES (1,10), (2,20), (3,30);

select * from trans;

--Чтобы при выполнении операции создавались переходные таблицы, 
--необходимо указать их имена при создании триггера:
CREATE TRIGGER t_after_upd_trans
AFTER UPDATE ON trans
REFERENCING
	OLD TABLE AS old_table
	NEW TABLE AS new_table -- можно и одну, не обязательно обе
FOR EACH STATEMENT
EXECUTE FUNCTION transition();


--Проверим
UPDATE trans SET n = n + 1 WHERE n <= 20;

select * from trans;


--Пример: сохранение истории изменения строк
drop table coins;
drop table coins_history;

CREATE TABLE coins(
	face_value numeric,
	name text
)


-- создаем клон основной таблицы
CREATE TABLE coins_history(LIKE coins);

--добавляем столбцы «действительно с» и «действительно по»
ALTER TABLE coins_history
	ADD start_date timestamp,
	ADD end_date timestamp;

--триггерная функция будет вставлять новую историческую строку с открытым интервалом действия
drop function history_insert;
CREATE OR REPLACE FUNCTION history_insert() RETURNS trigger
AS $$
BEGIN
	EXECUTE format(
		'INSERT INTO %I SELECT ($1).*, current_timestamp, NULL',
			TG_TABLE_NAME||'_history'
			) USING NEW;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;



--другая функция будет закрывать интервал действия исторической строки:
drop function history_delete;
CREATE OR REPLACE FUNCTION history_delete() RETURNS trigger
AS $$
BEGIN
	EXECUTE format(
		'UPDATE %I SET end_date = current_timestamp WHERE face_value = $1 AND end_date IS NULL',
		TG_TABLE_NAME||'_history'
		) USING OLD.face_value;
	RETURN OLD;
END;
$$ LANGUAGE plpgsql;


-- Важные моменты:
-- Обновление трактуется как удаление и затем вставка; здесь важен порядок, в котором сработают триггеры (по алфавиту).
-- Current_timestamp возвращает время начала транзакции, поэтому при обновлении start_date одной строки будет равен end_date другой.
-- Использование AFTER-триггеров позволяет избежать проблем с INSERT ... ON CONFLICT и потенциальными
-- конфликтами с другими триггерами, которые могут существовать на основной таблице.
CREATE TRIGGER coins_history_insert
	AFTER INSERT OR UPDATE ON coins
	FOR EACH ROW EXECUTE FUNCTION history_insert();


CREATE TRIGGER coins_history_delete
	AFTER UPDATE OR DELETE ON coins
	FOR EACH ROW EXECUTE FUNCTION history_delete();

--Проверим работу триггеров.
INSERT INTO coins VALUES (0.25, 'Полушка'), (3, 'Алтын');

UPDATE coins SET name = '3 копейки' WHERE face_value = 3;

INSERT INTO coins VALUES (5, '5 копеек');

DELETE FROM coins WHERE face_value = 0.25;

SELECT * FROM coins;

--В исторической таблице хранится вся история изменений
SELECT * FROM coins_history ORDER BY face_value, start_date;

--можно восстановить состояние на любой момент времени
SELECT face_value, name
	FROM coins_history
	WHERE start_date <= '2025-10-29 11:14:12.061182'::timestamptz 
	  AND (end_date IS NULL OR '2025-10-29 11:14:12.061182'::timestamptz < end_date)
	ORDER BY face_value;

--или так
WITH vars AS (
  SELECT '2025-10-29 11:14:13'::timestamptz AS d
)
	SELECT face_value, name
	FROM coins_history, vars
	WHERE start_date <= vars.d AND (end_date IS NULL OR vars.d < end_date)
	ORDER BY face_value;	


--Пример, обновляемое представление.
--имеются две таблицы: аэропорты и рейсы:
drop table airports1;
drop table flights1;

CREATE TABLE airports1(
	code char(3) PRIMARY KEY,
	name text NOT NULL
);

INSERT INTO airports1 VALUES
	('SVO', 'Москва. Шереметьево'),
	('LED', 'Санкт-Петербург. Пулково'),
	('TOF', 'Томск. Богашево');

CREATE TABLE flights1(
	id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
	airport_from char(3) NOT NULL REFERENCES airports1(code),
	airport_to char(3) NOT NULL REFERENCES airports1(code),
	UNIQUE (airport_from, airport_to)
);

INSERT INTO flights1 (airport_from, airport_to) VALUES
	('SVO','LED');

--Для удобства можно определить представление:
drop view flights_v1;
CREATE VIEW flights_v1 AS
	SELECT id,
	(SELECT name
	FROM airports1
	WHERE code = airport_from) airport_from,
	(SELECT name
	FROM airports1
	WHERE code = airport_to) airport_to
	FROM flights1;


SELECT * FROM flights_v1;

--такое представление не допускает изменений. 
--Например, не получится изменить пункт назначения таким образом:
UPDATE flights_v1
	SET airport_to = 'Томск. Богашево'
	WHERE id = 1;
	
	
--можем определить триггер. 
--для краткости обрабатываем только аэропорт назначения
drop function flights_v_update cascade;

CREATE OR REPLACE FUNCTION flights_v_update() RETURNS trigger
AS $$
DECLARE
	code_to char(3);
BEGIN
	BEGIN
		SELECT code INTO STRICT code_to
		FROM airports1
		WHERE name = NEW.airport_to;
	EXCEPTION
		WHEN no_data_found THEN
			RAISE EXCEPTION 'Аэропорт % отсутствует', NEW.airport_to;
	END;
	UPDATE flights1
		SET airport_to = code_to
		WHERE id = OLD.id; -- изменение id игнорируем
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--триггер INSTEAD OF на представление
CREATE TRIGGER flights_v_upd_trigger
	INSTEAD OF UPDATE ON flights_v1
	FOR EACH ROW EXECUTE FUNCTION flights_v_update();


--Проверим:
UPDATE flights_v1
	SET airport_to = 'Томск. Богашево'
	WHERE id = 1;


SELECT * FROM flights_v1;
SELECT * FROM flights1;


--Попытка изменить аэропорт на отсутствующий в таблице:
UPDATE flights_v1
	SET airport_to = 'Южно-Сахалинск. Хомутово'
	WHERE id = 1;



--Пример триггера для события ddl_command_end, которое соответствует завершению DDL-операции.
--Создадим функцию, которая описывает контекст вызова:
CREATE OR REPLACE FUNCTION describe_ddl() RETURNS event_trigger
AS $$
DECLARE
	r record;
BEGIN
	-- Для события ddl_command_end контекст вызова в специальной функции
	--Создание таблицы может может привести к выполнению нескольких команд DDL, поэтому функция
	--pg_event_trigger_ddl_commands возвращает множество строк
	FOR r IN SELECT * FROM pg_event_trigger_ddl_commands()
	LOOP
		RAISE NOTICE '%. тип: %, OID: %, имя: % ',
			r.command_tag, r.object_type, r.objid, r.object_identity;
	END LOOP;
	-- Функции триггера событий не нужно возвращать значение
END;
$$ LANGUAGE plpgsql;



--Сам триггер:
CREATE EVENT TRIGGER after_ddl
	ON ddl_command_end EXECUTE FUNCTION describe_ddl();

--Создаем новую таблицу
CREATE TABLE t1(id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY);

-- Посмотреть последовательности
SELECT 
    schemaname,
    sequencename,
    data_type,
    start_value,
    min_value,
    max_value,
    increment_by,
    cycle,
    last_value
FROM pg_sequences
WHERE sequencename = 't1_id_seq';

-- Посмотреть индексы таблицы
SELECT indexname, indexdef FROM pg_indexes 
WHERE tablename = 't1';

-- Триггер для отслеживания удаления объектов
CREATE OR REPLACE FUNCTION describe_drop() RETURNS event_trigger
AS $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT * FROM pg_event_trigger_dropped_objects()
    LOOP
        RAISE NOTICE 'УДАЛЕНИЕ: тип: %, OID: %, имя: %, оригинальное: %',
            r.object_type, r.object_identity, r.original, r.normal;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER after_drop
    ON sql_drop EXECUTE FUNCTION describe_drop();
	

drop table t1;





