-- 01_esquema.sql  (Hito 3: esquema normalizado)
-- Va en postgres/init/: se ejecuta solo al crear la base vacia.
-- Prueba sin borrar la base del grupo:
--   docker compose exec postgres psql -U curso -c "CREATE DATABASE prueba_init;" -d curso
--   docker compose exec postgres psql -U curso -d prueba_init -f /docker-entrypoint-initdb.d/01_esquema.sql
--
-- CAMBIO DEL HITO 3: se elimino prestamo.estado (dato derivado que podia
-- contradecir a las fechas y a la tabla devolucion). Ahora se calcula con la
-- vista v_prestamo_estado. Ver el documento de normalizacion.

DROP SCHEMA IF EXISTS biblioteca CASCADE;
CREATE SCHEMA biblioteca;
SET search_path TO biblioteca;

-- ---------------------------------------------------------------
-- libro: entidad fuerte, PK = isbn
-- ---------------------------------------------------------------
CREATE TABLE libro (
    isbn      varchar(13) PRIMARY KEY,
    titulo    varchar     NOT NULL,
    autor     varchar     NOT NULL,
    editorial varchar,                -- CAMBIO 1: opcional, el CSV semilla no trae editorial
    categoria varchar,                -- CAMBIO 2: agregada, el CSV trae categoria y el diagrama no
    ano       integer     NOT NULL,
    CONSTRAINT ck_libro_isbn   CHECK (isbn ~ '^[0-9]{13}$'),
    CONSTRAINT ck_libro_titulo CHECK (titulo <> ''),
    CONSTRAINT ck_libro_autor  CHECK (autor <> ''),
    CONSTRAINT ck_libro_ano    CHECK (ano BETWEEN 1450 AND 2100)
);

-- ---------------------------------------------------------------
-- ejemplar: una fila por copia fisica (relacion 1:N con libro)
-- estado: desnormalizacion deliberada (ver documento de normalizacion).
--   'prestado' se puede deducir de si hay un prestamo abierto; se guarda para
--   consultar la disponibilidad sin recorrer prestamo. 'danado' y 'perdido'
--   no se deducen de otra tabla. Se verifica con v_descuadre_ejemplar y se
--   mantendra con un trigger (Hito 4).
-- ---------------------------------------------------------------
CREATE TABLE ejemplar (
    id_ejemplar varchar PRIMARY KEY,   -- p. ej. '9780000000001-1'
    isbn        varchar(13) NOT NULL REFERENCES libro (isbn),
    estado      varchar     NOT NULL DEFAULT 'disponible',
    CONSTRAINT ck_ejemplar_estado
        CHECK (estado IN ('disponible', 'prestado', 'danado', 'perdido'))
);

-- ---------------------------------------------------------------
-- usuario: una sola tabla con columna rol (opcion 1 de S11)
-- ---------------------------------------------------------------
CREATE TABLE usuario (
    id_usuario integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    documento  varchar UNIQUE,          -- CAMBIO 3: agregada, el CSV de lectores trae documento
    nombre     varchar NOT NULL,
    direccion  varchar,
    telefono   varchar,
    correo     varchar UNIQUE,
    rol        varchar NOT NULL,
    CONSTRAINT ck_usuario_rol
        CHECK (rol IN ('lector', 'bibliotecario', 'administrador', 'auditor')),
    CONSTRAINT ck_usuario_documento CHECK (documento IS NULL OR documento ~ '^[0-9]{6,15}$'),
    CONSTRAINT ck_usuario_correo CHECK (correo IS NULL OR correo LIKE '%_@_%')
);

-- ---------------------------------------------------------------
-- cuenta: credenciales de acceso (1:1 con usuario)
-- ---------------------------------------------------------------
CREATE TABLE cuenta (
    id_cuenta      integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_usuario varchar NOT NULL UNIQUE,
    contrasena     varchar NOT NULL,   -- guardar SIEMPRE con hash, nunca en texto plano
    id_usuario     integer NOT NULL UNIQUE REFERENCES usuario (id_usuario),
    creada_por     integer REFERENCES cuenta (id_cuenta)   -- autorreferencia
);

-- ---------------------------------------------------------------
-- prestamo
-- fecha_vencimiento se conserva como dato historico: es el plazo acordado en
-- ese prestamo (puede cambiar la regla de 14 dias o haber plazos especiales).
-- ---------------------------------------------------------------
CREATE TABLE prestamo (
    id_prestamo       integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_ejemplar       varchar NOT NULL REFERENCES ejemplar (id_ejemplar),
    id_lector         integer NOT NULL REFERENCES usuario (id_usuario),
    id_bibliotecario  integer NOT NULL REFERENCES usuario (id_usuario),
    fecha_prestamo    date    NOT NULL,
    fecha_vencimiento date    NOT NULL,
    CONSTRAINT ck_prestamo_fechas CHECK (fecha_vencimiento >= fecha_prestamo)
);

-- ---------------------------------------------------------------
-- devolucion: como mucho una por prestamo
-- ---------------------------------------------------------------
CREATE TABLE devolucion (
    id_devolucion    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_prestamo      integer NOT NULL UNIQUE REFERENCES prestamo (id_prestamo),
    id_bibliotecario integer NOT NULL REFERENCES usuario (id_usuario),
    fecha_devolucion date    NOT NULL
);

-- ---------------------------------------------------------------
-- Vista: estado calculado del prestamo (reemplaza a prestamo.estado)
--   devuelto : tiene devolucion
--   vencido  : sin devolucion y la fecha de vencimiento ya paso (mora)
--   activo   : sin devolucion y aun dentro del plazo
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
-- Vista de verificacion de la desnormalizacion ejemplar.estado:
-- devuelve los ejemplares cuyo estado guardado no coincide con los prestamos.
-- Si devuelve 0 filas, la copia esta al dia.
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

-- ---------------------------------------------------------------
-- REGLAS QUE EL ESQUEMA NO CUBRE (para M6 / triggers):
--  1. prestamo.id_lector debe ser un usuario con rol = 'lector'.
--  2. prestamo.id_bibliotecario y devolucion.id_bibliotecario deben tener rol = 'bibliotecario'.
--  3. fecha_devolucion no debe ser anterior a fecha_prestamo (esta en otra tabla).
--  4. Un ejemplar no puede tener dos prestamos activos a la vez.
--  5. ejemplar.estado debe pasar a 'prestado' al crear el prestamo y a 'disponible' al devolver.
--  6. Todo libro deberia tener al menos un ejemplar.
--  7. La contrasena debe guardarse con hash (pgcrypto), no en texto plano.
-- ---------------------------------------------------------------
