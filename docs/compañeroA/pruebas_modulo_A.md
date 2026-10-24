# Pruebas del módulo A

## Estado de A-07

Este documento reúne las pruebas de catálogo, distribución, programación, cartelera, tarifas, promociones, permisos y auditoría. Hay 47 pruebas automatizadas aprobadas. A-07 continúa abierto: faltan los casos de protección de salas con reservas o ventas de A-04, la integración completa y el ensayo final del guion.

Las comprobaciones iniciales del esquema de A-01 permanecen en [pruebas_a.md](pruebas_a.md). Sus doce tablas y pendientes describen aquella entrega; A-03 añadió las tres tablas de condiciones promocionales. La instalación actual de A tiene quince tablas. No se suman los ensayos manuales antiguos a las 47 pruebas automatizadas.

## Evidencia y entorno

El código probado corresponde a la entrega de permisos y auditoría del [PR #32](https://github.com/Mauriart/BD_IMAX/pull/32), commit 5496c40a71ec65f1ec3d33b9cfdc310ec68d2de3. Esta entrega de A-07 agrega documentación y conserva las salidas de esas ejecuciones; no cambia las reglas del programa.

Entorno consultado al reunir las evidencias: Windows, Python 3.14.7, PostgreSQL 18.6, Flask 3.1.3 y psycopg 3.3.6. Los ensayos crean esquemas propios dentro de la base configurada, revierten sus datos y eliminan esos esquemas al terminar. Se comprobó que no quedaron esquemas ensayo_a02_ pendientes.

| Suite en dev | Aprobadas | Salida real |
| --- | ---: | --- |
| verificar_a02.py | 11 | [Catálogo, distribución y horarios](evidencias/verificar_a02.txt) |
| verificar_cartelera_a03.py | 5 | [Cartelera y filtros](evidencias/verificar_cartelera_a03.txt) |
| verificar_precios_a03.py | 11 | [Tarifas y promociones](evidencias/verificar_precios_a03.txt) |
| verificar_seguridad_a.py | 15 | [Sesiones, permisos y auditoría](evidencias/verificar_seguridad_a.txt) |
| verificar_compatibilidad_c03.py | 5 | [Compatibilidad con C-03](evidencias/verificar_compatibilidad_c03.txt) |
| Total | 47 | Sin fallas en las ejecuciones registradas. |

Las cuatro primeras salidas se conservaron de la ejecución que validó el PR #32. La quinta se capturó nuevamente al preparar esta documentación, con las funciones del mismo SQL de C-03 usado en aquella validación. Cada archivo muestra los nombres de los casos, la cantidad ejecutada y el resultado de unittest; no es una salida reconstruida a partir de resultados esperados.

Las revisiones de pantallas se describen en [interfaz_A.md](interfaz_A.md) y [permisos_auditoria_A.md](permisos_auditoria_A.md). Aquí no se adjuntan capturas nuevas ni se afirma haber realizado el ensayo completo de defensa.

## Cómo repetir

Desde dev, con el archivo .env local y PostgreSQL disponibles, ejecutar cada suite con el Python del entorno. No hace falta activarlo:

    .\.venv\Scripts\python.exe verificar_a02.py
    .\.venv\Scripts\python.exe verificar_cartelera_a03.py
    .\.venv\Scripts\python.exe verificar_precios_a03.py
    .\.venv\Scripts\python.exe verificar_seguridad_a.py

Estas cuatro suites comprueban 42 casos. Al final de cada una debe aparecer OK. Un fallo de conexión o una suite omitida no equivale a un resultado aprobado.

Las cinco pruebas restantes necesitan recibir el SQL real de C-03, versión f19dd9b01fc643805b2cb0baefc334fee7b2b0a1. La forma de obtenerlo y pasar su ruta está en [permisos_auditoria_A.md](permisos_auditoria_A.md#compatibilidad-con-c-03). El ensayo solo extrae cuatro funciones y monta los triggers de A en su esquema temporal; no instala el módulo completo de C-03 ni sus reembolsos.

Para repetir un solo caso se puede indicar la clase y el método después del nombre del archivo. Por ejemplo:

    .\.venv\Scripts\python.exe verificar_a02.py PruebasA02.test_programacion_simultanea

## Casos vinculados a requisitos

Los PA identifican grupos de comprobaciones de la matriz, no pruebas adicionales. Los métodos concretos y sus subcasos están en las suites indicadas. Los valores son datos de ensayo; los scripts no requieren los IDs de la base personal.

| Caso y requisitos | Precondición | Pasos comprobados | Esperado y obtenido | Evidencia |
| --- | --- | --- | --- | --- |
| PA-01 · RF-A-02 | Catálogo temporal y administrador autenticado. | Crear película completa, intentar metadatos incompletos y editar título. | Alta/edición válidas aceptadas; datos incompletos rechazados. Aprobado. | verificar_a02: test_metadatos_pelicula y test_editar_pelicula. |
| PA-02 · RF-A-03, RNF-A-01 | Cine y zona de ensayo. | Crear sala/zona, generar asientos y repetir una ubicación dentro de un lote. | Capacidad calculada desde los asientos; duplicado rechazado sin guardar un lote parcial. Aprobado. | verificar_a02: test_salas_zonas_y_lote; seguridad: test_lote_rechazado_no_genera_auditoria_de_exito. |
| PA-03 · RF-A-03 | Película de 120 minutos y cine America/Costa_Rica. | Programar función usando hora local y comprobar inicio/final almacenados. | Conversión horaria y duración correctas. Aprobado. | verificar_a02: test_creacion_duracion_y_zona_horaria. |
| PA-04 · RNF-A-04 | Función de 18:00 a 20:00 en una sala. | Probar cruces y un inicio a las 20:10; después probar 20:15. | Cruces y limpieza insuficiente rechazados; límite exacto permitido. Aprobado. | verificar_a02: test_traslapes_y_limpieza. |
| PA-05 · RF-A-03, RNF-A-04 | Funciones y vínculos válidos. | Editar a un horario incompatible, reactivar una función incompatible y cambiar la sala de una función con tarifas. | Rechazos conservan el estado válido anterior. Aprobado. Esta última protección no demuestra la de ventas de A-04. | verificar_a02: test_edicion_y_horario_original, test_inactiva_y_reactivacion y test_sala_con_tarifas_protegida. |
| PA-06 · RNF-A-04 | Dos conexiones independientes programando la misma sala. | Mantener la primera escritura sin confirmar, iniciar la segunda, comprobar espera y confirmar la primera. | Segunda operación espera y rechaza el cruce; queda una sola función. Aprobado. | verificar_a02: test_programacion_simultanea. |
| PA-07 · RF-A-04, RN-17/20 | Usuarios y permisos reales de C-01; escrituras de A. | Probar rol permitido/denegado, sesión/CSRF inválidos, revocación, once escrituras y fallos de auditoría. Repetir los mecanismos pertinentes con funciones de C-03. | Acceso protegido; actor de sesión y motivo registrados; fallo revierte el cambio; sin duplicación por auditoría automática. Aprobado en el alcance descrito abajo. | Las 15 pruebas de seguridad y las 5 de compatibilidad. |
| PA-08 · RF-A-05 | Funciones futuras, pasadas e inactivas; películas con varios géneros. | Combinar filtros por cine/fecha/género y consultar sin coincidencias. | Solo funciones futuras activas; fecha local correcta y sin horarios duplicados. Aprobado. | Las 5 pruebas de cartelera. |
| PA-09 · RF-A-06 | Función, zona de su sala y categorías. | Registrar tarifa/categoría, consultar matriz y probar zona ajena o valores inválidos. | Montos y acreditación correctos; vínculos inválidos rechazados. Aprobado. | precios: test_formulario_tarifa_categoria_y_matriz_publica y test_datos_invalidos_no_guardan_y_zona_ajena. |
| PA-10 · RF-A-07 | Promoción con vigencia, días, zonas y categorías. | Consultar límites/filtros y provocar un fallo en la última condición de una nueva promoción. | Solo se ofrecen promociones aplicables; la operación fallida no deja registros parciales. Aprobado. | precios: test_promocion_estructurada_filtros_y_limites, test_dia_de_funcion_local_y_promocion_antigua_incompleta, test_promocion_invalida_no_deja_registros_parciales y test_fallo_en_ultima_condicion_revierte_toda_promocion. |
| PA-11 · RNF-A-05 | Tarifas de la misma función/zona/categoría. | Probar límites, vigencias cruzadas/contiguas y dos altas simultáneas. Comprobar ambigüedad aun sin trigger. | Inicio incluido/final excluido; cruces rechazados, vigencias contiguas aceptadas y sin cotización ambigua. Aprobado. | precios: test_vigencia_desde_incluido_hasta_excluido_y_decimal, test_cruces_rechazados_y_vigencias_contiguas_permitidas, test_tarifas_simultaneas y test_ambiguedad_no_cotiza_aun_sin_trigger. |
| PA-12 · RF-A-08/09 | Reserva o venta activa de B en la sala. | Intentar cambio/eliminación incompatible; probar cambio permitido y auditarlo. | Pendiente de A-04/B; no ejecutado ni declarado aprobado. | Sin evidencia todavía. |
| PA-13 · RNF-A-06 | Reserva/venta de B simultánea a un cambio de distribución de A. | Coordinar ambas operaciones y verificar que ninguna deja referencias incompatibles. | Pendiente del protocolo de bloqueo A/B. La concurrencia de horarios no sustituye este caso. | Sin evidencia todavía. |
| PA-14 · DOC-A-03 | Documentación, código y salidas accesibles. | Revisar nombres, enlaces y correspondencia; reproducir con otro entorno. | Documentación y evidencia organizadas; reproducción por otro entorno pendiente. | Este documento y las cinco salidas. |
| PA-15 · DOC-A-04 | Base de ensayo y usuarios con contraseña local. | Ejecutar el guion de defensa y, después de A-04, agregar la protección con reservas/ventas. | Guion preparado; ensayo completo y sección A-04 pendientes. | [guion_defensa_A.md](guion_defensa_A.md). |

Los nombres abreviados de las suites en la tabla corresponden a los cinco archivos completos del cuadro de evidencias. Las salidas permiten localizar los métodos y confirmar que se ejecutaron.

## Alcance de SQL, Python e interfaz

SQL mantiene claves, referencias, restricciones de integridad y triggers de horario/vigencia. Python recibe los formularios, valida entradas, consulta permisos, organiza las transacciones y presenta resultados. La interfaz sirve para ejecutar esas operaciones; esconder controles no sustituye la autorización del servidor.

Las pruebas automatizadas usan solicitudes reales al servidor Flask mediante su cliente de pruebas y PostgreSQL real. Las pruebas de concurrencia abren conexiones separadas. No son clics automatizados en un navegador ni una medición de capacidad mundial.

La auditoría con C-03 se verificó con sus cuatro funciones y triggers pertinentes a A. El ensayo no cubre su módulo completo, reembolsos, privilegios de la cuenta técnica ni check-in. Las listas completas de asociaciones requieren la conciliación descrita en permisos_auditoria_A.md. Las pruebas tampoco acreditan que B calcule el 2x1 o conserve precios históricos de la compra.

## Qué falta para completar A-07

Faltan PA-12 y PA-13 con B real, incorporar sus resultados a esta evidencia y ensayar el guion completo. También debe comprobarse la ejecución en otro entorno antes de declarar reproducible la entrega final. La factibilidad económica A-06 y la consolidación del informe general conservan sus tareas propias.

Este material sirve como base del apartado de pruebas del informe final. Al juntar los bloques se describe lo efectivamente integrado y se conserva la distinción entre resultados obtenidos y casos pendientes.
