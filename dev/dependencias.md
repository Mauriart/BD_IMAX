# Dependencias e instalación de IMAX

## Una computadora nueva

Instala estos programas antes de iniciar:

- [Python 3.14](https://www.python.org/downloads/). En Windows habilita el lanzador `py` y la opción de agregar Python al PATH.
- [PostgreSQL 18](https://www.postgresql.org/download/). Conserva la contraseña del usuario `postgres` y deja el servicio iniciado. Se usa el puerto 5432 por defecto.
- [Git](https://git-scm.com/downloads), si vas a clonar el repositorio. También puedes descargar el ZIP desde GitHub y descomprimirlo.

DBeaver es opcional. La aplicación y el instalador se conectan directamente a PostgreSQL.

## Descargar y preparar las librerías

Abre una terminal y ejecuta:

```powershell
git clone https://github.com/Mauriart/BD_IMAX.git
cd BD_IMAX/dev
py -3.14 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

No necesitas activar el entorno virtual. Los comandos usan directamente su Python.

`requirements.txt` instala Flask para la interfaz web, Psycopg para PostgreSQL, python-dotenv para la configuración, qrcode con Pillow para los QR y tzdata para las zonas horarias en Windows. Sus dependencias se descargan automáticamente. Se necesita conexión a Internet para esta instalación inicial.

## Crear la base y preparar el acceso

Desde `dev`, ejecuta:

```powershell
.\.venv\Scripts\python.exe instalar.py
```

El instalador pide el servidor, puerto, nombre de base, usuario y contraseña de PostgreSQL. Con el usuario `postgres` puede crear la base `p2`. Después ejecuta el único SQL completo que está en `sql/instalacion_completa.sql`.

También pide una contraseña inicial de al menos 12 caracteres para las cuentas de demostración. La contraseña se guarda como hash y se genera una clave de sesión privada en `dev/.env`. Ese archivo se queda únicamente en tu computadora.

La instalación agrega un cine, salas, asientos, una película, una función futura, tarifas, la promoción y los usuarios de ejemplo. El pago es simulado. No se necesitan archivos de documentación ni ejecutar SQL adicionales.

El instalador rechaza una base que ya contiene tablas u otros objetos. No borra ni reinstala tus datos. Si ya tienes una base funcionando, conserva tu `.env` y pasa directamente al inicio de la aplicación.

## Levantar la aplicación

En Windows, abre `dev/iniciar.cmd`, o ejecuta desde `dev`:

```powershell
.\.venv\Scripts\python.exe iniciar.py
```

Abre [la cartelera local](http://127.0.0.1:5000/cartelera). Para detener el servidor presiona `Ctrl+C` en la terminal.

Las cuentas iniciales usan la contraseña que elegiste en la instalación:

| Rol | Correo |
| --- | --- |
| Administrador | admin@imax.test |
| Cliente | cliente1@imax.test |
| Segundo cliente | cliente2@imax.test |
| Taquillero | taquillero@imax.test |
| Operador de puerta | puerta1@imax.test |
| Segundo operador | puerta2@imax.test |
| Contador | contador@imax.test |

## Ejecutar solamente el SQL

Como alternativa al instalador, crea una base vacía y ejecuta `dev/sql/instalacion_completa.sql` como script completo desde DBeaver o psql. Ese archivo contiene las tablas, relaciones, funciones, triggers, permisos de aplicación, reportes y datos iniciales.

Después copia `.env.example` como `.env` y escribe los datos reales de la conexión. Ejecuta lo siguiente para preparar el acceso de cada usuario que vayas a utilizar:

```powershell
.\.venv\Scripts\python.exe configurar_acceso.py
```

Si ya ejecutaste el SQL manualmente, no necesitas volver a ejecutar `instalar.py`.

## Linux y macOS

Instala los mismos programas y usa los siguientes comandos desde `dev`:

```sh
python3.14 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python instalar.py
.venv/bin/python iniciar.py
```

## Organización

- `app.py` registra las pantallas y las operaciones del catálogo de películas.
- `modulos/` contiene conexión, seguridad, cartelera, salas, funciones, precios, ventas, reportes y mantenimiento.
- `templates/` contiene las pantallas HTML y `static/` los estilos, imágenes y JavaScript.
- `sql/instalacion_completa.sql` instala toda la base en una máquina nueva.
- `pruebas/` contiene las pruebas integradas en esquemas temporales, incluidas 50 reservas y 50 ingresos simultáneos.

Para ejecutar las pruebas desde `dev`:

```powershell
.\.venv\Scripts\python.exe pruebas/integracion.py
```

Las pruebas requieren una conexión configurada y permiso para crear esquemas en esa base. Crean sus propios datos y eliminan el esquema temporal al terminar.
