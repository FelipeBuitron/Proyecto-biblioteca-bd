# S14: Mapeo CSV → esquema y criterios por tipo de error

**Curso:** Bases de Datos · Universidad del Valle
**Grupo:** 3
**Integrantes:** Andres Escobar - Miguel Lasso - Sebastaian Arango - Juan David Ramirez

Esta carga sigue el patrón **tabla de paso → validación → tabla final → bitácora**, dentro de una transacción (`BEGIN … COMMIT`). Los scripts son `carga-libros.sql` y `carga-lectores.sql`; las tablas de paso y la bitácora (`rechazo_carga`) viven en el esquema `carga`, aparte del modelo (`biblioteca`).

---

## 1. Cambios al esquema respecto al diagrama del Hito 1

Para poder cargar los CSV semilla se hicieron tres ajustes al modelo:

| # | Cambio | Justificación |
|---|---|---|
| 1 | `libro.editorial` pasa de `NOT NULL` a opcional | El CSV de libros no trae editorial. Con `NOT NULL` ninguna fila podría cargarse. |
| 2 | Se agrega `libro.categoria` (opcional) | El CSV trae categoría y el diagrama no tenía dónde guardarla. |
| 3 | Se agrega `usuario.documento` (único, 6 a 15 dígitos) | El CSV de lectores trae documento. Es el dato que identifica a un lector y permite detectar duplicados. |

---

## 2. Mapeo CSV → esquema

### 2.1 `libros_semilla.csv` (6 columnas)

| Columna del CSV | Tabla.columna destino | Transformación | Regla de validación (motivo) |
|---|---|---|---|
| `isbn` | `libro.isbn` (y `ejemplar.isbn`) | `trim` | no vacío ("isbn vacío"); 13 dígitos ("isbn no tiene 13 dígitos"); no existe en el catálogo ("isbn ya existe en el catálogo"); no repetido en el archivo ("isbn repetido en el archivo") |
| `titulo` | `libro.titulo` | `trim` | no vacío ("título vacío") |
| `autor` | `libro.autor` | `trim` | no vacío ("autor vacío") |
| `categoria` | `libro.categoria` | `trim`; vacío pasa a `NULL` | ninguna (opcional) |
| `anio_publicacion` | `libro.ano` | `::integer` | solo dígitos ("año no numérico"); entre 1450 y 2100 ("año fuera de rango"); no mayor al año actual ("año en el futuro") |
| `ejemplares_disponibles` | `ejemplar` (n filas) | `generate_series(1, n)`; `id_ejemplar` = `isbn-número` (por ejemplo `9780000000001-2`); `estado` = `disponible` | entero ("ejemplares no numérico"); no negativo ("ejemplares negativo"); máximo 999 ("ejemplares demasiado grande (máx. 999)") |
| _(no viene en el CSV)_ | `libro.editorial` | queda en `NULL` | ninguna |
| _(estructura de la línea)_ | _(toda la fila)_ | `string_to_array` por coma | exactamente 6 campos ("tiene N columnas, se esperaban 6") |

### 2.2 `lectores_semilla.csv` (5 columnas)

| Columna del CSV | Tabla.columna destino | Transformación | Regla de validación (motivo) |
|---|---|---|---|
| `documento` | `usuario.documento` | `trim` | no vacío ("documento vacío"); 6 a 15 dígitos ("documento no numérico o de longitud inválida"); no existe ("documento ya existe") |
| `nombres` | `usuario.nombre` | `nombres \|\| ' ' \|\| apellidos` | no vacío ("nombres vacío") |
| `apellidos` | `usuario.nombre` | se une con `nombres` | no vacío ("apellidos vacío") |
| `correo` | `usuario.correo` | `trim` y `lower` | no vacío ("correo vacío"); formato `algo@algo.algo` ("correo mal formado"); no registrado ("correo ya registrado por otro usuario") |
| `telefono` | `usuario.telefono` | `trim` | 7 a 15 dígitos ("teléfono no numérico o de longitud inválida") |
| _(no viene en el CSV)_ | `usuario.rol` | valor fijo `'lector'` | ninguna |
| _(no viene en el CSV)_ | `usuario.direccion` | queda en `NULL` | ninguna |
| _(estructura de la línea)_ | _(toda la fila)_ | `string_to_array` por coma | exactamente 5 campos ("tiene N columnas, se esperaban 5") |
| `documento` y `correo` | _(duplicados dentro del archivo)_ | se conserva la primera aparición | "documento o correo repetido en el archivo" |

**Contraseña:** los lectores se cargan en `usuario` sin contraseña. Las credenciales viven en la tabla `cuenta` (columna `contrasena`, que se guardará con hash en el Hito 5), así que la carga no maneja contraseñas.

### 2.3 Restricciones del esquema y la regla que las cubre

Cada restricción del esquema tiene una regla equivalente en el `CASE` de validación. Así, una fila mala se rechaza con un motivo legible antes de llegar a la restricción.

| Restricción del esquema | Regla de validación que la cubre |
|---|---|
| `libro.isbn` PK y `ck_libro_isbn` (13 dígitos) | isbn vacío, isbn no tiene 13 dígitos, isbn ya existe |
| `libro.titulo` `NOT NULL` y `<> ''` | título vacío |
| `libro.autor` `NOT NULL` y `<> ''` | autor vacío |
| `libro.ano` `NOT NULL` y `ck_libro_ano` (1450 a 2100) | año no numérico, año fuera de rango, año en el futuro |
| `ejemplar.isbn` FK a `libro` | se genera solo desde ISBN ya validados |
| `usuario.documento` `UNIQUE` y `ck_usuario_documento` | documento vacío, inválido, ya existe |
| `usuario.nombre` `NOT NULL` | nombres vacío, apellidos vacío |
| `usuario.correo` `UNIQUE` y `ck_usuario_correo` | correo vacío, mal formado, ya registrado |

> **Nota:** "ejemplares negativo" no corresponde a ninguna restricción del esquema, porque la columna `ejemplares_disponibles` no existe en el modelo (las copias son filas de `ejemplar`). Esa regla solo existe en la validación de la carga.

---

## 3. Criterios por tipo de error

**Criterio general del grupo:** se **corrige** solo lo mecánico que no cambia el significado del dato (espacios sobrantes con `trim`, correo a minúsculas con `lower`). Todo lo demás se **rechaza y se registra** en la bitácora con archivo, línea, contenido original y motivo. **Nunca se actualiza** un registro existente: la carga es de altas, y por eso repetirla no duplica datos (las filas ya cargadas salen rechazadas).

### 3.1 Errores de `libros_semilla_con_errores.csv`

| Línea | Problema | Acción | Por qué |
|---|---|---|---|
| 2 | ISBN que ya existe en el catálogo | Rechazar | No es un alta nueva. No se actualiza para que la carga se pueda repetir sin duplicar. |
| 3 | Título vacío | Rechazar | El dato falta y no se puede adivinar. |
| 4 | Año no numérico (`dos`) | Rechazar | No se puede interpretar de forma segura. |
| 5 | Año no numérico (`MCMXLIX`) | Rechazar | Un número romano no se convierte automáticamente. |
| 6 | Siete columnas en vez de seis | Rechazar | La fila está mal formada y no se sabe qué campo sobra. |
| 7 | Autor vacío | Rechazar | El dato falta y es obligatorio. |
| 8 | ISBN vacío | Rechazar | Es la clave del libro; sin ella no hay forma de identificarlo. |
| 9 | Ejemplares negativo (`-3`) | Rechazar | Una cantidad negativa de copias no tiene sentido. |

### 3.2 Errores de `lectores_semilla_con_errores.csv`

| Línea | Problema | Acción | Por qué |
|---|---|---|---|
| 2 | Documento que ya existe | Rechazar | Evita crear un lector duplicado. |
| 3 | Correo vacío | Rechazar | El correo es necesario para contactar al lector. |
| 4 | Correo mal formado (sin `@`) | Rechazar | No se puede adivinar el correo correcto. |
| 5 | Teléfono no numérico (`tres-cero-cero`) | Rechazar | No se puede convertir de forma segura. |
| 6 | Documento vacío | Rechazar | Es el dato que identifica al lector. |
| 7 | Nombres vacío | Rechazar | El dato falta y es obligatorio. |

### 3.3 Casos que se corrigen en vez de rechazar

| Caso | Acción | Por qué |
|---|---|---|
| Espacios al inicio o al final de un campo | Corregir (`trim`) | Es mecánico y no cambia el significado. |
| Correo con mayúsculas | Corregir (`lower`) | `Ana@X.co` y `ana@x.co` son el mismo correo. |
| Categoría vacía | Cargar con `NULL` | La categoría es opcional en el modelo. |

### 3.4 Errores adicionales que el grupo agregó

Estos casos no aparecen en los archivos del curso. Se probaron con `libros_propio.csv`:

| Problema | Acción | Motivo registrado | Por qué |
|---|---|---|---|
| Mismo ISBN dos veces en el archivo | Rechazar la segunda aparición | isbn repetido en el archivo | Se conserva la primera. El ISBN aún no está en la tabla, así que la regla contra el catálogo no lo detecta. |
| Año en el futuro (2031) | Rechazar | año en el futuro | Un libro no puede haberse publicado después de hoy. |
| ISBN de 12 dígitos | Rechazar | isbn no tiene 13 dígitos | No se puede adivinar el dígito que falta. |

Reglas de apoyo que no aparecen en los archivos de prueba: "ejemplares demasiado grande (máx. 999)", "documento o correo repetido en el archivo" y "correo ya registrado por otro usuario".

---

## 4. Limitaciones conocidas

| Caso | Qué pasa con el script |
|---|---|
| Coma dentro de comillas (`"Libro, con coma"`) | Se parte en dos campos y la fila sale rechazada por columnas de más. |
| Archivo con `;` como separador (Excel en español) | Todas las filas salen rechazadas por "tiene 1 columnas". Es la pista para revisar el separador. |
| Finales de línea de Windows (CRLF) | Se manejan bien: `COPY` los reconoce solo. |

---

## 5. Resultado de las pruebas

| Carga | Archivo | Cargadas | Rechazadas |
|---|---|---|---|
| 1 | `libros_semilla.csv` | 32 | 0 |
| 2 | `libros_semilla_con_errores.csv` | 0 | 8 |
| 3 | `lectores_semilla_con_errores.csv` (con los 20 lectores limpios ya cargados) | 0 | 6 |
| 4 | `libros_propio.csv` | 5 | 3 |

Repetir la carga de un archivo ya cargado deja todas sus filas rechazadas por duplicado, sin duplicar datos.
