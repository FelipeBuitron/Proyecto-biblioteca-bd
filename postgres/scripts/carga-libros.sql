-- Carga de libros desde CSV al esquema "biblioteca"
-- Patron: tabla de paso -> validacion -> tablas finales (libro + ejemplar) -> bitacora
--
-- Uso (desde entorno-docker/):
--   docker compose exec postgres psql -U curso -d curso \
--     -v archivo=/scripts/datos-semilla/libros_semilla_con_errores.csv \
--     -f /scripts/carga-libros.sql
-- Sin "-v archivo=..." carga /scripts/datos-semilla/libros_semilla.csv

\set ON_ERROR_STOP on
\if :{?archivo}
\else
    \set archivo /scripts/datos-semilla/libros_semilla.csv
\endif

-- Tablas de paso y bitacora: viven en el esquema "carga", aparte del modelo
CREATE SCHEMA IF NOT EXISTS carga;

CREATE TABLE IF NOT EXISTS carga.stg_linea (
    n     integer GENERATED ALWAYS AS IDENTITY,
    linea text
);

CREATE TABLE IF NOT EXISTS carga.stg_libro (
    linea_csv        integer,
    contenido        text,
    num_campos       integer,
    isbn             text,
    titulo           text,
    autor            text,
    categoria        text,
    anio_publicacion text,
    ejemplares       text,
    motivo           text
);

CREATE TABLE IF NOT EXISTS carga.rechazo_carga (
    id        integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    archivo   text,
    linea     integer,
    contenido text,
    motivo    text,
    fecha     timestamptz DEFAULT now()
);

SET search_path TO biblioteca, carga;

BEGIN;

TRUNCATE carga.stg_linea, carga.stg_libro RESTART IDENTITY;

-- 1. Leer el archivo tal cual: una fila por linea
COPY carga.stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM carga.stg_linea WHERE n = 1;          -- encabezado

-- 2. Partir cada linea en sus campos (todo como texto)
INSERT INTO carga.stg_libro (linea_csv, contenido, num_campos,
                             isbn, titulo, autor, categoria,
                             anio_publicacion, ejemplares)
SELECT n, linea,
       array_length(string_to_array(linea, ','), 1),
       trim(split_part(linea, ',', 1)),
       trim(split_part(linea, ',', 2)),
       trim(split_part(linea, ',', 3)),
       trim(split_part(linea, ',', 4)),
       trim(split_part(linea, ',', 5)),
       trim(split_part(linea, ',', 6))
FROM carga.stg_linea;

-- 3. Validar: la primera regla que falla da el motivo
UPDATE carga.stg_libro AS t SET motivo = CASE
    WHEN num_campos <> 6                     THEN 'tiene ' || num_campos || ' columnas, se esperaban 6'
    WHEN isbn = ''                           THEN 'isbn vacío'
    WHEN isbn !~ '^[0-9]{13}$'               THEN 'isbn no tiene 13 dígitos'
    WHEN titulo = ''                         THEN 'título vacío'
    WHEN autor = ''                          THEN 'autor vacío'
    WHEN anio_publicacion !~ '^[0-9]{1,4}$'  THEN 'año no numérico'
    WHEN anio_publicacion::integer NOT BETWEEN 1450 AND 2100
                                             THEN 'año fuera de rango'
    -- regla propia del grupo: no se aceptan años futuros
    WHEN anio_publicacion::integer > extract(year FROM current_date)::integer
                                             THEN 'año en el futuro'
    WHEN ejemplares !~ '^-?[0-9]+$'          THEN 'ejemplares no numérico'
    WHEN ejemplares ~ '^-'                   THEN 'ejemplares negativo'
    WHEN ejemplares !~ '^[0-9]{1,3}$'        THEN 'ejemplares demasiado grande (máx. 999)'
    WHEN EXISTS (SELECT 1 FROM biblioteca.libro l WHERE l.isbn = t.isbn)
                                             THEN 'isbn ya existe en el catálogo'
END;

-- 4. Duplicados dentro del mismo archivo: se conserva la primera aparicion
UPDATE carga.stg_libro AS t SET motivo = 'isbn repetido en el archivo'
WHERE t.motivo IS NULL
  AND EXISTS (SELECT 1 FROM carga.stg_libro s2
              WHERE s2.isbn = t.isbn
                AND s2.motivo IS NULL
                AND s2.linea_csv < t.linea_csv);

-- 5a. Libros validos a la tabla final (editorial queda NULL: el CSV no la trae)
INSERT INTO biblioteca.libro (isbn, titulo, autor, categoria, ano)
SELECT isbn, titulo, autor, NULLIF(categoria, ''), anio_publicacion::integer
FROM carga.stg_libro
WHERE motivo IS NULL;

-- 5b. Un ejemplar por cada copia: ejemplares = 4 -> '...-1', '...-2', '...-3', '...-4'
INSERT INTO biblioteca.ejemplar (id_ejemplar, isbn)
SELECT s.isbn || '-' || g.n, s.isbn
FROM carga.stg_libro s
CROSS JOIN LATERAL generate_series(1, s.ejemplares::integer) AS g(n)
WHERE s.motivo IS NULL;

-- 6. Rechazadas a la bitacora
INSERT INTO carga.rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM carga.stg_libro
WHERE motivo IS NOT NULL;

COMMIT;

-- Resumen de la carga
SELECT count(*) FILTER (WHERE motivo IS NULL)     AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM carga.stg_libro;

SELECT linea_csv AS linea, motivo, contenido
FROM carga.stg_libro
WHERE motivo IS NOT NULL
ORDER BY linea_csv;
