# Permisos y auditoría del bloque A

## Qué resuelve

Las pantallas administrativas ahora identifican al usuario antes de permitir cambios. Cada operación autorizada guarda quién la hizo, su rol, el motivo y los datos afectados. Ocultar un botón no basta: el servidor también comprueba el permiso al recibir la solicitud y nuevamente dentro de la transacción que modifica los datos.

Esta integración usa el SQL real de C-01, incorporado sin modificaciones desde el commit 8889170f9a883c8a8a2aaa0e4dedf4f1569ce6a5. Se verificó A junto con ese esquema en PostgreSQL; la integración global de T-02 sigue pendiente de los demás módulos.

## Qué hace SQL y qué hace Python

SQL de C conserva usuarios, roles y permisos en usuario, rol y rol_permiso. La función autorizar_accion decide si un usuario activo puede ejecutar una acción. La tabla admin_operacion_audit conserva los eventos administrativos; los triggers de C rechazan UPDATE y DELETE de esos eventos.

Python agrega el inicio y cierre de sesión, verifica la contraseña con su hash y consulta esos permisos. La sesión guarda el ID del usuario y está firmada con una clave local; no se acepta como identidad un ID enviado en el formulario o en una cabecera.

Al guardar, Python vuelve a comprobar usuario y permiso en la misma conexión que realiza el cambio. Mantiene bloqueadas para lectura las filas de identidad y permiso mientras termina esa operación, para coordinarla con una desactivación o revocación concurrente. Después inserta la auditoría antes de confirmar. Si falla el registro, se revierte también el cambio de negocio.

No se añadió un SQL paralelo de usuarios ni otra tabla de auditoría en A. El archivo de C sigue en docs/compañeroC/sql_C-01.sql. La instalación unificada de A conserva su alcance original.

## Acceso según los permisos de C

| Usuario o rol | Acceso en las pantallas de A |
| --- | --- |
| Visitante | Cartelera y consulta pública de precios. |
| Administrador | Catálogo, salas, zonas, asientos, funciones, categorías, tarifas y promociones. |
| Contador | Consulta administrativa de tarifas y promociones, sin formularios de modificación. |
| Cliente, taquillero y puerta | Consulta pública; sin acceso a modificaciones administrativas de A. |

La tabla describe los permisos iniciales de C. Si cambian en rol_permiso, la aplicación consulta la configuración vigente.

Los cambios requieren un motivo de hasta 500 caracteres. Los formularios incluyen un token CSRF para rechazar envíos sin el token de esa sesión. El cierre de sesión también requiere un formulario válido. Las cookies se configuran como HttpOnly y SameSite=Lax; el período de sesión se configura en 30 minutos.

## Preparar el acceso local

Desde dev, con la conexión a p2 ya configurada:

    .\.venv\Scripts\python.exe configurar_acceso.py

El programa genera SECRET_KEY en el archivo local .env si falta. Conserva una clave válida existente y rechaza una demasiado corta. Los archivos .env están excluidos por dev/.gitignore.

Si no existe ninguna de las siete tablas de C, instala su SQL original. Si están todas, las conserva; una instalación parcial se rechaza para evitar sobrescribirla.

Luego solicita el correo de un usuario existente, por ejemplo admin@imax.test, y una contraseña elegida localmente de al menos 12 caracteres. Solo reemplaza el marcador HASH_DE_PRUEBA. No crea usuarios, no cambia roles y no reemplaza contraseñas ya configuradas. No hay una contraseña predeterminada utilizable.

Reiniciar la aplicación después de preparar el acceso y entrar desde Iniciar sesión. Se puede repetir el programa para preparar otro usuario de prueba cuyo marcador siga intacto.

## Qué queda registrado

Cada alta o edición de A guarda actor, rol al actuar, IP de la conexión, acción, entidad, ID, motivo y datos anteriores/posteriores cuando corresponda. La película incluye sus géneros y la promoción sus condiciones. Con C-01, un lote de asientos genera un evento con fila, rango, zona y cantidad. Con los triggers de C-03, genera un evento por asiento y no agrega otro evento manual para el mismo cambio.

Un cambio rechazado no genera un evento de éxito. El inicio de sesión y los intentos denegados no se registran en esta tabla. Los cambios hechos directamente en DBeaver por el propietario de la base quedan fuera de esta auditoría de aplicación.

## Verificación

Se ejecutaron 47 pruebas automatizadas con esquemas temporales independientes de los datos de trabajo:

| Archivo en dev | Pruebas aprobadas | Cobertura |
| --- | ---: | --- |
| verificar_a02.py | 11 | Catálogo, salas, asientos y programación, incluida concurrencia. |
| verificar_cartelera_a03.py | 5 | Cartelera y filtros. |
| verificar_precios_a03.py | 11 | Tarifas, condiciones promocionales y concurrencia. |
| verificar_seguridad_a.py | 15 | Sesiones, permisos reales de C, CSRF y auditoría transaccional. |
| verificar_compatibilidad_c03.py | 5 | Funciones reales de C-03: guardias, once escrituras sin duplicación, trigger deshabilitado y reversión ante fallos. |

La suite de seguridad comprueba acceso por URL, identidad manipulada, roles sin permiso, contador sin escritura, contraseñas inválidas, sesión falsificada, usuario desactivado, permiso revocado y revalidación dentro de la operación. También comprueba auditoría en las once variantes de escritura, ausencia de evento de éxito al fallar un lote y reversión del cambio si falla la auditoría.

Verifica además que falten configuración o permisos sin abrir el acceso, que el cierre de sesión invalide el formulario anterior y que la preparación de acceso conserve roles, contraseñas ya configuradas y la clave local.

Se revisaron en navegador el inicio y cierre de sesión, el formulario de edición con motivo y la consulta del contador sin acciones de escritura. Las cuentas utilizadas para esa revisión pertenecían al esquema temporal.

Para repetir, ejecutar cada archivo con el Python del entorno virtual desde dev, por ejemplo:

    .\.venv\Scripts\python.exe verificar_seguridad_a.py

## Pendientes de integración

La protección de salas con reservas o ventas de A-04 todavía requiere el modelo y la coordinación transaccional de B. El acceso y la auditoría de A no resuelven esa dependencia. T-02 permanece abierto para la integración completa.

Estos ensayos tampoco demuestran retención de cinco años, capacidad de producción ni protección contra el propietario de PostgreSQL. Son evidencia del comportamiento funcional de A con el contrato real de C.


## Compatibilidad con C-03

A envía app.id_usuario, app.ip y app.motivo mediante set_config con alcance local a la transacción. El usuario procede de la sesión autenticada y se vuelve a validar junto con su permiso. C-03 puede leer ese contexto desde sus guardias y triggers.

Después de escribir, A comprueba si la tabla tiene instalado y habilitado el trigger de fila auditar_cambio_critico para INSERT o UPDATE, según corresponda. En ese caso, el trigger ya registró el cambio y A omite la inserción manual. Si no está instalado o está deshabilitado, A conserva su registro explícito: usa auditar_accion si esa función de C está disponible, o la tabla de C-01 en caso contrario.

La auditoría automática de C-03 guarda los campos de la fila afectada. Las asociaciones de géneros y las condiciones promocionales continúan guardándose atómicamente, pero sus listas completas solo forman parte del evento explícito de A; el trigger de la fila padre no incluye esas asociaciones. La cobertura de auditoría de esas relaciones debe conciliarse al integrar el módulo completo de C-03. No se declara cubierta por estas cinco pruebas.

Se comprobó con las cuatro funciones reales normalizar_ip, auditar_accion, guardia_rbac y auditar_cambio_critico del SQL de C-03, commit f19dd9b01fc643805b2cb0baefc334fee7b2b0a1. El ensayo extrae esas funciones del archivo recibido, adapta únicamente su search_path al esquema temporal y monta los triggers correspondientes a A. No ejecuta el script completo ni instala reembolsos, privilegios o cambios de B en public.

Para reproducir con esa versión, desde dev:

    git show f19dd9b01fc643805b2cb0baefc334fee7b2b0a1:docs/compañeroC/sql_c-03.sql | Set-Content -Encoding utf8 "$env:TEMP/imax_c03_prueba.sql"
    .\.venv\Scripts\python.exe verificar_compatibilidad_c03.py "$env:TEMP/imax_c03_prueba.sql"

El commit debe estar disponible localmente; se obtiene al traer la rama c-03-rbac-reembolsos-auditoria. Cuando su SQL esté integrado, se puede pasar directamente la ruta del archivo en docs/compañeroC.

Este ensayo acredita la compatibilidad de las escrituras actuales de A con esos mecanismos. No acredita el check-in, los reembolsos, las cortesías ni el módulo completo de C. La aplicación local y las pruebas no instalan C-03 automáticamente.
