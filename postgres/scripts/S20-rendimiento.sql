-- S20. Taller: desnormalización para rendimiento y Hito 3
-- Caso: una biblioteca "grande" (5 000 títulos, 15 000 ejemplares, ~300 000
-- préstamos) generada con generate_series, en 3FN, para medir consultas.
--
-- Uso (desde entorno-docker/, con este archivo copiado en postgres/scripts/):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/S20-rendimiento.sql
--
-- Tarda unos segundos. Se puede correr cuantas veces se quiera: borra y
-- recrea el esquema "rendimiento" completo, sin tocar nada más de la base.
-- Los datos son deterministas (no usan random()): todos los grupos obtienen
-- los mismos resultados, aunque los tiempos dependen de cada computador.
-- Para trabajar después sobre estas tablas desde psql o pgAdmin:
--   SET search_path TO rendimiento;

DROP SCHEMA IF EXISTS rendimiento CASCADE;
CREATE SCHEMA rendimiento;
SET search_path TO rendimiento;

CREATE TABLE libro (
    isbn       char(13)     PRIMARY KEY,
    titulo     varchar(200) NOT NULL,
    autor      varchar(120) NOT NULL,
    categoria  varchar(40)  NOT NULL
);

CREATE TABLE ejemplar (
    id_ejemplar  integer   PRIMARY KEY,
    isbn         char(13)  NOT NULL REFERENCES libro
);

CREATE TABLE lector (
    documento  varchar(15)  PRIMARY KEY,
    nombres    varchar(80)  NOT NULL
);

CREATE TABLE prestamo (
    id                integer      PRIMARY KEY,
    id_ejemplar       integer      NOT NULL REFERENCES ejemplar,
    documento         varchar(15)  NOT NULL REFERENCES lector,
    fecha_prestamo    date         NOT NULL,
    fecha_esperada    date         NOT NULL,
    fecha_devolucion  date                    -- NULL = préstamo abierto
);

-- 5 000 títulos: "Libro 1" … "Libro 5000"
INSERT INTO libro
SELECT '978' || lpad(i::text, 10, '0'),
       'Libro ' || i,
       'Autor ' || (1 + i % 800),
       (ARRAY['Novela', 'Cuento', 'Ciencia Ficción', 'Infantil', 'Historia', 'Ciencia'])[1 + i % 6]
FROM   generate_series(1, 5000) AS i;

-- 3 ejemplares por título: los del libro i son 3i-2, 3i-1 y 3i
INSERT INTO ejemplar
SELECT (i - 1) * 3 + k, '978' || lpad(i::text, 10, '0')
FROM   generate_series(1, 5000) AS i, generate_series(1, 3) AS k;

INSERT INTO lector
SELECT (1000000000 + i)::text, 'Lector ' || i
FROM   generate_series(1, 2000) AS i;

-- 300 000 préstamos ya devueltos, repartidos entre 2023 y 2025.
-- Los ejemplares de los libros con número bajo se prestan más.
INSERT INTO prestamo
SELECT n,
       (1 + ((n::bigint * 7919) % 15000) ^ 2 / 15000)::integer,
       (1000000000 + 1 + (n::bigint * 104729) % 2000)::text,
       date '2023-01-01' + (n % 1000),
       date '2023-01-01' + (n % 1000) + 14,
       date '2023-01-01' + (n % 1000) + (n % 20)
FROM   generate_series(1, 300000) AS n;

-- Un préstamo abierto para cada ejemplar múltiplo de 4 (3 750 abiertos)
INSERT INTO prestamo
SELECT 300000 + e,
       e,
       (1000000000 + 1 + (e * 31) % 2000)::text,
       CURRENT_DATE - (e % 30),
       CURRENT_DATE - (e % 30) + 14,
       NULL
FROM   generate_series(4, 15000, 4) AS e;

ANALYZE;

-- ---------------------------------------------------------------
-- Verificación
-- ---------------------------------------------------------------

SELECT (SELECT count(*) FROM libro)    AS libros,
       (SELECT count(*) FROM ejemplar) AS ejemplares,
       (SELECT count(*) FROM lector)   AS lectores,
       (SELECT count(*) FROM prestamo) AS prestamos,
       (SELECT count(*) FROM prestamo WHERE fecha_devolucion IS NULL) AS abiertos;