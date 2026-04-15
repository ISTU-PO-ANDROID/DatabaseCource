-- 2 transaction
-- Read Committed и грязное чтение

BEGIN;
SELECT * FROM lights ORDER BY id;

ROLLBACK;

-- Read Committed и чтение зафиксированных изменений
BEGIN;
SELECT * FROM lights ORDER BY id;

COMMIT;

--Можно ли увидеть изменения, зафиксированные в процессе выполнения одного оператора?
UPDATE lights SET state = 'on';
UPDATE lights SET state = 'off';


--Read Committed и потерянные изменения
begin;
SELECT * FROM lights ORDER BY id;

UPDATE lights
SET state = CASE WHEN state = 'on' THEN 'off' ELSE 'on' END;

COMMIT;


-- если изменение выполняется не в одной команде SQL, то обновление будет потеряно
BEGIN;

SELECT state AS old_state FROM lights WHERE lamp = 'red';

DO $$
DECLARE
    v_state text := 'off';
BEGIN
    UPDATE lights SET state = v_state WHERE lamp = 'red';
END $$;


COMMIT;



-- Repeatable Read и неповторяющееся чтение
UPDATE lights SET state = 'on' WHERE lamp = 'red' RETURNING *;

SELECT * FROM lights WHERE lamp = 'red';


--Repeatable Read и фантомное чтение
INSERT INTO lights(lamp,state) VALUES ('yellow', 'off')
RETURNING *;

SELECT * FROM lights;


DELETE FROM lights WHERE lamp = 'yellow';

--Repeatable Read и потерянные изменения
BEGIN ISOLATION LEVEL REPEATABLE READ;


SELECT state AS current_state FROM lights WHERE lamp = 'red';


DO $$
DECLARE
    v_state text := 'off';
BEGIN
    UPDATE lights SET state = v_state WHERE lamp = 'red';
END $$;


COMMIT;
--SQL Error [40001]: ERROR: could not serialize access due to concurrent update
--  Where: SQL statement "UPDATE lights SET state = v_state WHERE lamp = 'red'"
--PL/pgSQL function inline_code_block line 5 at SQL statement
rollback;



--Repeatable Read и другие аномалии
--пример аномалии конкурентного доступа — несогласованная запись (write skew), — которая возможна, даже если нет
--грязного, неповторяющегося и фантомного чтений

BEGIN ISOLATION LEVEL REPEATABLE READ;

UPDATE lights SET state = 'off' WHERE state != 'off';

SELECT * FROM lights ORDER BY id;

COMMIT;


--Serializable
BEGIN ISOLATION LEVEL SERIALIZABLE;

UPDATE lights SET state = 'off' WHERE state != 'off';

SELECT * FROM lights ORDER BY id;

COMMIT;
--SQL Error [40001]: ERROR: could not serialize access due to read/write dependencies among transactions
--  Detail: Reason code: Canceled on identification as a pivot, during commit attempt.
--  Hint: The transaction might succeed if retried.
rollback;

