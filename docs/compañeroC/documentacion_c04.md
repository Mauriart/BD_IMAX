# Documentación técnica C-04 — Cuatro reportes SQL y dashboard operativo

**Issue:** [C-04 · #18](https://github.com/Mauriart/BD_IMAX/issues/18) · **Bloque:** C · **Versión:** 2.0 · 24 de octubre de 2026
**Reglas:** consultas analíticas mínimas de la consigna, RN-17, RN-20 y definiciones de [acuerdos §4 y §11](00_acuerdos.md).
**Sustituye** a la versión 1.0 (`documentaci_n_del_issue_c_04.md`) y al script `04_reembolsos_reportes_C04.sql`.

| Archivo | Ruta sugerida | Uso |
| --- | --- | --- |
| `c04_reportes.sql` | `sql/` | Cinco funciones de reporte con RBAC en el servidor. Idempotente, no modifica datos. |
| `c04_verificacion_reportes.sql` | `sql/` | 39 comprobaciones con dataset conocido; termina en `ROLLBACK`. |
| `c07_indices_c04.sql` | `sql/` | Índices propuestos. **No** se ejecutan con C-04 (ver §6). |
| `reportes_c04.py` | `src/operacion/` | Blueprint Flask del dashboard (solo lectura, exportación CSV). |
| `reportes_c04.html` | `src/templates/` | Plantilla del dashboard. |

---

## 1. Alcance corregido

El issue #18 pide **cuatro reportes SQL y un dashboard**. La versión 1.0 añadía una función de ejecución de reembolsos (`resolver_reembolso_transaccional`) que **no pertenece a C-04** y se retira:

- `resolver_reembolso` (C-03) ya existe en `imax.sql`, con permisos, política de horas, auditoría y llamada a `revertir_venta` (B).
- La función retirada duplicaba esa lógica y escribía directamente sobre tablas de B (`boleto`, `compra`, `inventario_funcion`), lo que contradice los acuerdos §5: *C no modifica arbitrariamente tablas de ventas* y no debe haber «una segunda versión» de una operación compartida.

## 2. Revisión del script original contra `imax.sql`

La base actualizada conserva las mismas 26 tablas y las mismas funciones que la versión anterior; no incorpora las tablas de B. Contra ese esquema real, el script original **fallaba al ejecutarse**:

| # | Problema | Corrección |
| --- | --- | --- |
| 1 | Usaba tablas que no existen: `pago`, `reembolso`, `reembolso_detalle`, `inventario_funcion`. | Reportes 1, 2 y 4 usan solo tablas existentes. El reporte 3 depende de `pago` (B) y falla con un mensaje claro (55000) hasta que exista. |
| 2 | `admin_operacion_audit`: usaba `creada_en`, `id_rol_actor`, `detalles`, `id_audit`. Las columnas reales son `fecha`, `rol_al_actuar` (texto), `cambios`, `id_admin_operacion_audit`. | Reescrito con las columnas reales. |
| 3 | Roles `'Administrador'`, `'Gerente'` (el rol real es `administrador`, sin gerente) y comparación por nombre. | RBAC con `autorizar_accion(usuario, permiso)`: `ver_reportes_financieros` y `ver_auditoria`. |
| 4 | `sala.capacidad` no existe (A-01 la calcula). | Capacidad = asientos de todas las zonas de la sala. |
| 5 | Tipos `BIGINT` en `RETURNS TABLE` frente a columnas `INTEGER`: error de tipo de retorno. | Tipos `integer` y conversiones explícitas. |
| 6 | **Doble resta en el reporte 1:** el bruto solo contaba boletos emitidos/usados (ya sin los reembolsados) y luego restaba los reembolsos. | Bruto = todas las líneas de compras cobradas; devuelto = líneas de boletos anulados; neto = bruto − devuelto. |
| 7 | Reporte 1 filtraba a la vez `compra.creada_en` y `funcion.inicio` con el mismo rango, lo que omitía funciones con ventas fuera de rango. | Filtro opcional solo por `funcion.inicio`. |
| 8 | Reporte 4 no agrupaba por administrador, no filtraba por rol y mezclaba intentos denegados. | Agrupado por administrador; denegados en columna aparte. |
| 9 | Funciones sin `SECURITY DEFINER` ni control de permisos; `imax_app` no tiene `SELECT` sobre `compra`, `boleto`, etc. | `SECURITY DEFINER` con `search_path` fijo, `REVOKE` a `PUBLIC` y `GRANT EXECUTE` a `imax_app`. |
| 10 | Índices en columnas inexistentes (`creada_en` en la auditoría) y sobre `pago`. Crearlos en C-04 invalida el «antes» de C-07. | Movidos a `c07_indices_c04.sql` (§6). |
| 11 | Reembolso por mensaje de excepción con texto libre y motivo ≥ 10 caracteres como «forzado». | Eliminado (ver §1). |

## 3. Definiciones comunes

| Concepto | Definición |
| --- | --- |
| Moneda | USD (CHECK en `compra` y `tarifa`); ningún reporte mezcla monedas. |
| Ventanas | Semana = 168 h; mes = 720 h; intervalos `[desde, hasta)` con un único instante de corte. |
| Compra cobrada | Estado `pagada`, `parcialmente_reembolsada` o `reembolsada`. Las `pendiente`, `cancelada` y `expirada` no son ingreso. |
| Boleto vendido | Boleto `emitido` o `usado`. El `anulado` no ocupa asiento. |
| Importe devuelto | Suma de `total_linea` de los boletos `anulado` de compras cobradas. Hoy un boleto solo se anula por reembolso (`revertir_venta`). |
| Anti-duplicación | Cada reporte preagrega (por función, película o método) **antes** de unir tablas. |

## 4. Los cuatro reportes

Todas las funciones reciben `p_id_usuario` (el de la sesión) y rechazan con SQLSTATE `42501` si el rol no tiene el permiso.

| Reporte | Función | Permiso | Lógica |
| --- | --- | --- | --- |
| 1. Ocupación y recaudación | `reporte_ocupacion_recaudacion(usuario, [función], [desde], [hasta])` | `ver_reportes_financieros` | Vendidos / capacidad, bruto, devuelto y neto por función. `LEFT JOIN`: incluye funciones sin ventas (0 % y 0.00). |
| 2. Top 5 películas | `reporte_top5_peliculas_semana(usuario, [corte])` | `ver_reportes_financieros` | Boletos emitidos/usados con `emitido_en` en `[corte − 168 h, corte)`, de compras `pagada`/`parcialmente_reembolsada`. Desempate por `id_pelicula`. |
| 3. Métodos de pago | `reporte_metodos_pago(usuario, [desde], [hasta])` | `ver_reportes_financieros` | Pagos `aprobado` del periodo (por omisión 720 h). Dos porcentajes con denominador explícito: **compras** del método / compras pagadas totales y **monto** del método / monto aprobado total. Devoluciones fuera del cálculo. |
| 4a. Auditoría por administrador | `reporte_auditoria_por_administrador(usuario, [desde], [hasta])` | `ver_auditoria` | Acciones del rol `administrador` en 720 h, agrupadas por ID: cortesías, reembolsos (ordinarios/forzados/rechazados), cambios de asiento, políticas y cambios por trigger (`insert_`/`update_`/`delete_`). Denegados aparte. |
| 4b. Detalle | `reporte_auditoria_detalle(usuario, [desde], [hasta])` | `ver_auditoria` | Mismas filas, una por acción, con IP, motivo y `cambios` (sin `password_hash`). |

Decisiones que conviene confirmar:

1. **Cortesías en el top 5:** cuentan como boleto emitido (demanda real). Si se prefiere excluirlas, se añade `cd.total_linea > 0`.
2. **Reembolsos sin tabla propia:** como `reembolso` no existe, el importe devuelto se deriva de los boletos anulados. Cuando B entregue `pago`/`reembolso`, el reporte 1 debe pasar a «pagos aprobados − devoluciones ejecutadas» (acuerdos §11).
3. **Taquillero:** la consigna le da «corte de caja propio», pero la matriz de los acuerdos §9 no le da reportes. Se aplicó la matriz de los acuerdos.

## 5. Dataset conocido y resultados esperados

`c04_verificacion_reportes.sql` usa los datos de `imax.sql` y añade, dentro de una transacción con `ROLLBACK`, una función sin ventas, seis películas con ventas, un segundo administrador y acciones de auditoría con fecha fija.

| Verificación | Esperado |
| --- | --- |
| Función 1 | capacidad 6, vendidos 3, usados 1, ocupación 50.00 %, bruto 33.00, devuelto 12.00, **neto 21.00** |
| Función sin ventas | aparece; 0 vendidos, 0.00 %, 0.00 / 0.00 / 0.00 |
| Sin duplicación | suma de brutos = suma de `compra.total` de compras cobradas; suma de vendidos = boletos emitidos/usados |
| Top 5 | `Horizonte estelar` 3, `Pelicula C04 6` 3, `C04 4` 2, `C04 5` 2, `C04 2` 1; se prueba el desempate y el `LIMIT 5`; fuera de la ventana → 0 filas |
| Métodos de pago (con tabla de ensayo) | tarjeta 2 compras 66.67 % / 25.00 / 75.76 %; paypal 1 compra 33.33 % / 8.00 / 24.24 %; rechazados y fuera de periodo excluidos |
| Auditoría | admin 7: 7 acciones manuales (1 cortesía, 2 reembolsos, 1 forzado, 1 rechazo, 1 cambio de asiento, 1 política, 1 catálogo) y 2 denegados; admin 2: 1; contador y fila fuera de ventana excluidos |
| RBAC | clientes, taquillero y operadores → `42501`; contador y administrador leen; usuario inexistente → `42501` |

## 6. Rendimiento e índices

Los índices del borrador se mueven a `c07_indices_c04.sql` porque la consigna exige `EXPLAIN ANALYZE` «antes y después». Si se crean aquí, no habrá un «antes». Se retiraron los que ya cubren las claves únicas existentes (`uq_cd_asiento`, `uq_boleto_detalle`) y el que usaba una columna inexistente. Orden: cargar dataset representativo → `ANALYZE` → guardar plan «antes» → crear índices → `ANALYZE` → guardar plan «después». `EXPLAIN` no entra al cuerpo de las funciones plpgsql; se mide la consulta base (ejemplo en el script).

## 7. Dashboard

- **Requiere interfaz:** sí. El criterio «mostrar métricas en dashboard» la exige.
- `reportes_c04.py` registra `/reportes` (cuatro reportes, filtros de función y fechas, métricas resumen) y `/reportes/exportar/<clave>.csv` (lectura/exportación del contador).
- El permiso lo decide la BD. La pantalla solo muestra «Su rol no tiene permiso» o, en el reporte 3, que falta la tabla `pago`.
- Solo lectura: sin formularios de escritura, por lo que no requiere CSRF.
- **Supuestos que no pude comprobar** porque no tengo el código de la aplicación: `app.config['DATABASE_URL']`, `session['id_usuario']` y que las plantillas viven en `src/templates/`. Hay que ajustarlos a su estructura.

## 8. Cumplimiento del issue #18

| Criterio | Estado | Evidencia y reserva |
| --- | --- | --- |
| Cuatro consultas correctas en dataset conocido | Preparado | `c04_verificacion_reportes.sql`; **sin ejecutar** (ver §9). Reporte 3 depende de `pago`. |
| Denominadores, fechas, moneda y anulaciones definidos | Cumplido | §3 y §4. |
| Joins sin duplicación; funciones sin ventas | Preparado | Preagregación; casos 9–11, 17 y 18. |
| Roles respetan la matriz; SQL y dashboard documentados | Preparado | Casos 31–40; §7. Pendiente la prueba en la aplicación. |
| Dashboard y consultas ejecutables sobre la BD | Preparado | Blueprint y funciones; falta integrarlo en la app. |

## 9. Cómo ejecutar y límites

```bash
psql -d imax -v ON_ERROR_STOP=1 -f sql/c04_reportes.sql
psql -d imax -f sql/c04_verificacion_reportes.sql     # esperado: filas 'OK' (OMITIDO solo si ya existe pago real)
```

Ejecutar con el usuario propietario (`postgres`), no con `imax_app`. En DBeaver, ejecutar como script (Alt+X).

**Límites.** (1) **No pude ejecutar nada en PostgreSQL**: no hay un servidor en mi entorno. Los scripts se revisaron a mano contra el `imax.sql`, así que ejecute la verificación y guarde la salida en `evidencias/c/c04/`. (2) El denegado de un reporte no se registra en la auditoría: la función lanza excepción y el `INSERT` se revertiría. (3) Reporte 3 y devoluciones dependen de B. (4) `resumen_auditoria_admin` (C-03) sigue usando `INTERVAL '1 month'`; los reportes nuevos usan 720 h (C-05 §9.3 ya lo señala).
