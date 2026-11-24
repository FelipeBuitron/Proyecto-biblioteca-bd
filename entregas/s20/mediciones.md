# Hito 3 – Mediciones S20
## Responsable: A1 y A3

# A1. Consulta de catálogo normalizada

Se ejecutó la consulta de catálogo utilizando las tablas `libro`, `ejemplar` y `prestamo`, con `EXPLAIN ANALYZE` tres veces y sin índices adicionales a los de las llaves primarias.

### Resultados de las mediciones

| Ejecución | Tiempo de ejecución |
|---|---:|
| 1 | 21.157 ms |
| 2 | 17.712 ms |
| 3 | 16.601 ms |
| **Promedio** | **18.490 ms** |

### Análisis del plan de ejecución

- El nodo que más tiempo consume es `Seq Scan on prestamo p`.
- En la primera ejecución, este nodo presentó un tiempo de 17.617 a 17.945 ms.
- Se descartaron 300.000 filas porque correspondían a préstamos que ya tenían fecha de devolución.
- En el filtro de títulos se descartaron 4.889 libros y se encontraron 111 que cumplían la condición.

### Preguntas

**¿Por qué se utiliza LEFT JOIN?**

Porque permite conservar todos los ejemplares, incluso aquellos que no tienen préstamos activos. De esta manera se pueden contar correctamente los ejemplares disponibles.

**¿Por qué se utiliza COUNT(p.id)?**

Porque cuenta únicamente los préstamos existentes. Los valores NULL generados por el LEFT JOIN no se cuentan.

### Conclusión de A1

La consulta normalizada funciona correctamente, pero necesita relacionar varias tablas y revisar una gran cantidad de registros de préstamos. Esto aumenta el tiempo de ejecución.

---

# A3. Desnormalización y rendimiento

## A3 (a). Agregar la columna disponibles

Se agregó la columna `disponibles` a la tabla `libro`, con las siguientes características:

- Tipo de dato entero.
- Restricción `NOT NULL`.
- Valor inicial de 0.
- Restricción CHECK para evitar valores negativos.

Posteriormente, se realizó un UPDATE para calcular la cantidad de ejemplares que no tenían préstamos activos.

### Predicción inicial

Se esperaba obtener:

| Ejemplares disponibles | Cantidad de libros |
|---:|---:|
| 3 | 1.250 |
| 2 | 3.750 |
| **Total** | **5.000** |

### Resultado obtenido

La consulta de verificación confirmó exactamente los valores esperados:

| Ejemplares disponibles | Cantidad de libros |
|---:|---:|
| 3 | 1.250 |
| 2 | 3.750 |

La predicción coincidió con los resultados de la base de datos.

## A3 (b). Medición de rendimiento con desnormalización

Se ejecutó la consulta utilizando directamente la columna `disponibles`, sin realizar JOIN entre las tablas de ejemplares y préstamos.

### Resultados de las mediciones

| Ejecución | Tiempo de ejecución |
|---|---:|
| 1 | 0.391 ms |
| 2 | 0.458 ms |
| 3 | 0.524 ms |
| **Promedio** | **0.458 ms** |

### Análisis del plan de ejecución

- PostgreSQL utilizó el nodo `Seq Scan on libro`.
- Se encontraron 111 libros.
- Se descartaron 4.889 libros que no cumplían el filtro del título.
- La consulta ya no necesitó relacionar las tablas `ejemplar` y `prestamo`.

### Comparación entre A1 y A3

| Consulta | Tiempo promedio |
|---|---:|
| A1 – Normalizada | 18.490 ms |
| A3 – Desnormalizada | 0.458 ms |

La consulta desnormalizada fue aproximadamente 40 veces más rápida que la consulta normalizada en las mediciones realizadas.

### Conclusión de A3 (b)

La desnormalización mejoró considerablemente el rendimiento porque permite consultar directamente la cantidad de ejemplares disponibles, evitando realizar varias relaciones entre tablas.

## A3 (c). Detección de desincronización

Se simuló el registro de un préstamo sin actualizar la columna `disponibles` de la tabla `libro`.

Se registró el préstamo del ejemplar número 1 mediante el siguiente comando:

`INSERT INTO prestamo VALUES (400001, 1, '1000000001', CURRENT_DATE, CURRENT_DATE + 14, NULL);`

Después se creó la vista `descuadre`, encargada de comparar los ejemplares disponibles guardados con los calculados a partir de los préstamos activos.

### Resultado obtenido

| ISBN | Libro | Guardados | Calculados |
|---|---|---:|---:|
| 9780000000001 | Libro 1 | 3 | 2 |

La vista detectó correctamente la inconsistencia.

Esto ocurrió porque se registró un préstamo, pero no se actualizó la cantidad de ejemplares disponibles del libro.

## A3 (d). Mecanismo de consistencia

Para evitar este tipo de inconsistencias se pueden utilizar dos mecanismos:

1. **Triggers:** permiten actualizar automáticamente la cantidad de ejemplares disponibles cuando se registra o devuelve un préstamo.
2. **Transacciones desde la aplicación:** permiten realizar el registro del préstamo y la actualización de los ejemplares disponibles dentro de una misma transacción.

De esta manera se evita que una operación se complete sin actualizar la información relacionada.

### Conclusión general

La desnormalización permite mejorar el rendimiento de las consultas, como se demostró en las mediciones de A1 y A3. Sin embargo, también genera el riesgo de que la información almacenada se desincronice.

Por eso es importante implementar mecanismos que mantengan la consistencia de los datos.