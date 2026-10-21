# Matriz de requisitos y trazabilidad — Bloque A

Responsable: **Mauriart**.

## Alcance y lectura

Esta matriz cubre exclusivamente el bloque A: cartelera, programación, salas, tarifas, promociones, factibilidad y costos. B y C aparecen solo como dependencias; no se desarrollan ni se dan por cumplidos sus requisitos.

Fuentes: RN-01, RN-02, RN-06, RN-07, RN-17, RN-18 y RN-20 de la consigna, pauta de programación, fases DBLC e issues del repositorio. Las entidades base ya están en los [acuerdos](00_acuerdos.md#5-entidades-y-campos-mínimos-compartidos); no se deben inventar tres modelos independientes.

El orden es el número ascendente de los issues existentes: **#2, #3, #4, #5, #7, #8 y #20**. Por eso A-05 aparece antes de A-04 y A-06 al final. El número de issue y el código A-xx se conservan.

**A-01 completado en su alcance de diseño parcial:** Chen, esquema de 12 tablas, diccionario, normalización, datos, contratos para B/C y verificación en base temporal. Véanse [modelo](compa%C3%B1eroA/modelo_a.md), [contratos](compa%C3%B1eroA/contratos_a.md) y [resultados](compa%C3%B1eroA/pruebas_a.md). La integración y los comportamientos de A-02/A-03/A-04 permanecen en sus issues. No se exige revisión de otra persona para cerrar A-01, por decisión de Mauriart.

## 1. Matriz por issue

| ID | Issue | Fuente | Comportamiento o entregable verificable | Implementación/documento previsto | Prueba o verificación | Estado |
| --- | --- | --- | --- | --- | --- | --- |
| RF-A-01 | [#2 · A-01](https://github.com/Mauriart/BD_IMAX/issues/2) | RN-01/02/06/07/18; DBLC 3 | Modelar cine, película, género, sala, zona, asiento, función, categoría, tarifa y promoción con sus relaciones. | [Modelo y SQL](compa%C3%B1eroA/modelo_a.md); [datos](compa%C3%B1eroA/datos_A.sql); [contratos](compa%C3%B1eroA/contratos_a.md). | [Verificación y resultados](compa%C3%B1eroA/pruebas_a.md): instalación, relaciones, integridad y consultas. | Verificado en el alcance A-01; integración posterior. |
| RNF-A-01 | #2 · A-01 | DBLC 3/4 | DDL instalable en base vacía; rechazar vínculos inválidos, importes negativos y asientos duplicados por sala. | [Modelo y SQL](compa%C3%B1eroA/modelo_a.md); [datos](compa%C3%B1eroA/datos_A.sql); [contratos](compa%C3%B1eroA/contratos_a.md). | [Verificación y resultados](compa%C3%B1eroA/pruebas_a.md): instalación, relaciones, integridad y consultas. | Verificado en el alcance A-01; integración posterior. |
| RNF-A-02 | #2 · A-01 | RN-03/18; contrato con B | Diferenciar asiento físico y disponibilidad por función; no guardar ocupación global en `asiento`. | [Modelo y SQL](compa%C3%B1eroA/modelo_a.md); [datos](compa%C3%B1eroA/datos_A.sql); [contratos](compa%C3%B1eroA/contratos_a.md). | [Verificación y resultados](compa%C3%B1eroA/pruebas_a.md): instalación, relaciones, integridad y consultas. | Verificado en el alcance A-01; integración posterior. |
| RNF-A-03 | #2 · A-01 | DBLC 3 | Justificar normalización con claves y dependencias funcionales; ofrecer datos sintéticos y campos compartidos antes de la GUI. | [Modelo y SQL](compa%C3%B1eroA/modelo_a.md); [datos](compa%C3%B1eroA/datos_A.sql); [contratos](compa%C3%B1eroA/contratos_a.md). | [Verificación y resultados](compa%C3%B1eroA/pruebas_a.md): instalación, relaciones, integridad y consultas. | Verificado en el alcance A-01; integración posterior. |
| RF-A-02 | [#3 · A-02](https://github.com/Mauriart/BD_IMAX/issues/3) | RN-02; pauta de programación | Administrador crea/edita películas con título, sinopsis, clasificación, duración y póster. Rechazar información obligatoria incompleta. | [Aplicación y pruebas de A-02](compa%C3%B1eroA/interfaz_A.md); código en dev/. | dev/verificar_a02.py: 11 pruebas aprobadas y sus subcasos. | Verificado funcionalmente; permisos/auditoría en T-02. |
| RF-A-03 | #3 · A-02 | Pauta de programación | Gestionar salas, zonas, asientos y funciones con capacidad/distribución coherentes. | [Aplicación y pruebas de A-02](compa%C3%B1eroA/interfaz_A.md); código en dev/. | dev/verificar_a02.py: 11 pruebas aprobadas y sus subcasos. | Verificado funcionalmente; protección por ventas en A-04. |
| RNF-A-04 | #3 · A-02 | Pauta de programación; acuerdos | Impedir traslapes por sala considerando duración y limpieza, incluso ante programación simultánea. | [Aplicación y pruebas de A-02](compa%C3%B1eroA/interfaz_A.md); código en dev/. | dev/verificar_a02.py: 11 pruebas aprobadas y sus subcasos. | Verificado, incluida concurrencia. |
| RF-A-04 | #3 · A-02 | RN-17/20 | Proteger operaciones administrativas y registrar cambios críticos mediante identidad, autorización y auditoría de C. | [Aplicación y pruebas de A-02](compa%C3%B1eroA/interfaz_A.md); código en dev/. | Pendiente: denegación real por rol y evento administrativo en T-02. | Trasladado a T-02 (#23) por decisión de Mauriart; pendiente de C. |
| RF-A-05 | [#4 · A-03](https://github.com/Mauriart/BD_IMAX/issues/4) | RN-01/02; pauta de checkout | Mostrar solo funciones activas futuras con metadatos completos; filtrar por ubicación, fecha local y género. El modelo acordado en A-01 no incluye estado de película. | [Cartelera](compa%C3%B1eroA/cartelera_A.md); `dev/cartelera.py`. | PA-08: 5 pruebas en `dev/verificar_cartelera_a03.py`, incluidos filtros combinados y fecha local. | Verificado aisladamente en A. |
| RF-A-06 | #4 · A-03 | RN-06 | Configurar categorías y tarifas por función/zona; indicar si la categoría exige acreditación en puerta. | [Tarifas/promociones](compa%C3%B1eroA/tarifas_promociones_A.md); `dev/precios.py`. | PA-09: formulario, consulta y matriz con acreditación en `dev/verificar_precios_a03.py`. | Verificado en A; acreditación física pendiente de C. |
| RF-A-07 | #4 · A-03 | RN-07 | Configurar promociones con condiciones y vigencia estructuradas; entregar a B información suficiente para aplicarlas. | [Condiciones y contrato](compa%C3%B1eroA/tarifas_promociones_A.md); tres tablas de condiciones y `consultar_promociones`. | PA-10: vigencia, actividad, días locales, zona/categoría, condiciones incompletas y reversión transaccional. | Verificado aisladamente; aplicación del descuento pendiente de B. |
| RNF-A-05 | #4 · A-03 | RN-07/08; acuerdos | Resolver tarifa vigente sin ambigüedad y preservar referencias históricas; B conserva la cotización y calcula el total. | [SQL y reglas de vigencia](compa%C3%B1eroA/tarifas_promociones_A.sql); interfaz que agrega versiones. | PA-11: cruces INSERT/UPDATE, vigencias contiguas, rechazo de ambigüedad y dos altas simultáneas en `dev/verificar_precios_a03.py`. | Verificado en A; conservación de cotización histórica pendiente de integrar con B. |
| DOC-A-01 | [#5 · A-05](https://github.com/Mauriart/BD_IMAX/issues/5) | DBLC 1 | Rechazar razonadamente las seis debilidades del legado y proponer respuesta para cada una. | `docs/factibilidad.md`. | VA-01: seis problemas, solución y riesgos residuales identificados. | Pendiente |
| DOC-A-02 | #5 · A-05 | DBLC 1/2 | Proponer arquitectura técnica/operativa con BD, cómputo, red, seguridad, históricos y continuidad para la escala indicada. | Diagrama y explicación en `docs/factibilidad.md`. | VA-02: supuestos y flujo completos; separar capacidad propuesta y evidencia local. | Pendiente |
| RF-A-08 | [#7 · A-04](https://github.com/Mauriart/BD_IMAX/issues/7) | RN-18 | Rechazar eliminación o cambio incompatible de distribución si existen reservas/ventas activas de funciones de la sala. | Operación real de modificación de sala A; consulta de actividad de B. | PA-12: protección con reserva, con venta y caso permitido sin actividad. | Pendiente de integración con B |
| RNF-A-06 | #7 · A-04 | RN-18; integridad | Impedir que una reserva/venta concurrente evada la protección de sala; conservar referencias e historia. | Coordinación transaccional A/B, definida en diseño. | PA-13: carrera cambio de sala/reserva; ningún resultado deja datos incompatibles. | Pendiente de integración con B |
| RF-A-09 | #7 · A-04 | RN-17/20 | Autorizar cambios permitidos y registrar actor, fecha, acción, sala y motivo mediante C. | Contratos de autorización y auditoría. | PA-07 y PA-12: cambio autorizado auditado; denegación efectiva. | Pendiente de integración con C |
| DOC-A-03 | [#8 · A-07](https://github.com/Mauriart/BD_IMAX/issues/8) | DBLC 4; RN del bloque A | Documentar pruebas positivas/negativas, concurrencia, GUI y restricciones; vincular resultados con requisitos. | `docs/pruebas_a.md`, `tests/cartelera/`, `evidencias/a/` y esta matriz. | PA-14: otro integrante reproduce casos y revisa correspondencia con implementación. | Pendiente |
| DOC-A-04 | #8 · A-07 | Pauta de programación | Preparar demostración reproducible de catálogo, programación, tarifas, cartelera, permisos y salas protegidas. | Guion en `docs/pruebas_a.md`. | PA-15: ensayo desde datos conocidos con rechazos esperados y evidencia SQL/GUI. | Pendiente |
| DOC-A-05 | [#20 · A-06](https://github.com/Mauriart/BD_IMAX/issues/20) | DBLC 1; plan interno | Comparar dos proveedores con capacidades, regiones, disponibilidad y retención equivalentes; proyección de tres años. | Sección económica de `docs/factibilidad.md`. | VA-03: fuentes fechadas, moneda, cantidades y fórmulas reproducibles. | Pendiente |
| DOC-A-06 | #20 · A-06 | DBLC 1; plan interno | Separar inversión inicial y OPEX; calcular costo por millón de transacciones y ROI con supuestos explícitos y volúmenes de C. | Tabla económica y referencia a la versión del dimensionamiento recibido. | VA-04: denominador mensual definido, sin convertir TPS pico en tasa continua ni prometer rentabilidad. | Pendiente de datos de C |

## 2. Registro de pruebas y evidencia

Los códigos anteriores son identificadores de pruebas **previstas**. No se ha ejecutado ninguna prueba por publicar esta matriz.

Para cada PA-xx se registrará en `docs/pruebas_a.md`:

`ID | requisitos cubiertos | precondiciones/dataset | pasos/comando | esperado | obtenido | evidencia | entorno | responsable | fecha`.

Para cada VA-xx se registrará el apartado revisado, fuente y fecha, supuestos, cálculos o criterio usado, hallazgos y resolución. Las comprobaciones documentales no se presentan como pruebas de rendimiento.

Evidencia prevista: `evidencias/a/<id_prueba>/`, con salidas SQL, errores esperados, resultados de concurrencia y capturas pertinentes. Una captura no sustituye la comprobación del estado de BD.

## 3. Límites de responsabilidad y dependencias

| Dependencia | A entrega | A necesita | Cómo avanzar |
| --- | --- | --- | --- |
| B-01 [#6](https://github.com/Mauriart/BD_IMAX/issues/6) | IDs de función/sala/asiento, reglas de distribución y contratos de tarifas. | Modelo de actividad vigente y coordinación para proteger salas. | Fixtures compatibles y pruebas aisladas; después repetir con B real. |
| B-03 [#10](https://github.com/Mauriart/BD_IMAX/issues/10) | Tarifas, vigencias y condiciones promocionales. | Integración de cotización y conservación del precio de compra. | A verifica lo que devuelve; cálculo y checkout corresponden a B. |
| C-01 [#15](https://github.com/Mauriart/BD_IMAX/issues/15) | Acciones/recursos que A necesita autorizar. | Identidad y autorización compartidas. | Adaptador de prueba que permite y deniega; no sustituye verificación final. |
| C-05 [#19](https://github.com/Mauriart/BD_IMAX/issues/19) | Necesidades de arquitectura/costos. | Dimensionamiento con versión y supuestos. | Estimación preliminar identificada; conciliar antes de terminar A-06. |
| C-06 [#21](https://github.com/Mauriart/BD_IMAX/issues/21) | Arquitectura y componentes propuestos. | Políticas de continuidad y riesgos para mantener coherencia documental. | Referenciar aportes de C, sin redactar su módulo. |

Solo cambiar un requisito a **Verificado** cuando existan implementación/documento y evidencia accesibles. Un ensayo con fixtures se marca **Verificado aisladamente; integración pendiente**. La documentación de A-01 ya fue contrastada con el SQL y su verificación. Los demás issues conservan su estado propio.

## 4. Decisiones y mantenimiento

Las decisiones corresponden a Mauriart. Si una cuestión cambia el alcance o el comportamiento del equipo, se le presenta de forma concreta antes de modificar el acuerdo correspondiente.

Los detalles añadidos durante la corrección de `00_acuerdos.md` no se dan por ratificados por haber sido publicados. Al implementar, deben respetarse los acuerdos originales y las decisiones expresas de Mauriart; cualquier detalle añadido que requiera decisión se identifica como tal.

Esta matriz se amplía con rutas reales y resultados a medida que se completa A. No pretende sustituir la trazabilidad de B/C.

## Alcance de cierre de A-02

Mauriart decidió completar A-02 con las pantallas y reglas funcionales de A, y dejar la integración de permisos y auditoría de C en T-02 (#23). No se declara cumplido RF-A-04: se conserva como integración pendiente. La entrega funcional y sus 11 pruebas están documentadas en [interfaz_A.md](compa%C3%B1eroA/interfaz_A.md).
