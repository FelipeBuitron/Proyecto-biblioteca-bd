-- entregas/S16/consultas.sql
-- Consultas base de los 4 reportes del sistema de biblioteca (Hito 2).
--
-- Criterio de mora usado en todas las consultas:
--   un prestamo esta EN MORA si no tiene devolucion y su fecha_vencimiento
--   ya paso (fecha_vencimiento < current_date). Se calcula a partir de las
--   fechas y de la tabla devolucion; NO se usa prestamo.estado, porque ese
--   campo se puede desactualizar (nadie lo cambia solo cuando pasa la fecha).
--
-- Uso (desde entorno-docker/, con el archivo copiado a postgres/scripts/):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/consultas.sql

SET search_path TO biblioteca;

-- ==========================================================================
-- REPORTE 1: los 20 libros mas prestados
-- Que hace: cuenta cuantos prestamos ha tenido cada libro (sumando todas sus
--   copias, porque el prestamo apunta a un ejemplar y el ejemplar a un libro)
--   y devuelve los 20 con mas prestamos. Cuentan los prestamos abiertos y los
--   devueltos. Si hay empate, se ordena por titulo para que el resultado sea
--   siempre el mismo. Los libros que nunca se han prestado no aparecen.
-- ==========================================================================
\echo
\echo '=== REPORTE 1: 20 libros mas prestados ==='
SELECT l.isbn,
       l.titulo,
       l.autor,
       count(*) AS total_prestamos
FROM prestamo p
JOIN ejemplar e ON e.id_ejemplar = p.id_ejemplar
JOIN libro    l ON l.isbn = e.isbn
GROUP BY l.isbn, l.titulo, l.autor
ORDER BY total_prestamos DESC, l.titulo
LIMIT 20;

-- ==========================================================================
-- REPORTE 2: usuario(s) que mas libros ha(n) leido
-- Que hace: cuenta, por lector, los prestamos COMPLETADOS (los que tienen
--   devolucion). Los prestamos abiertos no cuentan, para no premiar a quien
--   solo tiene muchos libros retenidos (regla 3.2). Devuelve a todos los
--   lectores que empatan en el maximo, no solo a uno.
-- ==========================================================================
\echo
\echo '=== REPORTE 2: usuario(s) que mas ha(n) leido ==='
WITH lecturas AS (
    SELECT u.id_usuario,
           u.documento,
           u.nombre,
           count(*) AS libros_leidos
    FROM prestamo p
    JOIN devolucion d ON d.id_prestamo = p.id_prestamo
    JOIN usuario    u ON u.id_usuario  = p.id_lector
    GROUP BY u.id_usuario, u.documento, u.nombre
)
SELECT documento, nombre, libros_leidos
FROM lecturas
WHERE libros_leidos = (SELECT max(libros_leidos) FROM lecturas)
ORDER BY nombre;

-- ==========================================================================
-- REPORTE 3: lista de usuarios morosos
-- Que hace: lista cada lector con al menos un prestamo vencido y no devuelto.
--   Aparece una sola vez por lector, con cuantos prestamos tiene en mora y
--   los dias del mas atrasado. Los mas atrasados salen primero.
-- ==========================================================================
\echo
\echo '=== REPORTE 3: usuarios morosos ==='
SELECT u.documento,
       u.nombre,
       count(*)                                  AS prestamos_en_mora,
       max(current_date - p.fecha_vencimiento)   AS dias_mora_maximo
FROM prestamo p
JOIN usuario u ON u.id_usuario = p.id_lector
LEFT JOIN devolucion d ON d.id_prestamo = p.id_prestamo
WHERE d.id_prestamo IS NULL
  AND p.fecha_vencimiento < current_date
GROUP BY u.id_usuario, u.documento, u.nombre
ORDER BY dias_mora_maximo DESC, u.nombre;

-- ==========================================================================
-- REPORTE 4: notificacion de prestamos en mora
-- Que hace: una fila POR PRESTAMO en mora, con los datos de contacto del
--   lector (nombre, correo, telefono), el libro y los dias de atraso. Es la
--   lista que mostrara la aplicacion junto al boton "Enviar notificacion",
--   que no ejecuta ningun envio real (nota de alcance de la seccion 3.1).
--   A diferencia del reporte 3, un lector con 2 prestamos en mora sale 2 veces.
-- ==========================================================================
\echo
\echo '=== REPORTE 4: notificacion de prestamos en mora ==='
SELECT p.id_prestamo,
       u.nombre,
       u.correo,
       u.telefono,
       l.titulo,
       p.fecha_vencimiento,
       current_date - p.fecha_vencimiento AS dias_mora
FROM prestamo p
JOIN usuario  u ON u.id_usuario   = p.id_lector
JOIN ejemplar e ON e.id_ejemplar  = p.id_ejemplar
JOIN libro    l ON l.isbn         = e.isbn
LEFT JOIN devolucion d ON d.id_prestamo = p.id_prestamo
WHERE d.id_prestamo IS NULL
  AND p.fecha_vencimiento < current_date
ORDER BY dias_mora DESC, u.nombre;
