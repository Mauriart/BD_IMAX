# Datos y operaciones compartidos del bloque A

## Identificadores publicados

Todos los identificadores simples son enteros generados con SERIAL. B y C deben usar los IDs devueltos por las consultas, sin asumir que empiezan en 1.

| Dato | Campos compartidos | Uso |
| --- | --- | --- |
| Cine | id_cine, nombre, ubicacion, zona_horaria | Ubicación y presentación de fecha local. |
| Sala | id_sala, id_cine, nombre | Programación y distribución. |
| Zona | id_zona, id_sala, nombre | Identificar a qué sala pertenece cada zona. |
| Asiento | id_asiento, id_zona, fila, numero | B crea disponibilidad por función/asiento; sala se obtiene desde zona. |
| Función | id_funcion, id_pelicula, id_sala, inicio, fin, activa | Reserva B y validación de puerta C. |
| Categoría | id_categoria_entrada, nombre, requiere_acreditacion | Selección de tarifa y acreditación C. |
| Tarifa | id_tarifa, id_funcion, id_zona, id_categoria_entrada, monto, moneda, vigente_desde, vigente_hasta | Cotización B; monto decimal y moneda USD. |
| Promoción | id_promocion, nombre, tipo, condicion, vigente_desde, vigente_hasta, activa; días, zonas y categorías relacionadas | A-03 entrega condiciones consultables; B aplica el descuento y conserva sus referencias. |

Las firmas siguientes parten del contrato de A-01. A-03 implementa las consultas de funciones en `dev/cartelera.py` y tarifas/promociones en `dev/precios.py`; el contrato de distribución se conserva para B.

## Consultar funciones

`consultar_funciones(id_cine opcional, fecha_local opcional, genero opcional)`

Devuelve función, película, sala, cine, ubicación, horario y metadatos. Filtra por función activa e inicio futuro. La implementación utiliza el parámetro `id_genero` y fechas locales; ver [cartelera_A.md](cartelera_A.md).

## Consultar distribución

`consultar_asientos(id_funcion)`

Devuelve id_funcion, id_sala, id_zona, nombre_zona, id_asiento, fila y numero. B combina estos datos físicos con su inventario por función. A no devuelve ocupado/disponible ni propietario de una reserva.

## Consultar tarifas y promociones

`consultar_tarifas(id_funcion, id_zona, id_categoria_entrada, instante)`

Implementada en `dev/precios.py`. Devuelve un diccionario con tarifa, monto `Decimal`, moneda, vigencia, nombre de zona/categoría y `requiere_acreditacion`. Intervalos: desde incluido y hasta excluido. El instante debe incluir zona horaria. Lanza `ValueError` si falta tarifa, es ambigua o la función no está disponible. El SQL de A-03 impide vigencias superpuestas, incluidas altas simultáneas en `READ COMMITTED`.

`consultar_promociones(id_funcion, instante, id_zona=None, id_categoria_entrada=None)`

Implementada en `dev/precios.py`. Devuelve promociones 2x1 asociadas mediante `funcion_promocion`, activas y vigentes al cotizar; verifica el día local de inicio de la función. Incluye listas de IDs `dias`, `zonas` y `categorias` procedentes de las tres tablas de condiciones; permite filtrar por zona/categoría. Una promoción sin condiciones estructuradas no se ofrece. La descripción no se interpreta como código. A no calcula ni reserva el descuento: B aplica parejas, no acumulación, desempate e instantáneas históricas. Ver [tarifas_promociones_A.md](tarifas_promociones_A.md).

B conserva en su compra el precio, descuento y referencias utilizados. A no cambia los precios históricos de una venta al editar tarifas.

## Coordinación pendiente

- B entrega el contrato de actividad vigente para proteger salas en A-04.
- C aporta identidad, autorización y auditoría. A ya consume sus tablas y autorizar_accion en esta integración; ver [permisos_auditoria_A.md](permisos_auditoria_A.md). A no duplica sus tablas.
- La sala de una función o zona con tarifas no puede reasignarse directamente; el ajuste de integridad protege este vínculo. Los flujos futuros de reprogramación deben respetarlo.
- A-01 entrega modelo, datos, campos y estas firmas; su consumo real se verifica al integrar los módulos.

## Identidad y auditoría de A con C

La sesión autenticada identifica al usuario; los formularios no eligen actor ni rol. A consulta autorizar_accion y revalida el permiso dentro de cada transacción de escritura. Cada cambio guarda un evento en admin_operacion_audit con actor, rol, IP, acción, entidad, ID, motivo y datos antes/después. El cambio y el evento se confirman juntos; si falla la auditoría, ninguno se guarda. Las once variantes de escritura actuales se verifican en dev/verificar_seguridad_a.py. T-02 conserva pendiente la integración global con B/C.

La compatibilidad con C-03 añade contexto local de transacción (app.id_usuario, app.ip, app.motivo) para sus guardias. Si un trigger habilitado ya auditó la fila, A no registra nuevamente ese cambio. Sin ese trigger se conserva el evento explícito de A. Las cinco pruebas en dev/verificar_compatibilidad_c03.py consumen las funciones reales del SQL de C-03; no prueban ni instalan su módulo completo. Ver el alcance de las asociaciones y lotes en permisos_auditoria_A.md.
