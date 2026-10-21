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
| Promoción | id_promocion, nombre, tipo, condicion, vigente_desde, vigente_hasta, activa | Referencia de reglas; aplicación automática pendiente de A-03/B. |

Las firmas siguientes son el contrato de implementación para A-02/A-03. No son funciones ejecutables ya creadas en A-01.

## Consultar funciones

`consultar_funciones(id_cine opcional, fecha_local opcional, genero opcional)`

Devuelve función, película, sala, cine, ubicación, horario y metadatos. Debe filtrar por función activa e inicio futuro. Las consultas de ejemplo del repositorio comprueban las relaciones; todavía no implementan todos esos filtros.

## Consultar distribución

`consultar_asientos(id_funcion)`

Devuelve id_funcion, id_sala, id_zona, nombre_zona, id_asiento, fila y numero. B combina estos datos físicos con su inventario por función. A no devuelve ocupado/disponible ni propietario de una reserva.

## Consultar tarifas y promociones

`consultar_tarifas(id_funcion, id_zona, id_categoria_entrada, instante)`

Devuelve tarifa, monto, moneda y vigencia aplicable. Intervalos de vigencia: desde incluido y hasta excluido. A-03 debe resolver las vigencias sin ambigüedad y devolver errores comprensibles si falta una tarifa.

`consultar_promociones(id_funcion, instante)`

Devuelve promociones asociadas mediante funcion_promocion, activas y vigentes. La condición actual es texto descriptivo: no se debe interpretar como código ni afirmar que el 2x1 ya se calcula automáticamente.

B conserva en su compra el precio, descuento y referencias utilizados. A no cambia los precios históricos de una venta al editar tarifas.

## Coordinación pendiente

- B entrega el contrato de actividad vigente para proteger salas en A-04.
- C entrega identidad, autorización y auditoría. A no duplica sus tablas.
- La sala de una función o zona con tarifas no puede reasignarse directamente; el ajuste de integridad protege este vínculo. Los flujos futuros de reprogramación deben respetarlo.
- A-01 entrega modelo, datos, campos y estas firmas; su consumo real se verifica al integrar los módulos.
