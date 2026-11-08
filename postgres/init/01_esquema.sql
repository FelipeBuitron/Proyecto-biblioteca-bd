-- biblioteca-v2.sql  (BORRADOR a partir del diagrama "LAB 2 PROYECTO")
-- Ejecutar:
--   docker compose exec postgres psql -U curso -d curso -f /scripts/biblioteca-v2.sql

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
-- ---------------------------------------------------------------
CREATE TABLE prestamo (
    id_prestamo       integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_ejemplar       varchar NOT NULL REFERENCES ejemplar (id_ejemplar),
    id_lector         integer NOT NULL REFERENCES usuario (id_usuario),
    id_bibliotecario  integer NOT NULL REFERENCES usuario (id_usuario),
    fecha_prestamo    date    NOT NULL,
    fecha_vencimiento date    NOT NULL,
    estado            varchar NOT NULL DEFAULT 'activo',
    CONSTRAINT ck_prestamo_fechas CHECK (fecha_vencimiento >= fecha_prestamo),
    CONSTRAINT ck_prestamo_estado CHECK (estado IN ('activo', 'devuelto', 'vencido'))
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
-- REGLAS QUE EL ESQUEMA NO CUBRE (para M6 / triggers):
--  1. prestamo.id_lector debe ser un usuario con rol = 'lector'.
--  2. prestamo.id_bibliotecario y devolucion.id_bibliotecario deben tener rol = 'bibliotecario'.
--  3. fecha_devolucion no debe ser anterior a fecha_prestamo (esta en otra tabla).
--  4. Un ejemplar no puede tener dos prestamos activos a la vez.
--  5. ejemplar.estado debe pasar a 'prestado' al crear el prestamo.
--  6. Todo libro deberia tener al menos un ejemplar.
--  7. La contrasena debe guardarse con hash (pgcrypto), no en texto plano.
-- ---------------------------------------------------------------
