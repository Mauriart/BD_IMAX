# Acuerdos del equipo — Proyecto II: Base de datos IMAX

Versión 1.1 · 15 de octubre de 2026  
Repositorio: [Mauriart/BD_IMAX](https://github.com/Mauriart/BD_IMAX)  
Relacionado con [T-01 / issue #1](https://github.com/Mauriart/BD_IMAX/issues/1).

Este documento fija la base común para desarrollar los tres módulos. Sustituye el borrador `00_acuerdos.pdf` y prevalece sobre las recomendaciones organizativas de la guía cuando exista una diferencia. Describe acuerdos de implementación; publicar este archivo no significa que el DER, la aplicación o las pruebas ya estén terminados ni que se haya realizado una revisión de los tres integrantes.

## 1. Alcance y fuentes

El prototipo debe demostrar el flujo:

**Programación → cartelera → reserva → pago simulado → boleto QR → ingreso**, con roles, reembolsos, reportes y auditoría.

Se entregarán las cinco fases DBLC, DER, modelo relacional, normalización, diccionario, SQL, GUI y evidencias en el repositorio público. Los pagos serán simulados. La arquitectura global se justifica documentalmente; las pruebas locales demuestran integridad y comportamiento del prototipo.

Fuentes revisadas:

- Consigna: `Proyecto II - Diseño desde Cero de una BD.pdf`.
- Borrador del equipo: `00_acuerdos.pdf`.
- Guía interna: `Guia_Trabajo_Proyecto_II_BD_IMAX.md`.
- Issues A-01 a A-07, B-01 a B-07, C-01 a C-07 y T-01 a T-03 del repositorio.

Las RN-01 a RN-20 proceden de la consigna. Las versiones, políticas numéricas adoptadas, división de trabajo, 50 solicitudes de prueba, comparación de dos proveedores y proyección económica de tres años son decisiones del equipo.

### Datos de escala y correcciones de interpretación

| Concepto | Base documental |
| --- | --- |
| Concurrencia global propuesta | 8 millones de usuarios concurrentes; el PDF usa referencias distintas al primer minuto y a la primera hora. Se declara esta ambigüedad y se separan concurrencia y tasa de llegada. |
| Pico | 50 000 TPS durante 10 minutos: 30 millones de operaciones en esa ventana; no implica 30 millones de ventas. |
| Operación | 1 500 salas y **500 funciones diarias**. No sustituir funciones por títulos. |
| Ventas | 15 millones de boletos mensuales; 900 millones en 60 meses, antes de crecimiento. |
| Auditoría | Retención mínima de cinco años; dimensionar eventos adicionales a los boletos. |

La capacidad media, distribución de funciones y ocupación se declararán como supuestos y se comprobará su coherencia con el volumen de ventas. No se extrapolará el TPS pico a todo el mes.

RPO ≤ 5 segundos, RTO < 5 minutos y SLA de 99,99 % se mantienen como **objetivos internos de la propuesta global**, sujetos a justificación de arquitectura, costos y riesgos; no son cifras exigidas por el PDF revisado ni resultados medidos del prototipo.

## 2. Equipo y responsabilidades

| Bloque | Responsable | Dominio |
| --- | --- | --- |
| A | `Mauriart` | Catálogo, cines, salas, programación, tarifas, promociones, arquitectura y costos. |
| B | `keilynsolanotencio-dev` | Inventario por función, reservas, compras, pagos, boletos, reversión y concurrencia. |
| C | `IanDavid1406` | Identidad, roles, puerta, gestión de reembolsos, reportes, auditoría y continuidad. |
| Compartido | Los tres | Acuerdos, DER global, integración, trazabilidad y entrega final. |

Cada integrante desarrolla diseño, SQL, interfaz, pruebas y documentación de su dominio. La integración se realiza desde las primeras operaciones, sin esperar a terminar todas las pantallas.

La propiedad de una tabla identifica al módulo que coordina su esquema y operaciones. Otros módulos consultan mediante contratos compartidos y solicitan cambios mediante operaciones del propietario. Esto no divide una transacción de negocio en commits independientes: una venta o reversión y sus registros asociados deben poder ejecutarse en una sola transacción.

## 3. Herramientas y ejecución común

| Elemento | Acuerdo |
| --- | --- |
| Base de datos | PostgreSQL **17.x**; misma versión mayor para todos. Registrar la revisión exacta usada en las pruebas. |
| Cliente SQL | pgAdmin 4 o `psql`; ambos utilizan los mismos scripts. |
| Lenguaje | Python **3.12.x**, entorno virtual `.venv`. |
| Aplicación | Un único proyecto Flask, con fábrica `create_app` en `src/__init__.py` y módulos por dominio. |
| Interfaz | HTML/CSS con plantillas Jinja y JavaScript para mapa, actualización de estados y lectura/simulación de QR. |
| Acceso a datos | Psycopg 3 y SQL parametrizado; sin un segundo modelo paralelo mediante ORM. |
| Dependencias | `Flask`, `psycopg[binary]`, `qrcode[pil]`, `Faker` y `python-dotenv`; `pytest` para pruebas. Fijar versiones exactas al crear el entorno común. |
| Contraseñas y sesiones | Hash de contraseñas mediante Werkzeug, sesión Flask y clave secreta fuera de Git. |
| Diagramas | draw.io; conservar fuente editable y exportación en `docs/modelos/`. |
| Control de versiones | Git y GitHub; GitHub Desktop es opcional. |
| Seguimiento | **Issues y pull requests. No se utilizará GitHub Projects.** |
| Concurrencia | Script Python con 50 trabajadores, barrera de inicio y una conexión independiente por trabajador. |

### Contrato de instalación local

La implementación deberá cumplir esta secuencia, que se documentará con comandos comprobados en `docs/guia_trabajo.md`. Por decisión de Mauriart se omite ampliar el README como entregable:

1. Instalar PostgreSQL 17 y Python 3.12; crear la base vacía `imax` y los roles técnicos de instalación/aplicación.
2. Crear/activar `.venv` e instalar `requirements.txt`.
3. Copiar `.env.example` a `.env`; definir `DATABASE_URL` y `SECRET_KEY`. El archivo real queda excluido de Git.
4. Ejecutar `sql/instalar.sql` con `psql`, deteniéndose ante errores. Ese archivo incluirá explícitamente los SQL en el orden correcto.
5. Cargar el conjunto sintético de demostración. Los datos masivos se generan aparte.
6. Ejecutar `python -m flask --app src:create_app run --host 127.0.0.1 --port 5000`.
7. Abrir la aplicación desde dos sesiones de navegador para comprobar estados compartidos.

El servidor de desarrollo se usa en la demostración local. La propuesta de producción describe despliegue, conexiones y seguridad por separado. Esta sección define el contrato de ejecución; los archivos de aplicación e instalación se incorporarán en sus tareas.

## 4. Convenciones de datos

- Tablas y columnas en español, singular y `snake_case`, sin tildes: `funcion`, `id_funcion`.
- PK simples: `id_<tabla>`, tipo `BIGINT GENERATED ALWAYS AS IDENTITY`.
- Tablas puente e inventario pueden tener PK compuesta; documentar cada excepción en el diccionario.
- FK con el nombre de la PK referida; cuando hay varios vínculos a la misma tabla, usar un sufijo semántico, por ejemplo `id_usuario_actor`.
- Montos individuales: `NUMERIC(12,2)`; cálculos en Python con `Decimal`, nunca `float`. No reducir artificialmente el rango de agregados financieros.
- Moneda del prototipo: **USD**, código de tres caracteres y restricción para ese valor. No sumar monedas distintas.
- Redondeo comercial a dos decimales por línea; el total se obtiene sumando líneas ya redondeadas.
- Instantes en `TIMESTAMPTZ`; conexiones y registros técnicos en UTC. PostgreSQL guarda el instante, no el nombre original de la zona.
- Cada cine conserva `zona_horaria` IANA; formularios y fechas locales se interpretan con esa zona. Los datos de ejemplo usarán `America/Costa_Rica`.
- “Última semana”: ventana móvil de 168 horas. “Último mes”: ventana móvil de 720 horas. Reportes usan intervalos `[desde, hasta)` y un mismo instante de corte.
- Fechas por día de cartelera: límites de medianoche en la zona del cine, convertidos a instantes.
- Estados con `CHECK` y transiciones controladas; FK y `NOT NULL` donde corresponda.
- No borrar en cascada compras, pagos, boletos ni logs. Usar desactivación y estados para conservar historia.
- SQL numerado por dependencias y dominio; cambios de esquema posteriores mediante scripts nuevos y documentados.

## 5. Entidades y campos mínimos compartidos

Este es el contrato lógico mínimo. A-01, B-01 y C-01 elaborarán DER, tipos, cardinalidades y DDL completo sin eliminar estas garantías. Toda ampliación que afecte a otro módulo se revisa conjuntamente.

### Catálogo y programación — A

| Tabla | Campos mínimos y vínculos |
| --- | --- |
| `cine` | `id_cine, nombre, ubicacion, zona_horaria, activo`. |
| `pelicula` | `id_pelicula, titulo, sinopsis, clasificacion, duracion_min, poster_url, activa`. Duración positiva. |
| `genero` / `pelicula_genero` | Catálogo y asociación para filtrar por género, sin listas concatenadas. |
| `sala` | `id_sala, id_cine, nombre, capacidad, activa`. Nombre único por cine. |
| `zona` | `id_zona, id_sala, nombre`. Nombre único por sala. |
| `asiento` | `id_asiento, id_sala, id_zona, fila, numero, activo`. Único por sala/fila/número; la zona pertenece a esa sala. |
| `funcion` | `id_funcion, id_pelicula, id_sala, inicio, fin, limpieza_min, activa`. Fin posterior al inicio; duración y limpieza quedan fijadas al programar. |
| `categoria_entrada` | `id_categoria_entrada, nombre, requiere_acreditacion`: adulto, niño, estudiante y tercera edad. |
| `tarifa` | `id_tarifa, id_funcion, id_zona, id_categoria_entrada, monto, moneda, vigente_desde, vigente_hasta`. Zona de la sala de la función; sin vigencias superpuestas para la misma combinación. |
| `promocion` | `id_promocion, nombre, tipo, vigente_desde, vigente_hasta, activa` y condiciones estructuradas de días, categorías y zonas aplicables. |

La capacidad coincide con los asientos activos vendibles; no se mantienen valores contradictorios. Una tarifa se vincula expresamente a función/zona/categoría. Las condiciones promocionales no serán texto libre que el programa deba interpretar.

### Ventas — B

| Tabla | Campos mínimos y vínculos |
| --- | --- |
| `compra` | `id_compra, id_usuario_cliente, id_usuario_actor, id_funcion, estado, total, moneda, creada_en`. Una función por compra; cliente y actor permiten venta de taquilla identificada. |
| `compra_detalle` | `id_compra_detalle, id_compra, id_asiento, id_categoria_entrada, id_tarifa, id_promocion, precio_base, descuento, cargo_servicio, total_linea`. Una línea por asiento; instantánea histórica de lo cobrado. |
| `reserva` | `id_reserva, id_compra, estado, creada_en, vence_en`. Una reserva por compra. |
| `reserva_detalle` | `id_reserva, id_asiento`. Conserva los asientos solicitados, incluso después de expirar. |
| `inventario_funcion` | PK `(id_funcion, id_asiento)`; `estado, id_reserva, id_boleto`. Una fila por asiento vendible de la función. |
| `pago` | `id_pago, id_compra, estado, metodo, referencia, monto, moneda, creado_en`. Referencia de idempotencia única. |
| `boleto` | `id_boleto, id_compra_detalle, token_qr, estado, emitido_en, usado_en`. Token UUID aleatorio y único, separado del ID interno. Función/asiento se obtienen del detalle y la compra. |
| `reembolso` | `id_reembolso, id_solicitud_reembolso, id_pago, referencia, monto, moneda, creado_en`. Constancia de devolución simulada. |
| `reembolso_detalle` | `id_reembolso, id_boleto, monto`. Impide devolver dos veces el mismo boleto. |

El inventario representa disponibilidad actual; la reserva y sus detalles conservan historia. **No son una sola tabla.** Un boleto se emite por línea y una compra admite varios boletos.

La BD debe garantizar que el asiento pertenece a la sala de la función y que inventario, reserva, detalle y boleto se refieren al mismo asiento/función. Usar FK compuestas y restricciones, o una operación/triggers equivalentes explicados en el diseño. No basta comprobarlo en el formulario.

### Identidad, operación y logs — C y B

| Tabla | Propietario | Campos mínimos |
| --- | --- | --- |
| `rol` | C | `id_rol, nombre` único. |
| `usuario` | C | `id_usuario, id_rol, nombre, correo, password_hash, activo, creado_en`. Correo único normalizado. Un rol por usuario en el prototipo. |
| `solicitud_reembolso` | C | `id_solicitud_reembolso, id_compra, id_usuario_actor, motivo, estado, creada_en, resuelta_en, id_usuario_resuelve`. |
| `solicitud_reembolso_detalle` | C | `id_solicitud_reembolso, id_boleto`. Alcance concreto de la solicitud. |
| `transaccion_log` | B | ID, fecha, evento, compra/pago/reembolso, referencia, monto, moneda, actor y resultado. |
| `asiento_auditoria_log` | B | ID, fecha, función, asiento, reserva/compra, estado anterior/nuevo, actor y motivo. |
| `acceso_puerta_log` | C | ID, fecha, boleto opcional, función solicitada, operador, dispositivo, resultado y motivo. |
| `admin_operacion_audit` | C | ID, fecha, actor, rol al actuar, IP, acción, entidad/ID, motivo y cambios relevantes. |

Los rechazos de QR inexistente también se registran, sin exigir una FK a un boleto inexistente. No guardar contraseñas, tokens QR completos ni datos financieros sensibles en los logs.

C valida permisos y acceso; B ofrece la operación de consumo atómico del boleto. C no modifica arbitrariamente tablas de ventas. El registro de ingreso exitoso y el consumo se confirman juntos en una transacción compartida.

## 6. Políticas de negocio adoptadas

| Política | Decisión |
| --- | --- |
| Límite | Máximo **6 asientos diferentes por compra**. No se admiten listas vacías ni IDs repetidos. |
| Bloqueo | **120 segundos**, desde el instante de reserva medido por la BD; no se renueva al recargar la página. |
| Limpieza | **15 minutos** después de cada función. El intervalo ocupado es `[inicio, fin + limpieza)`. |
| Acceso | Desde **30 minutos antes** hasta **15 minutos después** del inicio, ambos extremos incluidos. |
| Reembolso ordinario | Solicitud y ejecución hasta **2 horas antes** del inicio, inclusive; solo boletos emitidos y sin usar. |
| Reembolso excepcional | Administrador, con motivo obligatorio; se permite por cancelación de función o excepción documentada. Nunca reutilizar ni devolver a emitido un boleto usado/anulado. |
| Retención | Cuatro categorías de logs, mínimo **cinco años** desde el evento. |
| Actualización del mapa | Consulta periódica cada **2 segundos** y actualización inmediata tras una operación local; la BD valida de nuevo al reservar. |
| Cargo de servicio | **USD 0,00** inicialmente; el modelo lo registra explícitamente por línea. |

Los ejemplos numéricos de la consigna se convierten aquí en decisiones del equipo. Las políticas se guardan de forma centralizada; su modificación requiere revisión, control de permisos y auditoría.

### Tarifas y promociones

- A configura tarifas por función, zona y categoría. C documenta la comprobación física de credenciales para categorías especiales.
- B calcula el precio en servidor; no acepta totales enviados por el navegador.
- Promoción inicial: **2x1**, en los días y categorías configurados, para parejas de entradas de la misma función, zona y categoría.
- Cada pareja recibe un descuento equivalente a una tarifa base; con cantidad impar se cobra la entrada sobrante. Las dos líneas conservan precio y descuento, distribuyendo el descuento por mitades y asignando cualquier centavo restante por orden de asiento.
- No se acumulan promociones. Si varias son aplicables, se utiliza la de mayor descuento; en empate, la de menor ID.
- La reserva fija la cotización y sus reglas hasta el vencimiento; un cambio posterior de tarifas no altera compras reservadas ni pagadas.
- Los cambios de tarifa/promoción se versionan mediante nuevas vigencias, preservando las referencias históricas.

### Vencimiento y pagos

- Una tarea periódica del servidor libera reservas vencidas; no depende del navegador. Al reservar o pagar también se comprueba el vencimiento dentro de la transacción.
- Un bloqueo está vencido cuando `ahora_bd >= vence_en`. En ese instante ya no permite pagar.
- Un pago rechazado cancela la compra y libera todos sus asientos inmediatamente.
- La aprobación exige reserva activa y vigente de todos los asientos; registra pago, compra, inventario, boletos y logs de manera atómica.
- Cada operación tiene referencia de idempotencia. Repetir la misma solicitud devuelve el resultado anterior; la misma referencia con datos distintos produce conflicto.
- Una confirmación tardía no recupera asientos liberados o revendidos. Se registra el intento rechazado y no se emiten boletos.
- Una compra cancelada o expirada no se reutiliza: se crea otra para intentar comprar de nuevo.

### Reembolsos e historia

C comprueba identidad, pertenencia, permisos y política; B ejecuta la reversión financiera simulada y la liberación. La aprobación efectiva de la solicitud, el reembolso, la anulación, el inventario y la auditoría quedan coordinados en una transacción.

Se permiten reembolsos de todos los boletos o de un subconjunto. El importe devuelto corresponde a los totales históricos de las líneas seleccionadas, incluido el descuento distribuido; nunca se recalcula con tarifas actuales ni excede el importe pagado.

Tras un reembolso parcial, la compra conserva sus otros boletos y queda `parcialmente_reembolsada`. No se devuelve dinero por un boleto usado. Una nueva venta del asiento genera otra compra y otro boleto/token; conserva los anteriores.

## 7. Estados y transiciones

| Entidad | Estados y transiciones válidas |
| --- | --- |
| Inventario | `disponible → bloqueado → vendido`; `bloqueado → disponible` por expiración/cancelación/rechazo; `vendido → disponible` por reversión autorizada de boleto sin usar. |
| Reserva | `activa → confirmada / expirada / liberada`. Estados finales sin reactivación. Una confirmada conserva el hecho histórico aunque luego haya reembolso. |
| Compra | `pendiente → pagada / cancelada / expirada`; `pagada → parcialmente_reembolsada / reembolsada`; `parcialmente_reembolsada → reembolsada` o permanece parcial si se devuelve otro subconjunto. |
| Pago | `pendiente → aprobado / rechazado`. Se conserva la aprobación original; devoluciones en tablas de reembolso. |
| Boleto | Se crea `emitido` después de aprobación; `emitido → usado / anulado`. No hay regreso a emitido. |
| Solicitud de reembolso | `pendiente → ejecutada / rechazada`. Revisión y ejecución síncronas; un fallo transaccional no deja la solicitud como ejecutada. |

Toda escritura verifica el estado esperado y las reglas en servidor/BD. El estado de compra no sustituye el estado de cada boleto en un reembolso parcial.

## 8. Integridad y concurrencia

1. La unidad de disponibilidad es **función + asiento**. La PK de inventario impide filas duplicadas y cada fila contiene un único ocupante vigente.
2. Reservar varios asientos es todo o nada: si uno falla, rollback completo. No se dejan bloqueos parciales.
3. Se bloquean las filas de inventario con `SELECT ... FOR UPDATE`, siempre por orden de ID. Pago, expiración, cancelación y reserva usan el mismo protocolo.
4. Se bloquea y revalida la compra/reserva antes de una transición. Las operaciones que toman varios tipos de bloqueo comparten un orden documentado en B-01; ante deadlock se revierte y se aplica un reintento limitado.
5. Programación y cambios de distribución se serializan por sala. Las reservas/ventas participan en la coordinación necesaria para que una modificación concurrente no evada RN-18.
6. A debe impedir traslapes incluso ante dos administradores simultáneos, mediante restricción de exclusión de intervalos o bloqueo por sala con revalidación transaccional.
7. Una función con reservas activas o boletos vigentes no cambia de sala, horario ni distribución mediante edición directa. Una cancelación o reprogramación requiere un flujo administrativo explícito y auditado.
8. El consumo QR actualiza condicionalmente `emitido → usado`; solo una operación concurrente puede lograrlo. Un reembolso y un ingreso simultáneos también compiten por el mismo boleto.
9. El historial no lleva una unicidad global de función/asiento en todos los boletos: eso impediría reventa legítima. La unicidad vigente reside en inventario.
10. Los logs de éxito se confirman con el cambio. Si se revierte una transacción por fallo, el intento fallido se registra después en una transacción separada sin afirmar que hubo éxito.

## 9. Matriz de roles

Permisos de la aplicación definidos por el equipo a partir de RN-17 y la pauta. La consigna revisada no contiene una matriz completa que pueda copiarse.

| Acción | Cliente | Taquillero | Operador de puerta | Contador | Administrador |
| --- | --- | --- | --- | --- | --- |
| Consultar cartelera | Sí | Sí | Sí | Sí | Sí |
| Crear/editar catálogo, salas y funciones | No | No | No | No | Sí, con restricciones |
| Configurar tarifas/promociones | No | No | No | Solo lectura | Sí |
| Reservar/comprar | Para sí | Venta presencial para cliente identificado | No | No | No en este rol |
| Consultar boletos/QR | Solo propios | Venta atendida, para entrega | Sin listado de QR; solo validar | Datos financieros sin QR | Consulta administrativa sin exposición masiva de QR |
| Validar ingreso | No | No | Sí | No | No en este rol |
| Solicitar reembolso | Solo propios | Solicitud de cliente identificado | No | No | Sí |
| Autorizar/ejecutar reembolso | No | No | No | No | Sí, conforme a política |
| Consultar reportes financieros | No | No | No | Sí | Sí |
| Consultar auditoría administrativa | No | No | No | Sí, lectura | Sí, lectura |
| Administrar usuarios/roles | No | No | No | No | Sí |
| Editar/borrar logs | No | No | No | No | No desde la aplicación |

El rol administrador no hereda automáticamente funciones de venta ni puerta. Para demostrar cada función se usa su cuenta específica. La emisión de boletos es automática tras el pago; ningún rol puede emitirlos anticipadamente mediante una edición manual.

- Actor y rol proceden de la sesión autenticada y la BD, nunca de parámetros confiados del navegador.
- Verificar permisos y propiedad en cada operación; ocultar botones es solo una ayuda visual.
- Las escrituras web usan protección CSRF y las consultas SQL son parametrizadas.
- El usuario técnico de aplicación tiene privilegios mínimos y no es superusuario. Los roles de negocio no equivalen a cinco credenciales PostgreSQL compartidas.
- Auditoría de cambios de rol, precios, programación, distribución, cortesías, cambios manuales de asiento y devoluciones: actor, rol, fecha, IP y motivo.

## 10. Operaciones compartidas

Serán funciones del mismo programa y/o procedimientos SQL. Las escrituras aceptan el contexto transaccional común y no hacen commits ocultos al coordinador.

| Operación | Dueño | Entrada principal | Resultado / rechazo |
| --- | --- | --- | --- |
| `consultar_funciones` | A | Ubicación, fecha local, género | Funciones activas futuras con metadatos. |
| `cotizar_compra` | A + B | Función, asientos/categorías | A entrega tarifas/promociones vigentes; B calcula líneas y total. |
| `consultar_disponibilidad` | B | Función, actor autenticado opcional | Asiento, zona, estado y vencimiento; indicador de bloqueo propio, sin identidad de otros clientes. |
| `reservar_asientos` | B | Actor, cliente, función, asientos/categorías, referencia | Compra, reserva, cotización y vencimiento; o límite/conflicto/función inválida. |
| `resolver_pago_simulado` | B | Actor, compra, resultado, método, referencia | Compra pagada con boletos o compra cancelada/liberada; rechaza expiración y referencias incompatibles. |
| `consultar_boletos_propios` | B | Usuario de sesión | Solo boletos autorizados de ese cliente. |
| `consumir_boleto` | B | Boleto, función, instante BD, contexto autorizado por C | Cambio atómico a usado o rechazo por estado; participa en transacción de ingreso. |
| `validar_ingreso` | C | Operador, token, función, dispositivo | Valida permiso, función y horario; invoca consumo B y registra aceptación/rechazo. |
| `solicitar_reembolso` | C | Actor, compra, boletos, motivo | Solicitud pendiente o rechazo por propiedad/estado. |
| `resolver_reembolso` | C | Administrador, solicitud, decisión y motivo | Rechazo o autorización con reversión B y auditoría. |
| `revertir_venta` | B | Solicitud persistida y autorizada, boletos, referencia | Devolución simulada, anulación y liberación atómicas; devuelve resultado previo si se repite. |
| `autorizar_accion` / `auditar_accion` | C | Actor autenticado, acción, recurso, contexto | Permiso o denegación; evento administrativo cuando corresponda. |

Errores de negocio comunes: `NO_AUTORIZADO`, `NO_ENCONTRADO`, `DATOS_INVALIDOS`, `LIMITE_EXCEDIDO`, `ASIENTO_NO_DISPONIBLE`, `RESERVA_EXPIRADA`, `ESTADO_INVALIDO`, `REFERENCIA_CONFLICTIVA`, `FUNCION_INCORRECTA`, `FUERA_DE_HORARIO`, `ENTRADA_YA_UTILIZADA` y `FUERA_DE_POLITICA`.

La interfaz traduce esos códigos a mensajes comprensibles; el segundo escaneo muestra **“Entrada ya utilizada”**. Un error técnico inesperado se registra por separado y no se cuenta como conflicto esperado.

## 11. Reportes, auditoría y continuidad

C implementa consultas SQL y dashboard con estas definiciones:

1. **Ocupación y recaudación por función:** boletos emitidos/usados no anulados entre asientos vendibles de la función; ingresos netos = pagos aprobados menos devoluciones ejecutadas. Preagregar antes de unir tablas para no multiplicar importes. Incluir funciones sin ventas.
2. **Top 5 películas:** boletos vendidos en los últimos siete días, según fecha de emisión y excluyendo anulados al corte; desempate por ID de película.
3. **Métodos de pago:** porcentaje de compras pagadas por método, usando pagos aprobados en el periodo seleccionado; denominador explícito. Las devoluciones se muestran aparte y no cuentan como nuevos pagos.
4. **Auditoría crítica:** acciones manuales de los últimos treinta días agrupadas por administrador, con detalle consultable.

Los logs se separan en financiero, inventario, puerta y administración. La cuenta operativa no los edita ni borra. La propuesta global definirá archivo protegido contra alteración, retención, acceso, respaldos y restauración; una tabla local por sí sola no prueba inalterabilidad a cinco años.

C dimensiona por categoría, tamaño/eventos, fallos, crecimiento, índices, réplicas y backups. A reutiliza esos mismos supuestos al comparar dos proveedores y proyectar tres años. Se distinguen réplica, backup y archivo histórico, y los objetivos globales de la evidencia local.

## 12. Datos y verificación comunes

El conjunto de demostración incluirá:

- Al menos **7 usuarios**: dos clientes y un usuario por cada uno de los otros cuatro roles, más un segundo operador para pruebas simultáneas.
- Dos cines con zona IANA; dos salas de aproximadamente 100 asientos cada una, con zonas y numeración única.
- Tres películas con género, sinopsis, clasificación, duración y póster.
- Categorías adulto, niño, estudiante y tercera edad; tarifas y promoción 2x1 con resultados verificables.
- Funciones futuras, pasadas e inactivas; fechas relativas al momento de cargar los datos.
- Reservas vigentes/vencidas; pagos aprobados/rechazados; boletos emitidos/usados/anulados; devoluciones parciales/totales.
- Ventas históricas y acciones administrativas con resultados esperados para los cuatro reportes.

Los boletos sintéticos respetan las mismas FK y estados: un boleto emitido tiene compra pagada y pago aprobado. Para desarrollo aislado, C usa fixtures compatibles con el contrato de B. Datos masivos con Faker y semilla fija se generan aparte y no se confunden con el dataset pequeño.

Verificaciones obligatorias del equipo:

- Reserva simultánea: **50 solicitudes** sobre un asiento libre y no vencido durante el ensayo; exactamente una exitosa, 49 conflictos esperados y cero errores inesperados. Comprobar inventario final en SQL.
- Compras multi-asiento sin reservas parciales; expiración sin navegador abierto.
- Pago rechazado, aprobado, repetido y tardío; QR ausente antes de aprobación.
- Dos ingresos simultáneos: un éxito; QR usado, anulado, ajeno a función y fuera de horario rechazados.
- Reembolso repetido/parcial, reventa y carrera ingreso/reembolso.
- Traslapes y cambios de sala ante actividad concurrente; permisos negativos.
- Cuatro reportes contra resultados conocidos; disponibilidad y analíticas con `EXPLAIN ANALYZE` antes/después sobre un mismo dataset representativo.
- Instalación desde cero y demostración de los cinco procesos.

Guardar entorno, versiones, datos, comandos, esperado, obtenido y evidencia. No inventar tiempos ni forzar planes para aparentar mejora.

## 13. Carpetas y seguimiento sin GitHub Projects

Estructura acordada para incorporar progresivamente:

~~~text
requirements.txt
.env.example
.gitignore
docs/
  00_acuerdos.md
  requisitos.md
  guia_trabajo.md
  factibilidad.md
  operacion.md
  modelos/
  informe/
sql/
  instalar.sql
  01_...
  99_datos_sinteticos.sql
src/
  __init__.py
  cartelera/
  ventas/
  operacion/
  templates/
  static/
tests/
evidencias/
~~~

Los únicos entregables creados por esta revisión son estos acuerdos. Las demás rutas son el contrato de estructura para las tareas siguientes.

### Flujo de trabajo

1. Elegir un issue asignado; máximo una tarea principal en curso por persona.
2. Actualizar la copia local y crear rama, por ejemplo `a-01-modelo-cartelera`.
3. Hacer commits pequeños con prefijos `feat:`, `fix:`, `docs:` o `test:`.
4. Abrir PR con issue relacionado, cambio y verificación.
5. Revisar, integrar y cerrar el issue cuando todos sus criterios estén cumplidos.

Seguimiento mediante el propio issue y el PR:

| Situación | Evidencia |
| --- | --- |
| Pendiente | Issue abierto sin trabajo iniciado. |
| En curso | Comentario de inicio del responsable y rama vinculada. |
| En revisión | PR abierto vinculado al issue. |
| Terminado | Cambio integrado, criterios verificados y issue cerrado. |

No se crea ni mantiene un tablero de GitHub Projects. Las etiquetas son opcionales; no condicionan el flujo.

Revisión cruzada: A revisa B, B revisa C y C revisa A. Cambios de contrato, permisos o esquema global requieren revisión de los tres, incluido el autor. No se declara una revisión que no haya ocurrido.

Los acuerdos iniciales se publican como base documental por solicitud del equipo; las modificaciones posteriores siguen este flujo. No cerrar T-01 automáticamente. La trazabilidad y la guía de colaboración se documentan en `docs/requisitos.md` y `docs/guia_trabajo.md`; se omite el README por decisión de Mauriart. Las entidades existentes son la base del DER que se desarrolla en las tareas de diseño. En este apartado se trabaja únicamente A.

## 14. Regla de terminado y control de cambios

Una tarea termina cuando:

- Cubre sus reglas y criterios de aceptación.
- Código, SQL y GUI corresponden al mismo modelo.
- Incluye evidencia reproducible de éxito y rechazo.
- Actualiza diccionario y matriz `docs/requisitos.md`.
- Otro integrante revisa y el cambio queda integrado.

La matriz de trazabilidad tendrá: requisito RN/RF/RNF, fuente, responsable, issue, tabla/operación/pantalla, prueba, evidencia y estado. Cada dominio documenta su normalización con claves y dependencias funcionales.

Si un issue o la guía conserva una formulación incompatible con estos acuerdos, se registra la discrepancia en su próxima revisión; no se implementan dos contratos distintos. Cambios futuros se registran aquí mediante commits y PRs, indicando impacto en otros módulos.

### Correcciones incorporadas al borrador

- Sustitución de GitHub Projects por issues y PRs.
- Versiones comunes y contrato de arranque sin espacios en blanco.
- Matriz de permisos completa; sus decisiones no se atribuyen a una matriz inexistente en la consigna.
- Separación de inventario actual, reserva histórica, detalle de compra y reembolso.
- Incorporación de género, zonas, categorías, identidad y precio histórico.
- Reglas de expiración, idempotencia, concurrencia, reembolso parcial y consumo QR compartido.
- Privacidad de disponibilidad: no revelar el dueño de bloqueos ajenos.
- Corrección de 500 títulos a 500 funciones diarias; separación de requisitos de la consigna y objetivos internos.

### Actualización de alcance — 15 de octubre de 2026

Mauriart toma las decisiones pendientes. La matriz y la guía de esta etapa cubren solo el bloque A, con B/C como dependencias. Los detalles técnicos añadidos durante la corrección anterior no se consideran ratificados por el solo hecho de estar publicados; antes de usarlos para fijar comportamiento se identifican y se someten a su decisión cuando corresponda. Esta actualización no declara una revisión del grupo ni modifica sus módulos.
