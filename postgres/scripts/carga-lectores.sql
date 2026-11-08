-- Carga de lectores desde CSV al esquema "biblioteca"
-- Los lectores son filas de "usuario" con rol = 'lector'.
--
-- Uso (desde entorno-docker/):
--   docker compose exec postgres psql -U curso -d curso \
--     -v archivo=/scripts/datos-semilla/lectores_semilla_con_errores.csv \
--     -f /scripts/carga-lectores.sql
-- Sin "-v archivo=..." carga /scripts/datos-semilla/lectores_semilla.csv

\set ON_ERROR_STOP on
\if :{?archivo}
\else
    \set archivo /scripts/datos-semilla/lectores_semilla.csv
\endif

-- Tablas de paso y bitacora (las mismas que usa carga-libros.sql)
CREATE SCHEMA IF NOT EXISTS carga;

CREATE TABLE IF NOT EXISTS carga.stg_linea (
    n     integer GENERATED ALWAYS AS IDENTITY,
    linea text
);

CREATE TABLE IF NOT EXISTS carga.stg_lector (
    linea_csv  integer,
    contenido  text,
    num_campos integer,
    documento  text,
    nombres    text,
    apellidos  text,
    correo     text,
    telefono   text,
    motivo     text
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

TRUNCATE carga.stg_linea, carga.stg_lector RESTART IDENTITY;

-- 1. Leer el archivo tal cual: una fila por linea
COPY carga.stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM carga.stg_linea WHERE n = 1;          -- encabezado

-- 2. Partir cada linea en sus campos; el correo se normaliza a minusculas
INSERT INTO carga.stg_lector (linea_csv, contenido, num_campos,
                              documento, nombres, apellidos, correo, telefono)
SELECT n, linea,
       array_length(string_to_array(linea, ','), 1),
       trim(split_part(linea, ',', 1)),
       trim(split_part(linea, ',', 2)),
       trim(split_part(linea, ',', 3)),
       lower(trim(split_part(linea, ',', 4))),
       trim(split_part(linea, ',', 5))
FROM carga.stg_linea;

-- 3. Validar: la primera regla que falla da el motivo
UPDATE carga.stg_lector AS t SET motivo = CASE
    WHEN num_campos <> 5                      THEN 'tiene ' || num_campos || ' columnas, se esperaban 5'
    WHEN documento = ''                       THEN 'documento vacío'
    WHEN documento !~ '^[0-9]{6,15}$'         THEN 'documento no numérico o de longitud inválida'
    WHEN nombres = ''                         THEN 'nombres vacío'
    WHEN apellidos = ''                       THEN 'apellidos vacío'
    WHEN correo = ''                          THEN 'correo vacío'
    WHEN correo !~ '^[^@ ]+@[^@ ]+\.[^@ ]+$'  THEN 'correo mal formado'
    WHEN telefono !~ '^[0-9]{7,15}$'          THEN 'teléfono no numérico o de longitud inválida'
    WHEN EXISTS (SELECT 1 FROM biblioteca.usuario u WHERE u.documento = t.documento)
                                              THEN 'documento ya existe'
    WHEN EXISTS (SELECT 1 FROM biblioteca.usuario u WHERE lower(u.correo) = t.correo)
                                              THEN 'correo ya registrado por otro usuario'
END;

-- 4. Duplicados dentro del mismo archivo (por documento o por correo)
UPDATE carga.stg_lector AS t SET motivo = 'documento o correo repetido en el archivo'
WHERE t.motivo IS NULL
  AND EXISTS (SELECT 1 FROM carga.stg_lector s2
              WHERE (s2.documento = t.documento OR s2.correo = t.correo)
                AND s2.motivo IS NULL
                AND s2.linea_csv < t.linea_csv);

-- 5. Validos a la tabla final: nombres + apellidos van juntos en usuario.nombre
INSERT INTO biblioteca.usuario (documento, nombre, correo, telefono, rol)
SELECT documento, nombres || ' ' || apellidos, correo, telefono, 'lector'
FROM carga.stg_lector
WHERE motivo IS NULL;

-- 6. Rechazadas a la bitacora
INSERT INTO carga.rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM carga.stg_lector
WHERE motivo IS NOT NULL;

COMMIT;

-- Resumen de la carga
SELECT count(*) FILTER (WHERE motivo IS NULL)     AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM carga.stg_lector;

SELECT linea_csv AS linea, motivo, contenido
FROM carga.stg_lector
WHERE motivo IS NOT NULL
ORDER BY linea_csv;
