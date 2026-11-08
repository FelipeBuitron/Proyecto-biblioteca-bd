-- datos-prueba.sql
-- Datos de prueba para que los 4 reportes devuelvan resultados.
-- REQUISITO: haber cargado antes libros_semilla.csv y lectores_semilla.csv
--            (carga-libros.sql y carga-lectores.sql con sus valores por defecto).
--
-- Uso (desde entorno-docker/):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/datos-prueba.sql
--
-- Las fechas son RELATIVAS a la fecha actual (current_date), asi que los
-- prestamos "en mora" siguen en mora cuando se vuelva a correr. Los dias de
-- mora que muestran los reportes cambian con el tiempo.
-- Se puede correr varias veces: si ya hay prestamos, no inserta otros.

\set ON_ERROR_STOP on
SET search_path TO biblioteca;

BEGIN;

-- 1. Personal de la biblioteca (la carga de lectores solo crea lectores)
INSERT INTO usuario (documento, nombre, direccion, telefono, correo, rol) VALUES
 ('2000000001', 'Carolina Mejía Soto',  'Calle 5 # 10-20, Cali',  '3002000001', 'carolina.mejia@biblioteca-ejemplo.edu.co',  'bibliotecario'),
 ('2000000002', 'Ricardo Núñez Pardo',  'Carrera 8 # 3-45, Cali', '3002000002', 'ricardo.nunez@biblioteca-ejemplo.edu.co',   'bibliotecario'),
 ('2000000003', 'Elena Prado Ríos',     'Avenida 6 # 20-10, Cali','3002000003', 'elena.prado@biblioteca-ejemplo.edu.co',     'administrador'),
 ('2000000004', 'Héctor Salazar Mora',  'Calle 9 # 4-30, Cali',   '3002000004', 'hector.salazar@biblioteca-ejemplo.edu.co',  'auditor')
ON CONFLICT (documento) DO NOTHING;

-- 2. Plan de prestamos (tabla temporal; desaparece al cerrar la sesion)
--    dias_atras     : hace cuantos dias se presto
--    dias_plazo     : dias de plazo (14 = regla por defecto)
--    devuelto_tras  : dias despues del prestamo en que se devolvio (NULL = sigue abierto)
CREATE TEMP TABLE plan_prestamo (
    doc_lector    text,
    id_ejemplar   text,
    dias_atras    integer,
    dias_plazo    integer,
    devuelto_tras integer
);

INSERT INTO plan_prestamo VALUES
 -- Prestamos ya devueltos (completados)
 ('1000000001', '9780000000001-1', 60, 14, 10),
 ('1000000001', '9780000000014-1', 50, 14, 12),
 ('1000000001', '9780000000017-1', 40, 14, 13),
 ('1000000001', '9780000000032-1', 30, 14,  9),
 ('1000000002', '9780000000001-2', 55, 14, 14),
 ('1000000002', '9780000000014-2', 45, 14,  8),
 ('1000000002', '9780000000009-1', 35, 14, 10),
 ('1000000003', '9780000000014-3', 48, 14,  7),
 ('1000000003', '9780000000032-2', 28, 14, 12),
 ('1000000003', '9780000000017-3', 70, 14, 20),  -- devuelto tarde (pero devuelto)
 ('1000000004', '9780000000001-3', 52, 14,  5),
 ('1000000004', '9780000000017-2', 33, 14,  6),
 ('1000000005', '9780000000032-3', 25, 14, 10),
 ('1000000006', '9780000000014-4', 20, 14,  3),
 ('1000000007', '9780000000009-2', 22, 14,  9),
 -- Prestamos abiertos y vigentes (no vencidos)
 ('1000000008', '9780000000014-5',  5, 14, NULL),
 ('1000000009', '9780000000001-4',  3, 14, NULL),
 ('1000000010', '9780000000032-4',  7, 14, NULL),
 ('1000000010', '9780000000004-1',  2, 14, NULL),
 -- Prestamos abiertos y vencidos (en mora)
 ('1000000011', '9780000000014-6', 30, 14, NULL),
 ('1000000012', '9780000000009-3', 25, 14, NULL),
 ('1000000013', '9780000000017-4', 21, 14, NULL),
 ('1000000013', '9780000000032-5', 20, 14, NULL),  -- el mismo lector con 2 prestamos en mora
 ('1000000014', '9780000000005-1', 40, 14, NULL);

-- 3. Prestamos: los registra la bibliotecaria Carolina (solo si aun no hay prestamos)
INSERT INTO prestamo (id_ejemplar, id_lector, id_bibliotecario,
                      fecha_prestamo, fecha_vencimiento, estado)
SELECT p.id_ejemplar,
       l.id_usuario,
       b.id_usuario,
       current_date - p.dias_atras,
       current_date - p.dias_atras + p.dias_plazo,
       CASE
         WHEN p.devuelto_tras IS NOT NULL                 THEN 'devuelto'
         WHEN current_date - p.dias_atras + p.dias_plazo < current_date THEN 'vencido'
         ELSE 'activo'
       END
FROM plan_prestamo p
JOIN usuario l ON l.documento = p.doc_lector
JOIN usuario b ON b.documento = '2000000001'
WHERE NOT EXISTS (SELECT 1 FROM prestamo);

-- 4. Devoluciones: las registra el bibliotecario Ricardo
INSERT INTO devolucion (id_prestamo, id_bibliotecario, fecha_devolucion)
SELECT pr.id_prestamo,
       b.id_usuario,
       pr.fecha_prestamo + p.devuelto_tras
FROM plan_prestamo p
JOIN usuario l   ON l.documento = p.doc_lector
JOIN prestamo pr ON pr.id_ejemplar = p.id_ejemplar
                AND pr.id_lector = l.id_usuario
                AND pr.fecha_prestamo = current_date - p.dias_atras
JOIN usuario b   ON b.documento = '2000000002'
WHERE p.devuelto_tras IS NOT NULL
ON CONFLICT (id_prestamo) DO NOTHING;

-- 5. Los ejemplares con prestamo abierto quedan en estado 'prestado'
UPDATE ejemplar e SET estado = 'prestado'
WHERE EXISTS (SELECT 1 FROM prestamo pr
              WHERE pr.id_ejemplar = e.id_ejemplar
                AND NOT EXISTS (SELECT 1 FROM devolucion d WHERE d.id_prestamo = pr.id_prestamo));

DROP TABLE plan_prestamo;

COMMIT;

-- Resumen
SELECT (SELECT count(*) FROM prestamo)   AS prestamos,
       (SELECT count(*) FROM devolucion) AS devoluciones,
       (SELECT count(*) FROM ejemplar WHERE estado = 'prestado') AS ejemplares_prestados;
