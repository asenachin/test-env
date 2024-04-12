## test-env

### Улучшить время выполнения следующего запроса  

EXPLAIN ANALYZE VERBOSE  
SELECT body     
FROM posts     
WHERE body ILIKE '%postgres%awesome%'   
OR body ILIKE '%postgres%amazing%';
                                                QUERY PLAN                                                            
--------------------------------------------------------------------------------------------------------  
 Gather  (cost=1000.00..29376.86 rows=44 width=829) (actual time=183.030..2755.678 rows=40 loops=1)  
   Output: body  
   Workers Planned: 2  
   Workers Launched: 2  
   ->  Parallel Seq Scan on public.posts  (cost=0.00..28372.46 rows=18 width=829) (actual time=160.970..2747.124 rows=13 loops=3)  
         Output: body  
         Filter: ((posts.body ~* '%postgres%awesome%'::text) OR (posts.body ~* '%postgres%amazing%'::text))  
         Rows Removed by Filter: 73451  
         Worker 0:  actual time=49.365..2743.866 rows=12 loops=1  
         Worker 1:  actual time=250.882..2744.352 rows=17 loops=1  
 Planning Time: 3.642 ms  
 Execution Time: 2755.715 ms  
(12 rows)     

1. Подключаемся к базе данных  
>$ docker compose exec postgres psql -U postgres interview  

2. Посмотрим на таблицы базы данных  

Посмотрим общую информацию о таблицах:  

interview=# \dt  
>        List of relations  
Schema |     Name     | Type  |  Owner     
-------|--------------|-------|----------  
public | badges       | table | postgres  
public | comments     | table | postgres  
public | post_history | table | postgres  
public | post_links   | table | postgres  
public | posts        | table | postgres  
public | tags         | table | postgres  
public | users        | table | postgres  
public | votes        | table | postgres  
(8 rows)  

Посмотрим на таблицу posts:

interview=# \d posts  
                            Table "public.posts"  
          Column          |            Type             | Collation | Nullable |                Default              
--------------------------+-----------------------------+-----------+----------+-----------------------------------  
 id                       | integer                     |           | not null | nextval('posts_id_seq'::regclass)  
 owner_user_id            | integer                     |           |          |   
 last_editor_user_id      | integer                     |           |          |   
 post_type_id             | smallint                    |           | not null |   
 accepted_answer_id       | integer                     |           |          |   
 score                    | integer                     |           | not null |   
 parent_id                | integer                     |           |          |   
 view_count               | integer                     |           |          |  
 answer_count             | integer                     |           |          | 0  
 comment_count            | integer                     |           |          | 0  
 owner_display_name       | character varying(64)       |           |          |  
 last_editor_display_name | character varying(64)       |           |          |   
 title                    | character varying(512)      |           |          |   
 tags                     | character varying(512)      |           |          |  
 content_license          | character varying(64)       |           | not null |   
 body                     | text                        |           |          |   
 favorite_count           | integer                     |           |          |   
 creation_date            | timestamp without time zone |           | not null |   
 community_owned_date     | timestamp without time zone |           |          |  
 closed_date              | timestamp without time zone |           |          |  
 last_edit_date           | timestamp without time zone |           |          |   
 last_activity_date       | timestamp without time zone |           |          |   
Indexes:  
    "posts_pkey" PRIMARY KEY, btree (id)  

Определим максимальную длину поля body:  

interview=# SELECT max(length(body))  
FROM posts;
  
max   
-------   
 53338  
(1 row)  
  
Time: 333.251 ms  



3. Включаем опцию показа времени выполнения запроса      
>\timing on  

4. Определим время выполнения запроса  
   
>interview=# SELECT body    
FROM posts     
WHERE body ILIKE '%postgres%awesome%'   
OR body ILIKE '%postgres%amazing%';  
Time: 2692.267 ms (00:02.692)  

5. Создаём B-Tree индекс для поля body  
  
>interview=# CREATE INDEX idx_body_btree ON posts USING btree (body);   
ERROR:  index row requires 15472 bytes, maximum size is 8191  
CONTEXT:  parallel worker   
Time: 85.795 ms  

Создать B-Tree индекс не получилось, поэтому создадим другой GIN-индекс с использованием операторов trigram для столбца body:    

>interview=# CREATE INDEX idx_body ON posts USING GIN (body gin_trgm_ops);    
CREATE INDEX   
Time: 100717.235 ms (01:40.717)   

Повторим запрос:      

interview=# EXPLAIN ANALYZE VERBOSE  
SELECT body      
FROM posts  
WHERE body ILIKE '%postgres%awesome%'   
OR body ILIKE '%postgres%amazing%';   
                                QUERY PLAN                                                         
------  
 Bitmap Heap Scan on public.posts  (cost=296.35..467.68 rows=44 width=829) (actual time=15.567..24.971 rows=40 loops=1)  
   Output: body  
   Recheck Cond: ((posts.body ~* '%postgres%awesome%'::text) OR (posts.body ~* '%postgres%amazing%'::text))  
   Rows Removed by Index Recheck: 20  
   Heap Blocks: exact=59  
   ->  BitmapOr  (cost=296.35..296.35 rows=44 width=0) (actual time=15.203..15.204 rows=0 loops=1)  
         ->  Bitmap Index Scan on idx_body  (cost=0.00..148.17 rows=22 width=0) (actual time=7.800..7.800 rows=36 loops=1)  
               Index Cond: (posts.body ~* '%postgres%awesome%'::text)  
         ->  Bitmap Index Scan on idx_body  (cost=0.00..148.17 rows=22 width=0) (actual time=7.401..7.401 rows=24 loops=1)  
               Index Cond: (posts.body ~* '%postgres%amazing%'::text)  
 Planning Time: 3.780 ms  
 Execution Time: 25.041 ms  
(12 rows)  
Time: 29.539 ms  

Ура! Нам удалось уменьшить время выполнения запроса на два порядка.   
      
### Представим себе, что данная БД находится под нагрузкой в продуктивном окружении. Если вам потребуется создать индекс, то как вы будете это делать?

Работа базы данных под нагрузкой отличается от работы без нагрузки только временем выполнения запросов. Поэтому для этого запроса я не буду создавать индекс, так как на его создание тоже необходимо потратить процессорное время и память сервера.  

### Является ли хорошей практикой создание индекса во время высокой транзакционной нагрузки?  

Создание индекса во время высокой транзакционной нагрузки может блокировать данную таблицу базы данных, что может привести к замедлению выполнения транзакций или даже к ошибкам их выполнения.

### Какие параметры PostgreSQL нужно изменить, чтобы ускорить создание индекса при повышенной нагрузке?

Удалим созданный индекс:

interview=# DROP INDEX idx_body;  
DROP INDEX  
Time: 49.348 ms  

Когда оптимизатор определяет, что параллельное выполнение будет наилучшей стратегией для конкретного запроса, он создаёт план запроса, включающий узел Gather (Сбор):  

EXPLAIN  
SELECT body       
FROM posts       
WHERE body ILIKE '%postgres%awesome%'    
OR body ILIKE '%postgres%amazing%';  
                                QUERY PLAN                                              
-----  
 Gather  (cost=1000.00..29376.86 rows=44 width=829)  
   Workers Planned: 2  
   ->  Parallel Seq Scan on posts  (cost=0.00..28372.46 rows=18 width=829)  
         Filter: ((body ~* '%postgres%awesome%'::text) OR (body ~* '%postgres%amazing%'::text))  
(4 rows)  

Количество исполнителей, которое может попытаться задействовать планировщик, ограничивается значением `max_parallel_workers_per_gather`. Общее число фоновых рабочих процессов, которые могут существовать одновременно, ограничивается параметрами `max_worker_processes` и `max_parallel_workers`.  

Определим значения некоторые параметры планировщика:

interview=# SELECT name, setting  
FROM pg_settings  
WHERE name IN ('max_parallel_workers_per_gather',   
               'max_worker_processes',  
               'max_parallel_workers',
               'max_parallel_maintenance_workers');  
              name               | setting   
---------------------------------+---------  
 max_parallel_workers            | 8  
 max_parallel_workers_per_gather | 2  
 max_worker_processes            | 8  
(3 rows)  

Time: 2.435 ms  

Увеличим значение параметра `max_parallel_workers_per_gather`:  
 
interview=# ALTER SYSTEM SET max_parallel_maintenance_workers = 8;  
ALTER SYSTEM  
Time: 13.836 ms

Перезагрузим конфигурацию для применения изменений:  

interview=# SELECT pg_reload_conf();  
 pg_reload_conf  
----------------  
 t  
(1 row)  

Time: 4.197 ms



### Результат

1. Файл в формате Markdown содержащий описание и пояснение выполненных действий
2. Должен содержать исходный и финальный планы запроса со временем исполнения
3. Описание создания индекса для нагруженной системы

