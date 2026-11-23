-- normalizacion.sql  (Hito 3)
-- Migra la base ACTUAL del grupo (esquema "biblioteca" del Hito 2) al esquema
-- normalizado, SIN perder datos: solo se elimina la columna derivada
-- prestamo.estado y se agregan dos vistas.
--
-- Uso (desde entorno-docker/, con el archivo en postgres/scripts/):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/normalizacion.sql
--
-- Solo se corre UNA vez sobre una base que todavia tiene prestamo.estado.

\set ON_ERROR_STOP on
SET search_path TO biblioteca;

-- ---------------------------------------------------------------
-- 1. EVIDENCIA (antes): compara el estado guardado con el estado calculado
--    a partir de las fechas y de la tabla devolucion.
--    Si hay filas con guardado <> calculado, el dato derivado se desincronizo
--    y por eso se elimina.
-- ---------------------------------------------------------------
\echo '=== ANTES: estado guardado vs estado calculado ==='
SELECT p.estado AS estado_guardado,
       CASE
         WHEN d.id_prestamo IS NOT NULL          THEN 'devuelto'
         WHEN p.fecha_vencimiento < current_date THEN 'vencido'
         ELSE 'activo'
       END AS estado_calculado,
       count(*) AS prestamos
FROM prestamo p
LEFT JOIN devolucion d ON d.id_prestamo = p.id_prestamo
GROUP BY 1, 2
ORDER BY 1, 2;

SELECT count(*) AS prestamos_antes FROM prestamo;

BEGIN;

-- ---------------------------------------------------------------
-- 2. Eliminar la columna derivada y su restriccion
-- ---------------------------------------------------------------
ALTER TABLE prestamo DROP CONSTRAINT ck_prestamo_estado;
ALTER TABLE prestamo DROP COLUMN estado;

-- ---------------------------------------------------------------
-- 3. Vista que reemplaza a prestamo.estado (se calcula al consultar)
-- ---------------------------------------------------------------
CREATE VIEW v_prestamo_estado AS
SELECT p.*,
       CASE
         WHEN d.id_prestamo IS NOT NULL          THEN 'devuelto'
         WHEN p.fecha_vencimiento < current_date THEN 'vencido'
         ELSE 'activo'
       END AS estado
FROM prestamo p
LEFT JOIN devolucion d ON d.id_prestamo = p.id_prestamo;

-- ---------------------------------------------------------------
-- 4. Vista de verificacion de la desnormalizacion ejemplar.estado
--    (0 filas = la copia esta al dia)
-- ---------------------------------------------------------------
CREATE VIEW v_descuadre_ejemplar AS
SELECT e.id_ejemplar,
       e.estado AS estado_guardado,
       EXISTS (SELECT 1 FROM prestamo p
               WHERE p.id_ejemplar = e.id_ejemplar
                 AND NOT EXISTS (SELECT 1 FROM devolucion d
                                 WHERE d.id_prestamo = p.id_prestamo)) AS tiene_prestamo_abierto
FROM ejemplar e
WHERE (e.estado = 'prestado'
       AND NOT EXISTS (SELECT 1 FROM prestamo p
                       WHERE p.id_ejemplar = e.id_ejemplar
                         AND NOT EXISTS (SELECT 1 FROM devolucion d
                                         WHERE d.id_prestamo = p.id_prestamo)))
   OR (e.estado = 'disponible'
       AND EXISTS (SELECT 1 FROM prestamo p
                   WHERE p.id_ejemplar = e.id_ejemplar
                     AND NOT EXISTS (SELECT 1 FROM devolucion d
                                     WHERE d.id_prestamo = p.id_prestamo)));

COMMIT;

-- ---------------------------------------------------------------
-- 5. VERIFICACION (despues)
-- ---------------------------------------------------------------
\echo '=== DESPUES: conteo de prestamos (debe ser igual al de antes) ==='
SELECT count(*) AS prestamos_despues FROM prestamo;

\echo '=== DESPUES: estado calculado por la vista ==='
SELECT estado, count(*) AS prestamos FROM v_prestamo_estado GROUP BY estado ORDER BY estado;

\echo '=== DESPUES: ejemplares descuadrados (debe devolver 0 filas) ==='
SELECT * FROM v_descuadre_ejemplar;
