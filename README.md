## test-env  

### Улучшить время выполнения следующего запроса    

>```EXPLAIN ANALYZE VERBOSE```    
```SELECT body```         
```FROM posts```         
```WHERE body ILIKE '%postgres%awesome%'```       
```OR body ILIKE '%postgres%amazing%';```    

                            QUERY PLAN                               
---    
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

1 Подключаемся к базе данных 
 
>```$ docker compose exec postgres psql -U postgres interview```    


2 Посмотрим на таблицы базы данных  
2.1 Общая информация о таблицах  

>```interview=# \dt```
  
          List of relations  
Schema  | Name          | Type   | Owner  
------- | ------------- | ------ | ---------  
public  | badges        | table  | postgres  
public  | comments      | table  | postgres  
public  | post_history  | table  | postgres  
public  | post_links    | table  | postgres  
public  | posts         | table  | postgres  
public  | tags          | table  | postgres  
public  | users         | table  | postgres  
public  | votes         | table  | postgres  
(8 rows)    
  
  
2.2 Таблица posts  

>```interview=# \d posts```
  
                                     Table "public.posts"  
Column                    | Type                        | Collation | Nullable | Default  
------------------------- | --------------------------- | --------- | -------- | ----------------------------------  
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

2.3 Максимальная длина поля body  

>```interview=# SELECT max(length(body))```  
```FROM posts;```  
  
max  
 53338  
(1 row)  
  
Time: 333.251 ms  

**Вывод**

Максимальная длина текстового поля body 53338 символов.

2.4 Время выполнения запроса без индекса  

Включаем опцию показа времени выполнения запроса     
>\timing on  

2.4.1 Определим время выполнения запроса  
   
>```interview=# SELECT body```      
```FROM posts```       
```WHERE body ILIKE '%postgres%awesome%'```     
```OR body ILIKE '%postgres%amazing%';```    
```Time: 2692.267 ms (00:02.692)```    

**Вывод**

Время выполнения запроса без индекса составило 2.692 с.  

2.5 Время выполнения запроса с индексом  

Создаём B-Tree индекс для поля body  
  
>```interview=# CREATE INDEX idx_body_btree ON posts USING btree (body);```     
```ERROR:  index row requires 15472 bytes, maximum size is 8191```    
```CONTEXT:  parallel worker```     
```Time: 85.795 ms```    

**Вывод** 

Создать B-Tree индекс не получилось из-за большой длины текстового поля body.   

Создадим GIN-индекс с использованием операторов trigram для столбца body:    

>interview=# CREATE INDEX idx_body ON posts USING GIN (body gin_trgm_ops);    
CREATE INDEX   
Time: 59395.500 ms (00:59.396)   

Повторим запрос:      

>```interview=# EXPLAIN ANALYZE VERBOSE```    
```SELECT body```        
```FROM posts```    
```WHERE body ILIKE '%postgres%awesome%'```     
```OR body ILIKE '%postgres%amazing%';```  
   
                                QUERY PLAN  
---  
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

**Вывод**

Поиск по индексу уменьшил время выполнения запроса почти на два порядка.   
      
### Представим себе, что данная БД находится под нагрузкой в продуктивном окружении. Если вам потребуется создать индекс, то как вы будете это делать?

Считаю, что работа базы данных под нагрузкой и без неё будет отличаться только временем выполнения запросов.  
Также стоит отметить, что создание индекса не всегда может привести к уменьшению времени выполнения запросов, например, при создании индекса для небольших по размеру таблиц. 
В нашем случае, так как время создания индекса в десятки раз превышает время выполнения запроса, то создавать индекс, я считаю, нецелесообразно.  
Если индекс необходимо всё же создать, то необходимо завершить все процессы с нужным полем таблицы и тогда уже создавать индекс, как в примере выше.  

### Является ли хорошей практикой создание индекса во время высокой транзакционной нагрузки?  

Создание индекса во время высокой транзакционной нагрузки может блокировать таблицу базы данных и привести к замедлению выполнения транзакций или возможно даже к ошибкам их выполнения. Поэтому я думаю, что создание индекса с высокой транзакционной нагрузкой не является хорошей практикой.

### Какие параметры PostgreSQL нужно изменить, чтобы ускорить создание индекса при повышенной нагрузке?

Думаю, что следующие параменты PostgreSQL могут повлиять на время создания индекса:  

* maintenance_work_mem - максимальный объем памяти, который может использоваться для операций обслуживания, таких как создание индексов, выполнение анализа, и операции VACUUM и ANALYZE;  
* shared_buffers - объем памяти, который будет выделен на сервере базы данных для кэширования данных в оперативной памяти. Увеличение значения параметра shared_buffers может улучшить производительность базы данных, поскольку больший объем данных будет доступен для операций чтения и записи без необходимости обращения к диску;  
* temp_buffers - максимальное количество буферов, выделенных для временных объектов и промежуточных результатов запросов, которые хранятся в оперативной памяти.  

**Определим значения этих параметров в нашей СУБД**    

>```interview=# SELECT name, setting```  
```FROM pg_settings```  
```WHERE name IN (```    
```               'shared_buffers',```   
```               'maintenance_work_mem',```  
```               'temp_buffers');```  
  
name                  | setting  
--------------------- | --------  
 maintenance_work_mem | 65536  
 shared_buffers       | 16384  
 temp_buffers         | 1024  


**Проверим влияние maintenance_work_mem на время создания индекса**   

>```interview=# ALTER SYSTEM SET maintenance_work_mem = 131072;```  
ALTER SYSTEM  

Закрепим изменения:  
>```interview=# SELECT pg_reload_conf();```  
 pg_reload_conf 
--  
 t
(1 row)

Удалим, созданный ранее индекс:

>```interview=# DROP INDEX idx_body;```    
```DROP INDEX```    
```Time: 49.348 ms```      

Создаём индекс по полю posts:  

>```interview=# CREATE INDEX idx_body ON posts USING GIN (body gin_trgm_ops);```  
CREATE INDEX  
Time: 60892.021 ms (01:00.892)  

**Вывод**  

Увеличение maintenance_work_mem не сократило время создания индекса.  

**Проверим влияние shared_buffers на время создания индекса**    

>```interview=# ALTER SYSTEM SET shared_buffers = 32768;```  
ALTER SYSTEM  
Time: 10.912 ms  

Создаём индекс по полю posts:  

>```interview=# CREATE INDEX idx_body ON posts USING GIN (body gin_trgm_ops);```  
CREATE INDEX  
Time: 61363.184 ms (01:01.363)  

**Вывод**  

Увеличение shared_buffers не сократило время создания индекса.  

**Проверим влияние temp_buffers на время создания индекса:**     

>```interview=# ALTER SYSTEM SET temp_buffers = 2048;```  
ALTER SYSTEM   
Time: 12.438 ms   

Создаём индекс по полю posts:   

>```interview=# CREATE INDEX idx_body ON posts USING GIN (body gin_trgm_ops);```   
CREATE INDEX  
Time: 59392.673 ms (00:59.393)  

**Вывод**  

Увеличение temp_buffers не сократило время создания индекса.  

**Общий вывод**  

Изменения параметров maintenance_work_mem, shared_buffers и temp_buffers не привело к ускорению создания индекса, что является тоже результатом.  

p.s. Я обязательно продолжу поиски решения последнего вопроса.
