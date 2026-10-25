# REPORTE TÉCNICO DE RENDIMIENTO Y OPTIMIZACIÓN DE ÍNDICES

**Módulo:** Gestión de Transacciones, Pagos e Inventario

**Propietaria: Keilyn**

**Técnica Evaluada:** Indexación Condicional / Parcial (`EXPLAIN ANALYZE`)

## 1. Propósito del Módulo

El módulo de **Gestión de Transacciones, Pagos e Inventario** es el núcleo transaccional del sistema de boletería. Sus objetivos principales son:

* **Garantizar la Atomicidad y Consistencia:** Controlar las reservas de asientos, compras y emisión de boletos evitando ventas duplicadas y reservas concurrentes sobre una misma función.

* **Procesamiento de Pagos:** Registrar las pasarelas de pago (aprobaciones, rechazos y anulaciones) asegurando la integridad de los fondos y actualizando el inventario en tiempo real.

* **Generación de Reportes Financieros y Métricas:** Proveer a los administradores consultas rápidas sobre montos totales cobrados, ventas por rango de fechas e histórico de transacciones del usuario.

Para mantener una experiencia de usuario óptima y un sistema eficiente, las consultas frecuentes de reportes financieros no deben ralentizar el rendimiento general de la base de datos a medida que la tabla de pagos crece.

## 2. Metodología de Pruebas de Rendimiento

Para simular un entorno de producción con un volumen realista de transacciones, se poblaron las tablas principales con una carga sintética masiva:

* **Volumen de Prueba:** \~100,000 registros insertados en las tablas `compra`, `compra_detalle`, `pago` y `boleto`.

* **Caso de Uso Evaluado:** Consulta analítica frecuente utilizada en tableros de control y reportes administrativos: *Calcular el número total de pagos aprobados y la suma acumulada de ingresos en los últimos 7 días.*

* **Herramienta de Medición:** `EXPLAIN (ANALYZE, BUFFERS)` de PostgreSQL para analizar el tiempo de ejecución real, el costo de entrada/salida (I/O) de bloques en memoria compartida y el algoritmo de búsqueda empleado por el optimizador.

## 3. Resultados de la Evaluación (`EXPLAIN ANALYZE`)

### Escenario A: Sin Índice (Consulta Baseline)

```
SELECT count(*) AS pagos, SUM(monto) AS total
  FROM pago
 WHERE estado = 'Aprobado'
   AND creado_en >= now() - interval '7 days';

```

* **Estrategia del Motor:** Escaneo Secuencial (`Seq Scan on pago`).

* **Filas Descartadas:** 98,064 filas evaluadas e ignoradas por no cumplir los criterios de filtrado.

* **Bloques Leídos en Memoria:** 1,235 bloques compartidos.

* **Tiempo Total de Ejecución:** **37.836 ms**

#### Análisis Técnico:

Sin una estructura de acceso rápido, el motor de PostgreSQL está obligado a leer fila por fila toda la tabla física de `pago`. A medida que el volumen pase de 100,000 a millones de filas, este comportamiento degradará de forma lineal ($O(N)$) el tiempo de respuesta y saturará el I/O del disco.

### Escenario B: Con Índice Parcial (`idx_pago_aprobado_fecha`)

Para resolver el cuello de botella se definió un **índice B-Tree parcial**, que solo indexa los registros en estado `'Aprobado'`:

```
CREATE INDEX idx_pago_aprobado_fecha
    ON pago (creado_en)
 WHERE estado = 'Aprobado';

```

* **Estrategia del Motor:** Búsqueda mediante Índice Bitmap (`Bitmap Index Scan` + `Bitmap Heap Scan`).

* **Filas Reales Evaluadas:** Únicamente las 1,933 filas que cumplían exactamente los criterios.

* **Bloques Leídos en Memoria:** 979 bloques compartidos.

* **Tiempo Total de Ejecución:** **2.604 ms**

#### Análisis Técnico:

El motor utiliza una estructura de árbol ($O(\log N)$) para localizar directamente las páginas donde residen los pagos aprobados recientes, reduciendo significativamente el tiempo de consulta y el número de lecturas necesarias en disco.

## 4. Cuadro Comparativo de Métricas

| Métrica | Sin Índice (`Seq Scan`) | Con Índice (`Bitmap Index Scan`) | Mejora / Impacto |
| ----- | ----- | ----- | ----- |
| **Estrategia** | Recorrido total tabla | Acceso condicional directo | Optimización de algoritmo |
| **Filas Analizadas** | \~100,000 | 1,933 | Reducción del 98% en filas escaneadas |
| **Tiempo de Ejecución** | **37.836 ms** | **2.604 ms** | **\~14.5 veces más rápido (93.1% de reducción)** |
| **Consumo de I/O** | 1,235 bloques | 979 bloques | Reducción de carga en la memoria búfer |

## 5. Conclusión y Justificación Técnica

### ¿Es mejor implementar el índice?

**Sí, es indispensable para la salud del sistema.**

Las razones clave que justifican su presencia en producción son:

1. **Eficiencia en Recursos:** Al reducir en más de un 93% el tiempo de ejecución, se libera capacidad de procesamiento de CPU y se minimiza la competencia por memoria durante picos de tráfico en la boletería.

2. **Uso de Índices Parciales (Estrategia Eficiente):** El índice no abarca toda la tabla sino solo los registros donde `estado = 'Aprobado'`. Esto ahorra espacio en disco y reduce el costo de mantenimiento del índice durante las operaciones de inserción (`INSERT`), a la vez que atiende las consultas más comunes.

3. **Escalabilidad del Sistema:** Sin este índice, un crecimiento continuo de la tabla `pago` generaría bloqueos e inestabilidad en las consultas analíticas del módulo. Con el índice, el tiempo de respuesta se mantiene estable en el rango de milisegundos.
