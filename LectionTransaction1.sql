CREATE TABLE lights(
id integer GENERATED ALWAYS AS IDENTITY,
lamp text,
state text
);

select * from lights;

INSERT INTO lights(lamp,state) VALUES
('red', 'on'), ('green', 'off');

SELECT * FROM lights ORDER BY id;

BEGIN;

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

SHOW transaction_isolation;

rollback;

BEGIN ISOLATION LEVEL READ COMMITTED;


SHOW default_transaction_isolation;


-- 1 transaction
-- Read Committed и грязное чтение
BEGIN;
UPDATE lights SET state = 'off' WHERE lamp = 'red';
SELECT * FROM lights ORDER BY id;

-- 2 transaction
BEGIN;
SELECT * FROM lights ORDER BY id;

ROLLBACK;


-- Read Committed и чтение зафиксированных изменений
SELECT * FROM lights ORDER BY id;
BEGIN;

UPDATE lights SET state = 'off' WHERE lamp = 'red';

COMMIT;

--Можно ли увидеть изменения, зафиксированные в процессе выполнения одного оператора?
SELECT * FROM lights ORDER BY id;
SELECT *, pg_sleep(5) FROM lights ORDER BY id;


--функция с категорией изменчивости volatile
drop function get_state;
CREATE FUNCTION get_state(lamp text) RETURNS text
LANGUAGE sql VOLATILE
RETURN (SELECT l.state FROM lights l WHERE l.lamp = get_state.lamp);


SELECT * FROM lights ORDER BY id;
SELECT *, get_state(lamp), pg_sleep(5) FROM lights ORDER BY id;

--функция с категорией изменчивости STABLE
ALTER FUNCTION get_state STABLE;


--Read Committed и потерянные изменения
--Команда UPDATE во второй транзакции блокирует строки таблицы по очереди. Сначала блокируется зеленая лампочка и
--изменяется ее состояние, а затем команда ждет снятия блокировки красной лампочки первой транзакцией.
--При этом команда во второй транзакции не должна видеть изменений, сделанных после начала ее выполнения. С другой
--стороны, она не должна потерять изменения, зафиксированные другими транзакциями. Поэтому после снятия
--блокировки она перечитывает строку, которую пытается обновить.В итоге, первая транзакция выключает красную лампочку, а вторая снова включает ее.

UPDATE lights SET state = 'on';
SELECT * FROM lights ORDER BY id;

begin;
UPDATE lights SET state = 'off' WHERE lamp = 'red';

COMMIT;


-- если изменение выполняется не в одной команде SQL, то обновление будет потеряно
UPDATE lights SET state = 'on';
SELECT * FROM lights ORDER BY id;
begin;
UPDATE lights SET state = 'blink' WHERE lamp = 'red';

COMMIT;


-- Repeatable Read и неповторяющееся чтение
BEGIN ISOLATION LEVEL REPEATABLE READ;

SELECT * FROM lights WHERE lamp = 'red';

SELECT * FROM lights WHERE lamp = 'red';

COMMIT;


--Repeatable Read и фантомное чтение
UPDATE lights SET state = 'off';

BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT * FROM lights WHERE state = 'off';

COMMIT;

SELECT * FROM lights WHERE state = 'off';


--Repeatable Read и потерянные изменения
UPDATE lights SET state = 'on';
SELECT * FROM lights WHERE lamp = 'red';

begin;
UPDATE lights SET state = 'blink' WHERE lamp = 'red';


COMMIT;


--Repeatable Read и другие аномалии
--пример аномалии конкурентного доступа — несогласованная запись (write skew), — которая возможна, даже если нет
--грязного, неповторяющегося и фантомного чтений

SELECT * FROM lights;
UPDATE lights SET state = 'off';
UPDATE lights SET state = 'on' WHERE lamp = 'red';


BEGIN ISOLATION LEVEL REPEATABLE READ;
UPDATE lights SET state = 'on' WHERE state != 'on';

SELECT * FROM lights ORDER BY id;

COMMIT;


--Serializable
SELECT * FROM lights;
UPDATE lights SET state = 'off';
UPDATE lights SET state = 'on' WHERE lamp = 'red';

BEGIN ISOLATION LEVEL SERIALIZABLE;

UPDATE lights SET state = 'on' WHERE state != 'on';

SELECT * FROM lights ORDER BY id;

COMMIT;