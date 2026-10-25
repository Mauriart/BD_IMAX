# Pruebas del módulo A

## Estado y evidencia actual

El bloque A está integrado con reserva, pago, boleto, ingreso, reembolso y reportes de B/C. Se aprobaron 97 casos automatizados en PostgreSQL real: los 47 anteriores, 17 de protección de salas, 10 con operaciones reales de B y 23 de integración global. Los casos PA agrupan esos métodos; no son pruebas adicionales.

La versión operativa de referencia es el [PR #40](https://github.com/Mauriart/BD_IMAX/pull/40), commit d54eae7271aa7e02ab5caf57ed11f85ada776a55. Esta actualización documenta sus resultados y la configuración inicial del 2x1 para miércoles. El instalador global contiene 33 tablas; quince corresponden al esquema de A. La primera entrega de A-01, documentada en [pruebas_a.md](pruebas_a.md), tenía doce.

Entorno: Windows, Python 3.14.7, PostgreSQL 18.6, Flask 3.1.3 y psycopg 3.3.6. Cada suite usa esquemas temporales propios y conexiones separadas para la concurrencia. La base personal no recibe compras ni pagos de ensayo.

| Suite en dev | Aprobadas | Salida real actual |
| --- | ---: | --- |
| verificar_a02.py | 11 | [Catálogo y horarios](../integracion/evidencias/verificar_a02.txt) |
| verificar_cartelera_a03.py | 5 | [Cartelera](../integracion/evidencias/verificar_cartelera_a03.txt) |
| verificar_precios_a03.py | 11 | [Tarifas y promociones](../integracion/evidencias/verificar_precios_a03.txt) |
| verificar_seguridad_a.py | 15 | [Permisos y auditoría](../integracion/evidencias/verificar_seguridad_a.txt) |
| verificar_compatibilidad_c03.py | 5 | [Compatibilidad C-03](../integracion/evidencias/verificar_compatibilidad_c03.txt) |
| verificar_salas_a04.py | 17 | [Distribución protegida](../integracion/evidencias/verificar_salas_a04.txt) |
| verificar_integracion_b_a04.py | 10 | [Reserva/pago reales de B](../integracion/evidencias/verificar_integracion_b_a04.txt) |
| verificar_integracion_global.py | 23 | [Flujo A/B/C](../integracion/evidencias/verificar_integracion_global.txt) |
| Total | 97 | Todas aprobadas. |

Las salidas anteriores de compañeroA/evidencias conservan su versión original. Las capturas del [mapa](../integracion/evidencias/mapa.png), [dashboard](../integracion/evidencias/reportes.png) y [puerta](../integracion/evidencias/puerta.png) corresponden a una revisión real en navegador con datos sintéticos. Formularios y QR también se comprueban con el cliente Flask. La [verificación local](../integracion/evidencias/verificacion_local_A07.txt) registra el estado de p2 y del programa.

## Cómo repetir

Desde dev, con PostgreSQL y .env local configurados, usar el Python del entorno sin activarlo:

    .\.venv\Scripts\python.exe verificar_a02.py
    .\.venv\Scripts\python.exe verificar_cartelera_a03.py
    .\.venv\Scripts\python.exe verificar_precios_a03.py
    .\.venv\Scripts\python.exe verificar_seguridad_a.py
    .\.venv\Scripts\python.exe verificar_compatibilidad_c03.py ..\docs\compañeroC\sql_C-03.sql
    .\.venv\Scripts\python.exe verificar_salas_a04.py --c03 ..\docs\compañeroC\sql_C-03.sql
    .\.venv\Scripts\python.exe verificar_integracion_b_a04.py
    .\.venv\Scripts\python.exe verificar_integracion_global.py

Cada salida debe terminar en OK. Una suite omitida no cuenta como aprobada. Las dos rutas de C-03 apuntan al SQL incluido en el repositorio; no requieren archivos privados de otra rama. La última suite instala el SQL completo en su esquema temporal.

Para repetir un caso:

    .\.venv\Scripts\python.exe verificar_a02.py PruebasA02.test_programacion_simultanea

## Casos vinculados a requisitos

Los PA identifican grupos de comprobaciones de la matriz, no pruebas adicionales. Los métodos concretos y sus subcasos están en las suites indicadas. Los valores son datos de ensayo; los scripts no requieren los IDs de la base personal.

| Caso y requisitos | Precondición | Pasos comprobados | Esperado y obtenido | Evidencia |
| --- | --- | --- | --- | --- |
| PA-01 · RF-A-02 | Catálogo temporal y administrador autenticado. | Crear película completa, intentar metadatos incompletos y editar título. | Alta/edición válidas aceptadas; datos incompletos rechazados. Aprobado. | verificar_a02: test_metadatos_pelicula y test_editar_pelicula. |
| PA-02 · RF-A-03, RNF-A-01 | Cine y zona de ensayo. | Crear sala/zona, generar asientos y repetir una ubicación dentro de un lote. | Capacidad calculada desde los asientos; duplicado rechazado sin guardar un lote parcial. Aprobado. | verificar_a02: test_salas_zonas_y_lote; seguridad: test_lote_rechazado_no_genera_auditoria_de_exito. |
| PA-03 · RF-A-03 | Película de 120 minutos y cine America/Costa_Rica. | Programar función usando hora local y comprobar inicio/final almacenados. | Conversión horaria y duración correctas. Aprobado. | verificar_a02: test_creacion_duracion_y_zona_horaria. |
| PA-04 · RNF-A-04 | Función de 18:00 a 20:00 en una sala. | Probar cruces y un inicio a las 20:10; después probar 20:15. | Cruces y limpieza insuficiente rechazados; límite exacto permitido. Aprobado. | verificar_a02: test_traslapes_y_limpieza. |
| PA-05 · RF-A-03, RNF-A-04 | Funciones y vínculos válidos. | Editar a un horario incompatible, reactivar una función incompatible y cambiar la sala de una función con tarifas. | Rechazos conservan el estado válido anterior. Aprobado. La protección específica por ventas se comprueba en PA-12. | verificar_a02: test_edicion_y_horario_original, test_inactiva_y_reactivacion y test_sala_con_tarifas_protegida. |
| PA-06 · RNF-A-04 | Dos conexiones independientes programando la misma sala. | Mantener la primera escritura sin confirmar, iniciar la segunda, comprobar espera y confirmar la primera. | Segunda operación espera y rechaza el cruce; queda una sola función. Aprobado. | verificar_a02: test_programacion_simultanea. |
| PA-07 · RF-A-04, RN-17/20 | Usuarios y permisos reales de C-01; escrituras de A. | Probar rol permitido/denegado, sesión/CSRF inválidos, revocación, once escrituras y fallos de auditoría. Repetir los mecanismos pertinentes con funciones de C-03. | Acceso protegido; actor de sesión y motivo registrados; fallo revierte el cambio; sin duplicación por auditoría automática. Aprobado en el alcance descrito abajo. | Las 15 pruebas de seguridad y las 5 de compatibilidad. |
| PA-08 · RF-A-05 | Funciones futuras, pasadas e inactivas; películas con varios géneros. | Combinar filtros por cine/fecha/género y consultar sin coincidencias. | Solo funciones futuras activas; fecha local correcta y sin horarios duplicados. Aprobado. | Las 5 pruebas de cartelera. |
| PA-09 · RF-A-06 | Función, zona de su sala y categorías. | Registrar tarifa/categoría, consultar matriz y probar zona ajena o valores inválidos. | Montos y acreditación correctos; vínculos inválidos rechazados. Aprobado. | precios: test_formulario_tarifa_categoria_y_matriz_publica y test_datos_invalidos_no_guardan_y_zona_ajena. |
| PA-10 · RF-A-07 | Promoción con vigencia, días, zonas y categorías. | Consultar límites/filtros y provocar un fallo en la última condición de una nueva promoción. | Solo se ofrecen promociones aplicables; la operación fallida no deja registros parciales. Aprobado. | precios: test_promocion_estructurada_filtros_y_limites, test_dia_de_funcion_local_y_promocion_antigua_incompleta, test_promocion_invalida_no_deja_registros_parciales y test_fallo_en_ultima_condicion_revierte_toda_promocion. |
| PA-11 · RNF-A-05 | Tarifas de la misma función/zona/categoría. | Probar límites, vigencias cruzadas/contiguas y dos altas simultáneas. Comprobar ambigüedad aun sin trigger. | Inicio incluido/final excluido; cruces rechazados, vigencias contiguas aceptadas y sin cotización ambigua. Aprobado. | precios: test_vigencia_desde_incluido_hasta_excluido_y_decimal, test_cruces_rechazados_y_vigencias_contiguas_permitidas, test_tarifas_simultaneas y test_ambiguedad_no_cotiza_aun_sin_trigger. |
| PA-12 · RF-A-08/09 | Sala con reserva, boleto o historia de B; administrador con motivo. | Intentar borrar asiento, trasladar zona y reprogramar; repetir un borrado permitido y provocar fallo de auditoría. | Cambios incompatibles rechazados, historia conservada y cambio permitido auditado; fallo revierte. Aprobado. | verificar_salas_a04: test_reserva_activa_rechaza_borrado_y_nuevos_asientos, test_emitido_y_usado_protegen_la_sala, test_historia_no_se_elimina, test_borrado_permitido_auditado_y_pantalla y test_fallo_auditoria_revierte_borrado; integración B: test_reserva_real_protege_distribucion y test_pago_real_emite_boleto_y_protege. |
| PA-13 · RNF-A-06 | Conexiones independientes en READ COMMITTED, misma sala e inventario. | Ejecutar primero reserva y después borrado; invertir el orden y observar espera y revalidación. | Operación incompatible rechazada sin referencias rotas. Aprobado en ambos órdenes. | verificar_salas_a04: test_concurrencia_reserva_primero_rechaza_borrado y test_concurrencia_borrado_primero_rechaza_reserva; integración B: test_concurrencia_reserva_real_primero_rechaza_borrado y test_concurrencia_borrado_primero_reserva_real_espera_y_revalida. |
| PA-14 · DOC-A-03 | SQL, interfaz y evidencia de la misma integración. | Repetir ocho suites, comprobar 33 tablas, enlaces y respuestas del programa. | 97 casos aprobados; documentación contrastada con código y resultados. Reproducción técnica local realizada. | Ocho salidas actuales y verificacion_local_A07.txt. No se afirma una ejecución en otra computadora. |
| PA-15 · DOC-A-04 | Guion, usuarios locales y datos de práctica. | Contrastar pasos con casos ejecutados y pantallas revisadas; incluir reserva y protección de salas. | Guion actualizado y comprobaciones técnicas aprobadas. La práctica oral del equipo sigue por realizar. | [Guion](guion_defensa_A.md), PA-01 a PA-13 y suite global: test_checkout_web_factura_qr_y_propiedad y test_venta_presencial_y_reembolso_desde_interfaz. |

Los nombres abreviados de las suites en la tabla corresponden a los ocho archivos completos del cuadro de evidencias. Las salidas permiten localizar los métodos y confirmar que se ejecutaron.

## Alcance de SQL, Python e interfaz

SQL mantiene claves, referencias, restricciones de integridad y triggers de horario/vigencia. Python recibe los formularios, valida entradas, consulta permisos, organiza las transacciones y presenta resultados. La interfaz sirve para ejecutar esas operaciones; esconder controles no sustituye la autorización del servidor.

Las pruebas automatizadas usan solicitudes reales al servidor Flask mediante su cliente de pruebas y PostgreSQL real. Las pruebas de concurrencia abren conexiones separadas. No son clics automatizados en un navegador ni una medición de capacidad mundial.

Las cinco pruebas de compatibilidad extraen mecanismos concretos de C-03. Las 23 globales sí instalan A/B/C y cubren compra web/presencial, 2x1 impar, miércoles frente a jueves, precio congelado, pago repetido, vencimiento, QR y acreditación, reembolso parcial, cortesía, cambio de asiento y reportes. También comprueban 50 reservas y 50 escaneos simultáneos: un éxito por carrera y 49 rechazos.

## Uso en el informe y límites

Este registro es material para el apartado de pruebas del informe final. No demuestra capacidad mundial, recuperación ante desastre ni todos los órdenes posibles de SQL administrativo. Una transacción incompatible puede abortarse; un reintento de pago conserva su referencia de idempotencia.

Mauriart autorizó integrar sin revisión obligatoria de otro integrante. La comprobación técnica local está realizada; no se declara una reproducción en otra computadora ni un ensayo oral humano. El guion queda preparado para esa práctica.

A-06 conserva el cierre económico. La conciliación del Chen global, la evidencia de rendimiento de C-07 y el documento técnico final siguen en sus tareas. La organización definitiva del repositorio se hará después del informe final: un SQL completo, un informe y los archivos del programa ordenados. Mientras tanto se conservan documentos de trabajo e historia.
