# Hito 3: Documento de normalización

**Curso:** Bases de Datos · Universidad del Valle · **Grupo:** 3
**Integrantes:** Juan David Ramírez Arriaga · Miguel Ángel Lasso Troncoso · Andrés Felipe Escobar Buitrón · Sebastián Arango Belalcázar

---

## 1. Esquema antes (Hito 2)

Seis tablas del esquema `biblioteca`: `libro`, `ejemplar`, `usuario`, `cuenta`, `prestamo` y `devolucion`. Las tablas `stg_*` y `rechazo_carga` del esquema `carga` son de apoyo para la carga de CSV y no forman parte del modelo.

## 2. Dependencias funcionales y claves candidatas

Notación: `X → Y` significa que el valor de X determina el de Y.

| Tabla | Claves candidatas | Dependencias funcionales (con su regla) |
|---|---|---|
| `libro` | `isbn` | `isbn → titulo, autor, editorial, categoria, ano`. Un ISBN identifica una sola edición con esos datos |
| `ejemplar` | `id_ejemplar` | `id_ejemplar → isbn, estado`. Cada copia física pertenece a un solo libro y tiene un solo estado |
| `usuario` | `id_usuario`, `documento`, `correo` | `id_usuario → documento, nombre, direccion, telefono, correo, rol`. `documento` y `correo` son únicos, así que también determinan a todos los demás atributos |
| `cuenta` | `id_cuenta`, `nombre_usuario`, `id_usuario` | `id_cuenta → nombre_usuario, contrasena, id_usuario, creada_por`. `nombre_usuario` e `id_usuario` son únicos (relación 1:1 con `usuario`) |
| `prestamo` | `id_prestamo` | `id_prestamo → id_ejemplar, id_lector, id_bibliotecario, fecha_prestamo, fecha_vencimiento (, estado en el Hito 2)` |
| `devolucion` | `id_devolucion`, `id_prestamo` | `id_devolucion → id_prestamo, id_bibliotecario, fecha_devolucion`. `id_prestamo` es único (a lo sumo una devolución por préstamo) |

Todas las claves primarias son de **una sola columna**, así que no puede haber dependencias parciales.

## 3. Forma normal de cada tabla y problemas encontrados

| Tabla | Forma normal | Observaciones |
|---|---|---|
| `libro` | FNBC | El único determinante es la clave `isbn` |
| `ejemplar` | FNBC | El único determinante es la clave `id_ejemplar`. Observación: el identificador tiene el formato `isbn-número`, así que repite el ISBN dentro de su texto; no es una dependencia que rompa la normalización, pero un `CHECK` podría exigir que coincidan |
| `usuario` | FNBC | Todos los determinantes son claves. Observación de 1FN: `nombre` guarda nombres y apellidos juntos y se acepta por simplicidad, porque ninguna regla del sistema necesita consultarlos por separado |
| `cuenta` | FNBC | Todos los determinantes son claves |
| `devolucion` | FNBC | Todos los determinantes son claves |
| `prestamo` | 3FN, con dos hallazgos | Ver abajo |

### Hallazgos

**H1. `prestamo.estado` es un dato derivado.** Se deduce de si existe una devolución y de si `fecha_vencimiento` ya pasó, es decir, de datos de **otra tabla** y de la fecha actual. No viola la 3FN dentro de la tabla, pero causa una **anomalía de actualización**: nadie cambia el valor cuando pasa la fecha, y puede contradecir los datos reales (por ejemplo, 'activo' en un préstamo ya vencido).

*Evidencia (23 de noviembre de 2026, consulta "ANTES" de `normalizacion.sql`):* se comparó el `estado` guardado con el calculado a partir de la devolución y de la fecha de vencimiento.

| estado guardado | estado calculado | préstamos |
|---|---|---|
| activo | **vencido** | **4** |
| devuelto | devuelto | 15 |
| vencido | vencido | 5 |

4 de los 24 préstamos (17 %) quedaron guardados como `activo` cuando ya estaban vencidos: nadie actualizó la columna al pasar la fecha. Es la anomalía de actualización que justifica eliminarla.

**H2. `fecha_vencimiento` frente a `fecha_prestamo`.** Si el plazo fuera siempre de 14 días, `fecha_prestamo → fecha_vencimiento` sería una dependencia entre atributos que no son clave, que rompería la 3FN. Pero las reglas del sistema permiten cambiar el plazo o dar plazos especiales (sección 3.2 del enunciado), y el esquema solo exige `fecha_vencimiento >= fecha_prestamo`. Por eso no es una dependencia funcional del modelo.

## 4. Cambios aplicados

| Cambio | Cómo se migró |
|---|---|
| Se elimina `prestamo.estado` y su `CHECK` | `normalizacion.sql`: `ALTER TABLE … DROP COLUMN`. No se pierden datos |
| Se crea la vista `v_prestamo_estado` | Calcula `devuelto`, `vencido` o `activo` al consultar |

*Conteos antes y después:* 24 préstamos antes y 24 después, así que no se perdió ningún dato. Con la vista `v_prestamo_estado`, el estado calculado queda en 15 `devuelto` y 9 `vencido` (los 5 que ya estaban en mora más los 4 que habían quedado mal guardados como `activo`).

## 5. Desnormalizaciones deliberadas

| Dato | Decisión | Justificación |
|---|---|---|
| `prestamo.fecha_vencimiento` | Se conserva | Es el plazo **acordado en ese préstamo** (dato histórico). Calcularlo como `fecha_prestamo + 14` daría un resultado equivocado si cambia la regla o hay plazos especiales |
| `ejemplar.estado = 'prestado'` | Se conserva guardado | Se puede deducir de si hay un préstamo abierto, pero se guarda para consultar la disponibilidad sin recorrer `prestamo`. Además el campo guarda `danado` y `perdido`, que no se deducen de ninguna otra tabla |

**Medición:** el tiempo de la consulta de disponibilidad calculada frente a la que lee `ejemplar.estado` está en `entregas/S20/mediciones.md`, medido sobre el esquema `rendimiento` del taller S20 (303 750 préstamos).

**Mecanismo que lo mantiene consistente:** un trigger sobre `prestamo` y `devolucion` que cambia `ejemplar.estado` a `prestado` al registrar un préstamo y a `disponible` al registrar una devolución. Se implementa en el **Hito 4**. Mientras tanto, el dato lo actualiza `datos-prueba.sql`.

**Consulta de verificación:** la vista `v_descuadre_ejemplar` devuelve los ejemplares cuyo estado guardado no coincide con los préstamos abiertos. Si devuelve 0 filas, la copia está al día. Tras la migración devolvió **0 filas**.

## 6. Esquema después

El esquema actualizado está en `postgres/init/01_esquema.sql` y se comprobó en una base vacía (`prueba_init`). Todas las tablas quedan en FNBC, salvo `prestamo`, que queda en 3FN con la dependencia de `fecha_vencimiento` justificada en la sección 5.

Los cuatro reportes de S16 (`consultas.sql`) se corrieron sobre el esquema nuevo (salida completa en `entregas/S20/salida-consultas-hito3.txt`). Ninguna consulta usaba `prestamo.estado`, porque calculan la mora con las fechas y la tabla `devolucion`, así que no hubo que modificarlas.

- **Reportes 1 y 2:** sin cambios respecto a S16 (*1984* es el libro más prestado, con 6 préstamos; Mariana Gómez Rojas es la lectora con más libros devueltos, con 4).
- **Reportes 3 y 4:** cambian solo porque pasó el tiempo. Los 4 préstamos que el 8 de noviembre seguían vigentes ya vencieron. Hoy hay **7 lectores morosos** (antes 4) y **9 préstamos en mora** (antes 5), y los días de atraso de los demás subieron 15. Es el comportamiento correcto de una mora calculada y es justo lo que una columna guardada no habría hecho.
