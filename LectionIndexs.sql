-- таблицы, индексы, последовательности, представления
select * from pg_class;
-- индексы
select * from pg_index;
-- типы индексов
select * from pg_am;

-- индексы
select * from pg_class where relkind = 'i'
-- таблицы
select * from pg_class where relkind = 'r'
-- представления
select * from pg_class where relkind = 'v'
-- материализованные представления
select * from pg_class where relkind = 'm'

-- индексы по таблице
SELECT 
    i.relname as index_name,
    am.amname as index_type,
    idx.indisunique as is_unique,
    idx.indisprimary as is_primary,
    idx.indisvalid as is_valid,
    pg_get_indexdef(idx.indexrelid) as index_definition,
	t.relname
FROM 
    pg_index idx
    JOIN pg_class i ON i.oid = idx.indexrelid
    JOIN pg_class t ON t.oid = idx.indrelid
    JOIN pg_am am ON i.relam = am.oid
WHERE 
    t.relname = 'boarding_passes';
	
-- количество индексов разных типов 
SELECT 
    amname as method_name,
    (SELECT count(*) FROM pg_index i 
     JOIN pg_class c ON c.oid = i.indexrelid 
     WHERE c.relam = pg_am.oid) as index_count
FROM pg_am
ORDER BY index_count DESC;	

-- обычные индексы B-tree
-- индексы по таблице tickets
SELECT 
    i.relname as index_name,
    am.amname as index_type,
    idx.indisunique as is_unique,
    idx.indisprimary as is_primary,
    idx.indisvalid as is_valid,
    pg_get_indexdef(idx.indexrelid) as index_definition,
	t.relname
FROM 
    pg_index idx
    JOIN pg_class i ON i.oid = idx.indexrelid
    JOIN pg_class t ON t.oid = idx.indrelid
    JOIN pg_am am ON i.relam = am.oid
WHERE 
    t.relname = 'tickets';
	
explain	
SELECT count( * )
FROM tickets
WHERE passenger_name = 'IVAN IVANOV';

-- без индекса сканирование таблицы Seq Scan, долго 9054.56 попугаев
-- Successfully run. Total query runtime: 750 msec.
-- 1 rows affected.

-- "Finalize Aggregate  (cost=9054.55..9054.56 rows=1 width=8)"
-- "  ->  Gather  (cost=9054.34..9054.55 rows=2 width=8)"
-- "        Workers Planned: 2"
-- "        ->  Partial Aggregate  (cost=8054.34..8054.35 rows=1 width=8)"
-- "              ->  Parallel Seq Scan on tickets  (cost=0.00..8054.07 rows=107 width=0)"
-- "                    Filter: (passenger_name = 'IVAN IVANOV'::text)"



CREATE INDEX passenger_name
ON tickets ( passenger_name );

-- с индексом сканирование индекса Index Scan, в 10 раз быстрее 868.52 vs 9054.56 попугаев
-- Successfully run. Total query runtime: 56 msec.
-- 1 rows affected.

-- "Aggregate  (cost=869.16..869.17 rows=1 width=8)"
-- "  ->  Bitmap Heap Scan on tickets  (cost=10.41..868.52 rows=257 width=0)"
-- "        Recheck Cond: (passenger_name = 'IVAN IVANOV'::text)"
-- "        ->  Bitmap Index Scan on passenger_name  (cost=0.00..10.35 rows=257 width=0)"
-- "              Index Cond: (passenger_name = 'IVAN IVANOV'::text)"

drop index passenger_name


-- hash индекс, только по равенству
EXPLAIN --(costs off)
SELECT * FROM seats WHERE seat_no = '31D';

-- "Seq Scan on seats  (cost=0.00..24.74 rows=2 width=15)"
-- "  Filter: ((seat_no)::text = '31D'::text)"

CREATE INDEX seats_seat_no_idx ON seats USING hash(seat_no);

EXPLAIN --(costs off)
SELECT * FROM seats WHERE seat_no = '31D';

-- "Bitmap Heap Scan on seats  (cost=4.02..9.04 rows=2 width=15)"
-- "  Recheck Cond: ((seat_no)::text = '31D'::text)"
-- "  ->  Bitmap Index Scan on seats_seat_no_idx  (cost=0.00..4.01 rows=2 width=0)"
-- "        Index Cond: ((seat_no)::text = '31D'::text)"


-- по неравенству уже не работает
EXPLAIN --(costs off)
SELECT * FROM seats WHERE seat_no > '31D';


-- "Seq Scan on seats  (cost=0.00..24.75 rows=492 width=15)"
-- "  Filter: ((seat_no)::text > '31D'::text)"

SELECT 
    i.relname as index_name,
    am.amname as index_type,
    idx.indisunique as is_unique,
    idx.indisprimary as is_primary,
    idx.indisvalid as is_valid,
    pg_get_indexdef(idx.indexrelid) as index_definition,
	t.relname
FROM 
    pg_index idx
    JOIN pg_class i ON i.oid = idx.indexrelid
    JOIN pg_class t ON t.oid = idx.indrelid
    JOIN pg_am am ON i.relam = am.oid
WHERE 
    t.relname = 'seats';
	
drop index seats_seat_no_idx


-- Размер и время создания hash-индексов примерно одинаковы. А размер индексов B-tree (как и время их построения) зависит от
-- размера индексируемого поля, поскольку такие индексы хранят индексируемые значения.
-- hash
CREATE INDEX tickets_hash_br ON tickets USING hash(book_ref);
--Query returned successfully in 902 msec.
CREATE INDEX tickets_hash_cd ON tickets USING hash(contact_data);
--Query returned successfully in 636 msec.

--индексы B-tree:
CREATE INDEX tickets_btree_br ON tickets(book_ref);
--Query returned successfully in 824 msec.
CREATE INDEX tickets_btree_cd ON tickets(contact_data);
--Query returned successfully in 3 secs 401 msec.

SELECT pg_size_pretty(pg_total_relation_size('tickets_hash_br')) "hash book_ref",
pg_size_pretty(pg_total_relation_size('tickets_hash_cd')) "hash contact_data",
pg_size_pretty(pg_total_relation_size('tickets_btree_br')) "btree book_ref",
pg_size_pretty(pg_total_relation_size('tickets_btree_cd')) "btree contact_data"
-- "10 MB"	"10 MB"	"8064 kB"	"28 MB"

drop index tickets_hash_br;
drop index tickets_hash_cd;
drop index tickets_btree_br;
drop index tickets_btree_cd;


-- GiST
SELECT 
    i.relname as index_name,
    am.amname as index_type,
    idx.indisunique as is_unique,
    idx.indisprimary as is_primary,
    idx.indisvalid as is_valid,
    pg_get_indexdef(idx.indexrelid) as index_definition,
	t.relname
FROM 
    pg_index idx
    JOIN pg_class i ON i.oid = idx.indexrelid
    JOIN pg_class t ON t.oid = idx.indrelid
    JOIN pg_am am ON i.relam = am.oid
WHERE 
    t.relname = 'airports_data';

EXPLAIN --(costs off)
SELECT airport_code
FROM airports_data
WHERE coordinates <@ '<(37.622513,55.753220),1.0>'::circle;


-- "Seq Scan on airports_data  (cost=0.00..4.30 rows=1 width=4)"
-- "  Filter: (coordinates <@ '<(37.622513,55.75322),1>'::circle)"

CREATE INDEX airports_gist_idx ON airports_data
USING gist(coordinates);

SET enable_seqscan = off;
-- "Index Scan using airports_gist_idx on airports_data  (cost=0.14..8.15 rows=1 width=4)"
-- "  Index Cond: (coordinates <@ '<(37.622513,55.75322),1>'::circle)"

SET enable_seqscan = on;

DROP INDEX airports_gist_idx;

-- список всех существующих классов операторов
SELECT am.amname AS index_method,
       opc.opcname AS opclass_name,
       opc.opcintype::regtype AS indexed_type,
       opc.opcdefault AS is_default
    FROM pg_am am, pg_opclass opc
    WHERE opc.opcmethod = am.oid
    ORDER BY index_method, opclass_name;

-- индекс SP-GIST
EXPLAIN --(costs off)
SELECT airport_code
FROM airports_data
WHERE coordinates >^ '(72.69889831542969,65.48090362548828)'::point;


-- "Seq Scan on airports_data  (cost=0.00..4.30 rows=10 width=4)"
-- "  Filter: (coordinates >^ '(72.69889831542969,65.48090362548828)'::point)"

CREATE INDEX airports_spgist_idx ON airports_data
USING spgist(coordinates kd_point_ops);

SET enable_seqscan = off;

-- "Bitmap Heap Scan on airports_data  (cost=4.22..7.34 rows=10 width=4)"
-- "  Recheck Cond: (coordinates >^ '(72.69889831542969,65.48090362548828)'::point)"
-- "  ->  Bitmap Index Scan on airports_spgist_idx  (cost=0.00..4.21 rows=10 width=0)"
-- "        Index Cond: (coordinates >^ '(72.69889831542969,65.48090362548828)'::point)"
SET enable_seqscan = on;

drop index airports_spgist_idx;



-- индекс GIN
SELECT 
	flight_no, 
	days_of_week -- массив номеров дней недели, по которым выполняется рейс
	FROM routes LIMIT 5;

-- создает таблицу из представления
CREATE TABLE routes_tbl
	AS SELECT * FROM routes;
	
EXPLAIN --(costs off)
SELECT flight_no, departure_airport_name AS departure,
arrival_airport_name AS arrival, days_of_week
FROM routes_tbl
WHERE days_of_week = ARRAY[3,6];

-- "Seq Scan on routes_tbl  (cost=0.00..25.88 rows=23 width=85)"
-- "  Filter: (days_of_week = '{3,6}'::integer[])"
CREATE INDEX routestbl_gin_idx ON routes_tbl USING gin(days_of_week);


SET enable_seqscan = off;

-- "Bitmap Heap Scan on routes_tbl  (cost=12.18..30.35 rows=23 width=85)"
-- "  Recheck Cond: (days_of_week = '{3,6}'::integer[])"
-- "  ->  Bitmap Index Scan on routestbl_gin_idx  (cost=0.00..12.17 rows=23 width=0)"
-- "        Index Cond: (days_of_week = '{3,6}'::integer[])"
SET enable_seqscan = on;

drop index routestbl_gin_idx;


EXPLAIN --(analyze, buffers, costs off, timing off)
SELECT * FROM tickets
WHERE contact_data->>'phone' LIKE '%1234%';


-- "Gather (actual rows=233 loops=1)"
-- "  Workers Planned: 2"
-- "  Workers Launched: 2"
-- "  Buffers: shared hit=1024 read=5120"
-- "  ->  Parallel Seq Scan on tickets (actual rows=78 loops=3)"
-- "        Filter: ((contact_data ->> 'phone'::text) ~~ '%1234%'::text)"
-- "        Rows Removed by Filter: 122167"
-- "        Buffers: shared hit=1024 read=5120"
-- "Planning Time: 0.042 ms"
-- "Execution Time: 86.144 ms"


-- "Gather  (cost=1000.00..9729.48 rows=2934 width=104)"
-- "  Workers Planned: 2"
-- "  ->  Parallel Seq Scan on tickets  (cost=0.00..8436.08 rows=1222 width=104)"
-- "        Filter: ((contact_data ->> 'phone'::text) ~~ '%1234%'::text)"


-- "Bitmap Heap Scan on tickets (actual rows=233 loops=1)"
-- "  Recheck Cond: ((contact_data ->> 'phone'::text) ~~ '%1234%'::text)"
-- "  Rows Removed by Index Recheck: 5"
-- "  Heap Blocks: exact=235"
-- "  Buffers: shared hit=58 read=184"
-- "  ->  Bitmap Index Scan on tickets_gin (actual rows=238 loops=1)"
-- "        Index Cond: ((contact_data ->> 'phone'::text) ~~ '%1234%'::text)"
-- "        Buffers: shared hit=7"
-- "Planning Time: 0.112 ms"
-- "Execution Time: 0.685 ms"


-- "Bitmap Heap Scan on tickets  (cost=42.74..5149.65 rows=2934 width=104)"
-- "  Recheck Cond: ((contact_data ->> 'phone'::text) ~~ '%1234%'::text)"
-- "  ->  Bitmap Index Scan on tickets_gin  (cost=0.00..42.00 rows=2934 width=0)"
-- "        Index Cond: ((contact_data ->> 'phone'::text) ~~ '%1234%'::text)"

CREATE EXTENSION pg_trgm;

CREATE INDEX tickets_gin
ON tickets USING GIN ((contact_data->>'phone') gin_trgm_ops);

drop index tickets_gin;

-- индекс BRIN
EXPLAIN --(analyze, costs off, timing off)
SELECT *
FROM ticket_flights
WHERE flight_id BETWEEN 3000 AND 4000;


-- "Gather  (cost=1000.00..20524.99 rows=42742 width=32)"
-- "  Workers Planned: 2"
-- "  ->  Parallel Seq Scan on ticket_flights  (cost=0.00..15250.79 rows=17809 width=32)"
-- "        Filter: ((flight_id >= 3000) AND (flight_id <= 4000))"

CREATE INDEX tflights_brin_idx ON ticket_flights USING brin(flight_id);

-- "Bitmap Heap Scan on ticket_flights  (cost=23.91..17471.33 rows=42742 width=32)"
-- "  Recheck Cond: ((flight_id >= 3000) AND (flight_id <= 4000))"
-- "  ->  Bitmap Index Scan on tflights_brin_idx  (cost=0.00..13.23 rows=582161 width=0)"
-- "        Index Cond: ((flight_id >= 3000) AND (flight_id <= 4000))"

drop index tflights_brin_idx



-- Статистика
-- количество записей и блоков в таблице
SELECT relname, relkind, reltuples as "записи", relpages as "блоки"
FROM pg_class
WHERE relname LIKE 'seats%';

select * from seats

-- представление pg_stats
SELECT *
FROM pg_stats
WHERE tablename = 'seats';

SELECT attname, inherited, n_distinct,
       array_to_string(most_common_vals, E'\n') as most_common_vals
FROM pg_stats
WHERE tablename = 'seats';

-- исходная статистика в pg_statistic
SELECT *
FROM pg_statistic
WHERE tablename = 'seats';


