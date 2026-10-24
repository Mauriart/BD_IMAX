# Guía de trabajo — Bloque A de BD IMAX

Responsable: **Mauriart**.

## 1. Propósito y alcance

Esta guía organiza el trabajo de A a partir de los issues existentes. Cubre modelo de catálogo/salas/tarifas, programación, cartelera, protección de salas, factibilidad, costos y pruebas del dominio.

Las entidades ya figuran en los [acuerdos](00_acuerdos.md#5-entidades-y-campos-mínimos-compartidos). Se desarrollan sus relaciones, restricciones, normalización y SQL en A-01. El DER es una representación de esa base y no un nuevo levantamiento de entidades.

Consultar la [matriz de requisitos de A](requisitos.md) para relacionar cada tarea con prueba y evidencia.

**Decisiones de alcance:**

- En este apartado se trabaja únicamente A.
- B y C se mencionan como contratos y dependencias.
- El seguimiento usa issues y PRs, **sin GitHub Projects**.
- Esta guía concentra organización e instrucciones; se omite ampliar el README como entregable.
- Mauriart toma las decisiones pendientes. La publicación de documentos no representa aprobación de añadidos técnicos ni una revisión de todos los integrantes.

## 2. Orden de referencia en GitHub

| Orden | Issue | Código | Resultado que debe entregar A |
| --- | --- | --- | --- |
| 1 | [#2](https://github.com/Mauriart/BD_IMAX/issues/2) | A-01 | Modelo parcial, normalización, diccionario, DDL y datos sintéticos de A. |
| 2 | [#3](https://github.com/Mauriart/BD_IMAX/issues/3) | A-02 | Gestión de catálogo/salas/funciones con protección de traslapes. |
| 3 | [#4](https://github.com/Mauriart/BD_IMAX/issues/4) | A-03 | Cartelera filtrada y configuración/consulta de tarifas y promociones. |
| 4 | [#5](https://github.com/Mauriart/BD_IMAX/issues/5) | A-05 | Rechazo del legado y arquitectura técnica/operativa propuesta. |
| 5 | [#7](https://github.com/Mauriart/BD_IMAX/issues/7) | A-04 | Protección de distribución de salas con reservas o ventas activas. |
| 6 | [#8](https://github.com/Mauriart/BD_IMAX/issues/8) | A-07 | Pruebas, documentación del módulo y guion de demostración. |
| 7 | [#20](https://github.com/Mauriart/BD_IMAX/issues/20) | A-06 | Comparación económica de dos proveedores y proyección a tres años. |

El orden conserva la numeración existente de GitHub; no renumera códigos ni modifica dependencias. A-05 puede redactarse con la base de acuerdos; A-06 se completa tras A-05 y el dimensionamiento de C. Las pruebas se preparan durante cada tarea, aunque su consolidación sea A-07.

## 3. Cómo ejecutar cada tarea

### A-01 — Modelo y SQL

1. Tomar las entidades A del documento de acuerdos y sus vínculos con función/asiento/usuario compartidos.
2. Dibujar cardinalidades y señalar PK, FK, claves alternativas y nulabilidad.
3. Explicar dependencias funcionales y normalización, incluidas zonas, géneros y categorías.
4. Definir las restricciones de integridad; diferenciar asiento físico de inventario por función.
5. Preparar SQL de creación y datos sintéticos de A con orden de instalación inequívoco.
6. Definir campos de salida para B/C antes de construir las pantallas.
7. Verificar instalación limpia, datos válidos y rechazos SQL.

Entregables previstos: DER editable/exportado, diccionario y normalización en `docs/modelos/`; SQL del dominio en `sql/`. Sus nombres exactos se fijan al crearlos. No generar tablas de ventas o identidad duplicadas para facilitar el desarrollo aislado.

### A-02 — Administración y programación

Implementar formularios y operaciones para catálogo, salas y funciones. Validar metadatos obligatorios, capacidad, distribución y horarios. La protección de traslapes debe considerar duración/limpieza y dos operaciones simultáneas.

Conectar las acciones administrativas al contrato de identidad/permisos/auditoría de C. Mientras se trabaja aisladamente, usar un adaptador de prueba explícito, con aceptación y denegación; no dejarlo como autenticación definitiva.

Entregables previstos: módulo `src/cartelera/`, vistas, SQL pertinente y evidencia PA-04 a PA-07.

### A-03 — Cartelera y reglas de precios

Implementar consulta de funciones activas futuras con ubicación, fecha local y género. Mostrar título, sinopsis, clasificación, póster, horarios y ubicación.

Configurar tarifas por función/zona/categoría y promociones con condiciones/vigencias verificables. Ofrecer a B datos estables y suficientes para calcular la compra. El checkout, los pagos y la emisión de boletos pertenecen a B.

Entregables previstos: cartelera, configuración de reglas y contrato de consulta; evidencia PA-08 a PA-11.

### A-05 — Factibilidad y arquitectura

Redactar `docs/factibilidad.md` con respuesta a las seis debilidades del escenario legado: equipo/BD, red, hoja compartida, pagos, recuperación y dimensionamiento.

Incluir diagrama, componentes, flujo de datos, operación/soporte y riesgos residuales. Separar lo que demuestra el prototipo de lo que propone la arquitectura global. Usar los datos del PDF y documentar sus ambigüedades; no sustituir 500 funciones diarias por 500 títulos.

Referenciar la continuidad de C cuando esté disponible y mantener coherencia con los costos. No atribuir capacidad global a una prueba local.

Entregables: dictamen, arquitectura y verificación VA-01/02.

### A-04 — Protección de salas

Impedir en la operación real la eliminación o alteración incompatible de distribución con reservas/ventas activas. La validación debe coordinarse con B para cubrir actividad simultánea.

Probar caso con reserva, con venta, sin actividad y carrera de modificación/reserva. Integrar permisos y auditoría de C. Los datos sintéticos permiten ensayos aislados, pero no cierran la integración.

Entregables previstos: validación transaccional A, contrato con B y evidencia PA-12/13.

### A-07 — Pruebas y documentación

Consolidar `docs/pruebas_a.md` con precondiciones, pasos, esperado, obtenido y evidencia; actualizar la matriz con rutas reales. Documentar restricciones, GUI y contratos efectivamente implementados.

Guion de demostración de A:

1. Administrador registra una película con metadatos completos; intento incompleto rechazado.
2. Crea sala/distribución y programa función; traslape rechazado.
3. Configura tarifas y promoción; consulta las reglas vigentes.
4. Usuario filtra cartelera; funciones pasadas/inactivas no se muestran.
5. Cliente o taquillero intenta modificar precios/salas y recibe denegación.
6. Modificación incompatible de sala con reserva/venta activa es rechazada.
7. Cambio permitido conserva integridad y genera auditoría.
8. Se muestran resultados SQL y evidencia de los casos simultáneos pertinentes.

Entregables previstos: documentación, pruebas y `evidencias/a/`; reproducción/revisión por otro integrante cuando corresponda.

### A-06 — Costos

Añadir al apartado económico de `docs/factibilidad.md` una comparación de dos proveedores con regiones, capacidades y retención equivalentes. Incluir BD, cómputo, red, almacenamiento, backups y componentes de seguridad pertinentes.

Usar fuentes oficiales y precios consultados al realizar la comparación, con fecha, moneda y supuestos. No escoger proveedores, contratar servicios ni afirmar cotizaciones antes de efectuar esa tarea.

Separar inversión inicial, OPEX y proyección de 36 meses. Definir volumen mensual para costo por millón de transacciones; el pico de 50 000 TPS durante diez minutos no es una tasa mensual continua. Presentar ROI como cálculo condicionado a supuestos.

C proporciona el dimensionamiento. Hasta recibirlo, cualquier escenario preliminar de A se identifica como estimación pendiente de conciliar.

Entregables: tablas/fórmulas/fuentes y verificaciones VA-03/04.

## 4. Organización de archivos de A

| Ruta | Uso |
| --- | --- |
| `docs/00_acuerdos.md` | Base común y decisiones. |
| `docs/requisitos.md` | Matriz de A, en orden de issues. |
| `docs/guia_trabajo.md` | Esta guía; organización e instrucciones de ejecución conforme se implemente. |
| `docs/modelos/` | DER A, diccionario y normalización. |
| `docs/factibilidad.md` | Rechazo, arquitectura y costos de A. |
| `docs/pruebas_a.md` | Casos, resultados y guion del módulo A. |
| `sql/` | DDL/restricciones/datos de A, con orden compatible con instalación común. |
| `src/cartelera/` | Operaciones y vistas del dominio A dentro de la aplicación compartida. |
| `tests/cartelera/` | Pruebas del dominio A. |
| `evidencias/a/` | Resultados verificables identificados por prueba. |

Esta entrega documental incorpora la matriz y la guía; las rutas restantes se crean al desarrollar sus tareas. No presentar el esquema de carpetas como implementación terminada.

La instalación local se documentará aquí con los comandos comprobados al incorporar la aplicación: dependencias, base vacía, configuración sin secretos, orden SQL, datos y arranque. No se afirma que la aplicación ya se pueda ejecutar.

## 5. Trabajo con GitHub

1. Elegir el issue de A correspondiente y actualizar la copia local.
2. Crear una rama, por ejemplo `a-01-modelo-cartelera`.
3. Hacer commits pequeños y relacionados con la tarea.
4. Abrir PR con descripción del cambio, referencia al issue y evidencia.
5. Revisar e integrar según el flujo del equipo; cerrar el issue solo al cumplir todos sus criterios.

Estados de seguimiento: issue abierto sin inicio = pendiente; trabajo/ramas vinculadas = en curso; PR abierto = en revisión; cambio integrado y criterios cumplidos = terminado. No se necesita GitHub Projects.

Publicar estos documentos es una actualización de la planificación solicitada por Mauriart. No demuestra ejecución de A-01 ni permite cerrar A-07.

## 6. Dependencias y decisiones

- **A entrega a B:** IDs y campos de catálogo, salas/asientos, funciones y reglas de tarifas/promociones.
- **A recibe de B:** forma de consultar actividad vigente y protocolo para coordinar modificaciones de sala.
- **A recibe de C:** identidad, autorización, auditoría y dimensionamiento.
- **A entrega a C:** acciones/recursos administrativos y arquitectura que debe ser coherente con continuidad.

Se puede avanzar con fixtures y contratos compatibles, identificando qué integración falta. No implementar por cuenta de A el checkout, el consumo QR, el sistema de roles o los reportes de C.

Mauriart decide las cuestiones que aún no estén acordadas. Si una decisión añadida durante la corrección del documento no cuenta con confirmación, se identifica antes de usarla para fijar comportamiento o alcance. Una nueva decisión debe registrar qué cambia y qué dependencia afecta.

## 7. Cierre de una tarea de A

- Requisitos y criterios del issue cubiertos.
- Modelo, SQL, operaciones y pantalla coherentes.
- Éxitos y rechazos con evidencia real.
- Pruebas simultáneas cuando la regla lo exige.
- Dependencias reales integradas o claramente registradas como pendientes.
- Matriz, diccionario y documentación actualizados.
- Revisión e integración registradas; ninguna aprobación se presume.

El avance de **A-01 / issue #2** se encuentra en [docs/compañeroA/modelo_a.md](compa%C3%B1eroA/modelo_a.md): Chen, esquema SQL, carga de ejemplo, consultas, diccionario y normalización. Los resultados confirmados y las comprobaciones pendientes se registran en [pruebas_a.md](compa%C3%B1eroA/pruebas_a.md). Se mantiene esta carpeta para el material de A; las rutas sugeridas anteriormente no exigen duplicar archivos.

## Entrega de A-01

El modelo parcial, SQL, datos, diccionario, normalización, contratos y pruebas de instalación están completos en [compañeroA](compa%C3%B1eroA/modelo_a.md). Por decisión de Mauriart no se requiere otra persona ni PR adicional para cerrar esta entrega. La integración B/C se verifica en las tareas posteriores. El siguiente trabajo es A-02: administración y programación sin traslapes.

Para la base ya creada en DBeaver, ejecutar únicamente [ajuste_integridad_A.sql](compa%C3%B1eroA/ajuste_integridad_A.sql); no repetir CREATE TABLE ni la carga de datos. La prueba temporal ya incorporó este ajuste, pero no modifica automáticamente la base personal.

## Entrega funcional de A-02

Las pantallas de películas, salas, distribución y funciones, más el rechazo de traslapes y las pruebas simultáneas, están completas en dev/. Para verificar: desde dev ejecutar `.\.venv\Scripts\python.exe verificar_a02.py`. La descripción y el guion están en [interfaz_A.md](compa%C3%B1eroA/interfaz_A.md). Por decisión de Mauriart, permisos/auditoría con C se integran en T-02 (#23); siguen pendientes y no bloquean este cierre funcional de A-02.

## Avance de A-03, A-04 y A-05

A-03 está integrado en main mediante el [PR #27](https://github.com/Mauriart/BD_IMAX/pull/27), con el issue #4 cerrado. La cartelera, tarifas/promociones, SQL, contratos y 27 pruebas de A-02/A-03 se documentan en [cartelera_A.md](compa%C3%B1eroA/cartelera_A.md) y [tarifas_promociones_A.md](compa%C3%B1eroA/tarifas_promociones_A.md). Las dependencias reales de B/C y el Chen global permanecen registradas en T-02 (#23).

Se avanza en A-05 mientras A-04 necesita el contrato y la actividad de reservas/ventas de B para verificar su protección real. El orden por número de issue es una referencia de organización, no una obligación de esperar a B para redactar arquitectura.

El entregable de A-05 es [factibilidad.md](factibilidad.md): dictamen del legado, seis debilidades, diagrama, flujo, riesgos, operación y criterios de capacidad/continuidad. Es documentación para revisión de Mauriart; no agrega SQL ni Python y no despliega infraestructura. El dimensionamiento detallado de C y los costos de A-06 se mantienen pendientes, sin bloquear este análisis de A.

## Acceso a las pantallas administrativas de A

La integración de A con identidad, permisos y auditoría de C-01 se explica en [permisos_auditoria_A.md](compa%C3%B1eroA/permisos_auditoria_A.md). Incluye la preparación local de la contraseña, los permisos por rol y las 47 pruebas de A y compatibilidad. El esquema de C se conserva en su carpeta original. A-04 sigue dependiendo de reservas y ventas de B; T-02 permanece pendiente para la integración completa.

## Avance preliminar de A-06

C-05 y C-06 ya están disponibles en main. La [comparación económica de A](compa%C3%B1eroA/costos_A06.md) incorpora el almacenamiento de C, precios públicos, inversión inicial, operación, sensibilidad y ROI. El cálculo se reproduce con dev/calcular_costos_a06.py. A-06 sigue abierto hasta conciliar B, dimensionar la carga y completar las cotizaciones; la estimación no demuestra capacidad mundial.
