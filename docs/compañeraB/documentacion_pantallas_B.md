Aquí tienes la versión lista para editar en Markdown. He preparado las secciones de **Evidencias y Capturas de Pantalla** con marcadores claros y una estructura limpia para que puedas insertar tus imágenes o enlaces de imágenes fácilmente.

---

# Documentación de las pantallas — Bloque B (Ventas)



**Módulo:** Ventas, inventario por función, pagos y boletos

**Propietaria:** Keilyn

**Archivos:** `ventas.py` (rutas) y 6 plantillas `ventas_*.html`

---

## 1. Propósito



Las pantallas permiten recorrer el flujo de compra completo desde el navegador:

**elegir función → elegir asientos → pagar (simulado) → recibir la factura con los boletos y su código QR.**

Las pantallas **no calculan precios ni deciden reglas**: llaman a las funciones SQL del bloque B (`consultar_disponibilidad`, `reservar_asientos`, `procesar_pago`, `liberar_reservas_vencidas`).

Así, las reglas (límite de 6 asientos, bloqueo de 2 minutos, todo o nada, un solo ganador por asiento) se cumplen igual aunque alguien use otra interfaz.

---

## 2. Archivos y estructura



| Archivo | Carpeta | Para qué sirve |
| --- | --- | --- |
| `ventas.py` | junto a `app.py` | Define las direcciones y llama a las funciones SQL (Blueprint `ventas_bp`)

 |
| `ventas_comun.html` | `templates/` | Fragmento que usan las 5 pantallas: estilos (limitados a `.ventas`), submenú de ventas y mensajes de aviso

 |
| `ventas_inicio.html` | `templates/` | Lista de funciones disponibles

 |
| `ventas_mapa.html` | `templates/` | **Mapa de asientos**

 |
| `ventas_compra.html` | `templates/` | **Compra**: detalle, cuenta regresiva y pago simulado

 |
| `ventas_factura.html` | `templates/` | **Factura** con boletos y QR

 |
| `ventas_mis_compras.html` | `templates/` | Lista de compras del usuario

 |

`app.py` no necesita cambios: ya importa `ventas_bp` y lo registra.

**Integración con el diseño del grupo:** todas las plantillas de ventas extienden `base.html` (bloques `title` y `content`), así que comparten la cabecera, el menú y el pie de las demás pantallas. Los estilos propios de ventas van dentro de `ventas_comun.html`, limitados a la clase `.ventas` y con nombres que empiezan con `v-`, para no alterar `static/estilos.css`.

**Enlace en el menú principal** (agregar dentro de `<nav>` en `base.html`):

```html
<a href="{{ url_for('ventas.inicio') }}" {% if request.blueprint == 'ventas' %}aria-current="page"{% endif %}>Ventas</a>

```

---

## 3. Direcciones (Rutas)



| Dirección | Qué muestra | Función SQL que usa |
| --- | --- | --- |
| `/ventas/` | Funciones activas y futuras | — (consulta `funcion`, `pelicula`, `sala`, `cine`)

 |
| `/ventas/funciones/<id>/asientos` | Mapa de asientos por colores | `liberar_reservas_vencidas`, `consultar_disponibilidad`

 |
| `POST /ventas/funciones/<id>/reservar` | Reserva los asientos marcados | `reservar_asientos`

 |
| `/ventas/compras/<id>` | Resumen, tiempo restante y botones de pago | `liberar_reservas_vencidas`

 |
| `POST /ventas/compras/<id>/pagar` | Pago simulado (aprobado o rechazado) | `procesar_pago`

 |
| `/ventas/compras/<id>/factura` | Factura con boletos y QR | — (lee `compra`, `compra_detalle`, `boleto`, `pago`)

 |
| `/ventas/mis-compras` | Compras del usuario | —

 |
| `/ventas/qr/<token>.png` | Imagen del código QR | — (verifica que el boleto sea del usuario y esté `Emitido`)

 |
| `/ventas/entrar-prueba/<id>` | Sesión de prueba (solo con `debug=True`) | —

 |

---

## 4. Las tres pantallas principales



### 4.1 Mapa de asientos



Muestra los asientos de la función por fila y zona, con colores: **disponible** (verde), **seleccionado** (azul), **bloqueado** (amarillo: alguien lo está pagando) y **vendido** (rojo). Solo los disponibles se pueden marcar. El cliente elige hasta 6 asientos y pulsa **Reservar**. Si alguien se adelantó en un asiento, la base de datos rechaza la reserva completa (todo o nada) y se muestra el mensaje.

### 4.2 Compra



Muestra cada asiento con su precio, descuento y total, el total de la compra y una **cuenta regresiva** con el tiempo que queda para pagar (120 segundos). Ofrece dos botones de **pago simulado**: aprobado y rechazado. Al llegar el tiempo a cero, la página se recarga: los asientos vencidos se liberan y la compra queda `Expirada`.

### 4.3 Factura con QR



Solo existe si el pago fue aprobado. Muestra los datos del cliente y de la función, el detalle de la compra, la referencia del pago simulado y **un boleto por asiento con su código QR** (que contiene el token único del boleto). Se puede imprimir. Los boletos anulados no muestran QR.

---

## 5. Reglas y protecciones



* **El cliente solo ve lo suyo:** cada pantalla filtra por el usuario de la sesión, nunca por un dato de la dirección. Pedir una compra o un QR ajeno devuelve "no encontrado".


* **QR protegido:** la imagen solo se genera para boletos propios y en estado `Emitido`.


* **Sin pago aprobado no hay boletos:** la factura redirige a la compra si el pago no está aprobado.


* **Doble clic:** el botón se bloquea al enviar y, si el mismo pago llegara dos veces, la referencia única lo rechaza sin duplicar nada.


* **Pago vencido:** antes de cobrar, la pantalla libera lo vencido; si la compra ya expiró, no se procesa el pago.


* **Pago simulado:** no se piden ni se guardan datos de tarjeta.



---

## 6. Pruebas y Evidencias Fotográficas



### Procedimiento de Prueba:



1. Base de datos con las tablas de A, B y C instaladas e inventario cargado (`inventario_funcion`).


2. Ejecutar desde la carpeta del proyecto: `python app.py`.


3. Abrir `[http://127.0.0.1:5000/ventas/entrar-prueba/1](http://127.0.0.1:5000/ventas/entrar-prueba/1)`.


4. Navegar a `/ventas/`, elegir función, seleccionar asientos y probar el flujo.



---

### Registro de Pruebas

#### P-01: Mapa muestra estados con colores



* **Resultado esperado:** Verde (disponible), amarillo (bloqueado) y rojo (vendido) según la base de datos.


* **Evidencia:**
![alt text](image-2.png)
---

#### P-02: Reservar 2 asientos



* **Resultado esperado:** Redirección a la pantalla de compra con el cálculo del total.


* **Evidencia:**
![alt text](image-1.png)
---

#### P-03: Intentar reservar más de 6 asientos



* **Resultado esperado:** La interfaz bloquea la selección de más de 6 asientos.


* **Evidencia:** Sin evidencia

---

#### P-04: Pago aprobado



* **Resultado esperado:** Generación de factura con un código QR por cada asiento reservado.


* **Evidencia:**
![alt text](image-3.png)
---

#### P-05: Pago rechazado



* **Resultado esperado:** Retorno al mapa de asientos y liberación de las reservas.


* **Evidencia:**
![alt text](image-4.png)
---

#### P-06: Tiempo de reserva vencido



* **Resultado esperado:** La compra pasa a estado `Expirada` y los asientos son liberados.


* **Evidencia:**
![alt text](image-5.png)
---

## 7. Limitaciones y pendientes



* **Integración de sesión:** La sesión actual es de prueba (`ventas.py`).


* *Estado:* `[EDITAR AQUÍ: Indicar si ya se integró con el módulo C]`




* **Permisos por rol:** Las funciones avanzadas (como taquilleros vendiendo a terceros) y auditorías dependen del Módulo C.


* **Diseño:** Interfaz funcional enfocado en usabilidad básica.


* **Rendimiento:** Las pruebas de concurrencia masiva se documentan por separado.