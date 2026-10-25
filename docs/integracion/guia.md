# Integración de A, B y C

La aplicación comparte una sola base y un solo inicio de sesión. El modelo de ventas es el publicado por B, adaptado a los permisos, puerta, reembolsos y reportes de C y a las tarifas/promociones de A.

## Archivos para ejecutar

- [instalacion_completa.sql](instalacion_completa.sql): instalación completa en una base vacía; 33 tablas, restricciones, funciones, triggers y datos de ejemplo. Una transacción; no borra ni reemplaza tablas existentes.
- [actualizar_base_A_C.sql](actualizar_base_A_C.sql): actualización de una base con A y C-01, pero sin tablas de B. Conserva sus datos. Rechaza una instalación parcial o una base que ya tenga tablas de B.
- [modelo_relacional_global.md](modelo_relacional_global.md): tablas, columnas, PK, FK y restricciones obtenidas de la instalación real.
- Aplicación: dev/. Desde esa carpeta, instalar requirements.txt, configurar .env y abrir iniciar.cmd. Este iniciador usa .venv sin activarlo y ejecuta la liberación de reservas cada dos segundos.
- configurar_acceso.py prepara una contraseña local para cada cuenta existente que todavía tenga HASH_DE_PRUEBA. No reemplaza contraseñas configuradas ni cambia roles.
- generar_instalacion.py vuelve a generar ambos SQL desde sus fuentes. Los cambios se hacen en las fuentes y luego se regeneran los dos archivos.

En otra computadora: crear .venv con py -m venv .venv, instalar con .venv\Scripts\python.exe -m pip install -r requirements.txt y completar la configuración de .env.example. Los valores reales de .env se conservan fuera de Git.

## Estado de la base local

La base p2 se actualizó con el segundo script. Se compararon conteo y contenido de las 21 tablas originales de datos antes de confirmar; se conservaron. rol_permiso incorporó los permisos administrativos que C necesita para sus operaciones.

Quedaron 33 tablas e inventario inicial para las funciones existentes. No se insertaron pagos de prueba en p2. Los experimentos de compra, pago, ingreso y reembolso se hicieron en esquemas de ensayo eliminados al terminar. La aplicación local se verificó con iniciar.py y responde en http://127.0.0.1:5000/cartelera.

La actualización no se aplica por segunda vez: reconoce las tablas de B y se detiene. El instalador completo tampoco es un mecanismo para reemplazar una base existente.

## Qué hace SQL

1. Reserva entre uno y seis asientos distintos de una función activa y futura.
2. Genera inventario sin reiniciar asientos reservados o vendidos.
3. Exige una categoría y una tarifa vigente única. No asigna precios de respaldo.
4. Consulta las condiciones estructuradas de 2×1: función, vigencia, día local, zona y categoría. Cada pareja comparte el descuento, incluidos los centavos; una entrada sobrante paga su precio completo.
5. Conserva el precio y descuento de la reserva. Un cambio de tarifa posterior no modifica lo ya cotizado.
6. Revalida vencimiento y estado al pagar. Un pago rechazado libera; un pago aprobado emite el boleto y su UUID.
7. Identifica al actor con app.id_usuario fijado por el servidor y verifica el permiso de C.
8. Comprueba el ingreso una sola vez, función, estado, ventana horaria y acreditación de categoría especial.
9. C autoriza la solicitud de reembolso y B ejecuta la devolución: anula solo los boletos seleccionados, registra monto/pago/reembolso, libera inventario y conserva historia.
10. Cortesías y cambios de asiento usan el mismo inventario. Requieren administrador y motivo; un fallo de auditoría revierte el cambio.
11. A-04 coordina la distribución con la actividad de ventas. Los cuatro logs impiden UPDATE/DELETE y TRUNCATE.
12. Los reportes consultan el boleto real de B y sus estados; incluyen compras parcialmente reembolsadas.

Estados de compra: Pendiente, Pagada, Cancelada, Expirada, ParcialmenteReembolsada, Reembolsada. Boleto: Emitido, Usado, Anulado. Reserva: activa, confirmada, expirada, liberada. Las solicitudes de C conservan pendiente, ejecutada y rechazada.

## Qué hace Python

- Reutiliza la conexión y la sesión autenticada en todos los módulos.
- Muestra cartelera, mapa con actualización cada dos segundos, categoría, checkout, factura, QR y compras propias o procesadas por el taquillero.
- El servidor toma cliente/actor desde el usuario autenticado; la venta de taquilla identifica además al cliente beneficiario.
- Protege los formularios con CSRF. Se retiró entrar-prueba; la URL ya no cambia el usuario.
- Ofrece las pantallas de puerta, solicitud/resolución de reembolso, cortesías y cambio de asiento.
- Une el dashboard y la exportación CSV al diseño común.
- Ejecuta liberar_reservas_vencidas periódicamente desde iniciar.py; no necesita que un cliente mantenga abierto el mapa.

El proceso local se sirve en 127.0.0.1:5000 con debug desactivado. Para un despliegue distinto se necesita configurar su ejecución y revisar los privilegios de la cuenta técnica; las pruebas locales usan la cuenta configurada en .env y no certifican una infraestructura de producción.

## Pruebas y evidencias

| Suite | Casos aprobados |
| --- | ---: |
| verificar_a02.py | 11 |
| verificar_cartelera_a03.py | 5 |
| verificar_precios_a03.py | 11 |
| verificar_seguridad_a.py | 15 |
| verificar_compatibilidad_c03.py | 5 |
| verificar_salas_a04.py | 17 |
| verificar_integracion_b_a04.py | 10 |
| verificar_integracion_global.py | 23 |
| Total | 97 |

Las ocho salidas reales están en [evidencias](evidencias/). Las suites crean sus propios esquemas, sin buscar tablas/funciones de public como respaldo, y los eliminan al terminar.

Desde dev se ejecutan con .venv\Scripts\python.exe y el nombre de la suite. Las dos que reciben el SQL de C-03 usan el archivo del propio repositorio:

    .venv\Scripts\python.exe verificar_compatibilidad_c03.py ..\docs\compañeroC\sql_C-03.sql
    .venv\Scripts\python.exe verificar_salas_a04.py --c03 ..\docs\compañeroC\sql_C-03.sql
    .venv\Scripts\python.exe verificar_integracion_global.py

La última suite instala el SQL completo y prueba:

- Cotización 2×1 impar e históricos después de cambiar una tarifa.
- Checkout y venta presencial desde Flask; factura y PNG del QR.
- Propiedad de compras/QR, CSRF, permisos SQL y retiro de la sesión de prueba.
- Funciones inactivas, asientos repetidos y ausencia de tarifa.
- Pago rechazado, repetición idempotente y expiración/pago tardío.
- Ingreso único, QR de otra función y acreditación especial.
- Reembolso parcial, reventa, excepción a la política y rechazo de boleto usado.
- Cortesía, cambio de asiento, conflicto y rollback ante fallo de auditoría.
- Métodos de pago, top cinco, ocupación/recaudación y logs inmutables.
- 50 reservas simultáneas: 1 éxito, 49 conflictos y una sola reserva vigente.
- 50 escaneos simultáneos: 1 ingreso, 49 rechazos y 50 registros de puerta.
- Carrera ingreso/reembolso: exactamente uno gana y el estado final coincide.
- Actualización desde A/C-01 conservando datos/contraseñas y rechazo seguro de reinstalación.

Se revisaron en navegador el acceso del administrador y operador, el mapa, el dashboard y puerta. Las capturas son del entorno temporal, con datos sintéticos: [mapa](evidencias/mapa.png), [reportes](evidencias/reportes.png), [puerta](evidencias/puerta.png). El formulario y la imagen del QR se comprobaron además mediante el cliente de Flask.

## Orden de bloqueos y límites

Las operaciones comparten la fila de sala. Pago, ingreso y reembolso bloquean la compra y el boleto antes de decidir su estado. Inventario se bloquea en orden de asiento. Se utiliza READ COMMITTED; no se supone validez bajo otra configuración.

Las pruebas observadas no certifican todos los órdenes posibles de SQL administrativo directo. PostgreSQL puede abortar una transacción incompatible por deadlock; esa transacción debe revertirse y reintentarse, conservando la referencia de idempotencia del pago. No se fuerza que dos operaciones incompatibles tengan éxito.

Los reportes usan USD y periodos definidos. El importe devuelto se obtiene de las líneas de boletos anulados; la ejecución de B deja también las tablas de reembolso y sus montos. Las cortesías cuentan como entradas emitidas con recaudación cero.

## Material anterior y pendientes de entrega

imax.sql de C conserva un modelo provisional de ventas: no se combina con este instalador. Los scripts de pruebas antiguos de B/C y sus documentos son material de trabajo; varias firmas y estados cambiaron al integrar. La ejecución reproducible actual es la descrita aquí.

T-02 conserva la conciliación del Chen global y la revisión documental final; este modelo relacional es la base comprobada. La integración operativa ya tiene código y evidencias.

A-07 reúne las pruebas y el guion actualizados. Quedan A-06 (cerrar costos), la evidencia EXPLAIN ANALYZE de C-07 y la preparación del documento técnico final en T-03. Las pruebas de 50 conexiones no demuestran la escala mundial propuesta en factibilidad ni sustituyen una prueba de recuperación.

No se cerraron automáticamente los issues de B/C por integrar sus archivos. Su aceptación debe contrastarse con las pruebas y pendientes específicos. La limpieza final del repositorio conserva commits e historia y distingue los entregables finales de los borradores.


## Configuración inicial y siguiente entrega

Pareja General se configuró por decisión de Mauriart como 2x1 solo los miércoles, para Adulto/General. El día corresponde al inicio local de la función. Se conservan vigencias y asociaciones existentes: una función de domingo no recibe ese descuento y una promoción vencida tampoco. El instalador nuevo incluye el día 3; ajustar_pareja_general.sql documenta el ajuste aplicado a p2 con actor y auditoría. La suite global contrasta una compra de dos entradas en miércoles (USD 8) con jueves (USD 16), a tarifa base USD 8.

Las [pruebas de A](../compañeroA/pruebas_modulo_A.md) y el [guion](../compañeroA/guion_defensa_A.md) son material para el informe. La práctica oral del equipo sigue por realizar. La limpieza y estructura definitiva quedan para después del documento final: un SQL completo, un informe y los archivos del programa ordenados.
