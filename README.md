# TallerNeto — app del personal del taller

Una sola app, funciones según el ROL de quien entra:

| Rol | Código demo | Qué ve |
|---|---|---|
| Mecánico a destajo | `MEC-01` | Inicio con «Llevo ganado» (suma de trabajos validados del mes) y «En revisión», conteos del mes por estado, Registrar trabajo por pasos (con **borrador local** reanudable), «Mis trabajos» con el detalle de cada trabajo, «Mis pagos» con el cálculo completo del mes, Perfil (con «Cambiar mi nombre» y «Cambiar mi PIN»), y **solicitudes de piezas**: botón «Pedir pieza» + el estado de las suyas (pendiente / en pedido / recibida / rechazada con el motivo); al registrar un trabajo, atajo «Pedir esta pieza» en las piezas sin stock |
| Mecánico con sueldo | `MEC-02` | Igual, pero el Inicio muestra «Tu sueldo: RD$35,000» y sus trabajos como productividad (en «Mis pagos», conteos sin importes por trabajo) |
| Coordinador de lavado | `LAV-01` | Interfaz de lavado: unidades de hoy con marcado/desmarcado y resumen «Lavadas hoy: X de Y» (solo si la empresa tiene el módulo activo) |
| Despachador de combustible | `COM-01` | Interfaz de combustible: **tarjeta del tanque por tipo** («Diésel: quedan X gal», con «de N gal · P%» si la empresa fijó la capacidad, alerta «Poco combustible» y días estimados), botón **«Recibir combustible»** (tipo + galones + costo por galón + proveedor opcional; se rechaza si se pasa de la capacidad del tanque), despachos de hoy, total de galones del día y registrar despacho (vehículo + galones + tipo + odómetro que no puede bajar + costo por galón; el despacho descuenta del tanque y se rechaza si el saldo no alcanza) (solo si la empresa tiene el módulo activo) |

PIN demo de todos: **1234**. Tema M3 con **modo noche/día** en el
Perfil (preferencia guardada en el teléfono).

**Rol adicional (desde la 1.2.0):** el login trae el rol principal
y el adicional (`rolAdicional`). MEC-01 es mecánico **+ almacén**:
como el almacén no tiene pantalla en la app, entra directo como
mecánico (su segundo sombrero se ejerce en el panel, donde valida
trabajos ajenos y recibe solicitudes). Si una persona tuviera dos
roles CON pantalla (p. ej. mecánico + lavado), al entrar la app le
pregunta con cuál trabajar y el Perfil trae la tarjeta «Cambiar de
función» para cambiar cuando quiera.

## Modo demo (sin servidor)

La app funciona COMPLETA sin backend: los datos semilla viven en
`lib/datos/repositorio_demo.dart` y son equivalentes a los del panel
demo y a la semilla SQL («Transportes Demo», lavado y combustible
activados, catálogo de 6 trabajos, trabajos en estados mixtos, 3
unidades ya lavadas hoy, 14 despachos, tanque con recepciones —
diésel 391 gal cómodo, gasolina 40 gal BAJO el umbral: alerta
visible— y 2 solicitudes de piezas). Registrar trabajos, marcar
lavados, despachar, recibir combustible y pedir piezas funciona en
el momento, en memoria + sesión guardada en el teléfono, con las
mismas reglas del servidor (incluido el rechazo de despacho sin
saldo en el tanque, con el mismo mensaje).

## Conexión a Supabase (ACTIVA desde la 1.4.0)

La app trabaja REAL contra el proyecto Supabase «staffride»
(`lib/datos/conexion.dart` + `lib/datos/repositorio_real.dart`):
RPC `pr_iniciar_sesion` (contexto 'app'; la cuenta del dueño se
rechaza con mensaje claro), `pr_datos_mecanico`,
`pr_registrar_trabajo`, `pr_solicitar_pieza`, `pr_datos_lavado`,
`pr_marcar_lavado`, `pr_desmarcar_lavado`, `pr_datos_combustible`,
`pr_registrar_despacho`, `pr_registrar_recepcion`,
`pr_datos_inventario_app`, `pr_pasar_inventario_unidad`,
`pr_cambiar_nombre`, `pr_cambiar_pin` (desde la 1.5.0) y
`pr_cerrar_sesion`. Sesión con token persistida en el teléfono.
Sin cola de envío en el repositorio real: sin conexión, error
claro y nada se da por guardado hasta que el servidor confirma
(la cola con «Pendiente de envío» existe solo como simulación
dentro de la demo local). La demo (`repositorio_demo.dart`)
queda como vitrina sin servidor y como respaldo.

## Versiones

- **1.5.1 (2026-11-23)**: la app muestra su **versión instalada**
  leída del sistema en tiempo de ejecución (PackageInfo:
  versionName + buildNumber, nunca un texto fijo) en dos sitios:
  una fila «Versión instalada: 1.5.1 (12)» en el Perfil, junto a
  «Buscar actualización», y un texto pequeño «v1.5.1» al pie de
  la pantalla de entrada (regla de Miguel, 2026-11-23: toda app
  muestra su versión). Sin más cambios.
- **1.5.0 (2026-11-23)**: rediseño según el prompt de Miguel,
  solo con lo que el sistema ya tiene (cero cambios de servidor)
  y UNA sola novedad de las discutidas: el **borrador local**.
  Inicio del mecánico reorganizado (encabezado con rol y modo
  de pago, conteos del mes por estado que abren «Mis trabajos»
  filtrado, acciones principales en grande REGISTRAR TRABAJO /
  VER MIS TRABAJOS); el Historial pasa a llamarse **«Mis
  trabajos»**, con **detalle por trabajo** (unidad, descripción,
  piezas usadas y motivo de rechazo); pantalla nueva **«Mis
  pagos»** con el cálculo completo del mes desde los datos que
  ya bajaban (validados = lo que cobra el de destajo; el sueldo
  ve conteos de productividad) — el sistema no tiene estado
  «pagado» ni comprobantes para la app y no se inventaron;
  **borrador local del formulario de trabajo** (se guarda solo
  en el teléfono, por usuario, con aviso visible; se retoma tal
  cual y se borra al registrar o al descartarlo; sin cola de
  sincronización: sin internet sigue el error claro de siempre);
  **«Cambiar mi PIN» en el Perfil** (la RPC `pr_cambiar_pin` ya
  existía en el servidor; al cambiar el PIN el servidor revoca
  las sesiones y la app lo avisa y vuelve a la entrada);
  encabezados con saludo y rol en Lavado y Combustible; pasos
  del tutorial corregidos a lo que la app real hace sin conexión.
  NO incorporado por decisión de Miguel (2026-11-23): rol chofer
  y reportes de avería, órdenes asignadas como entidad nueva,
  fotos adjuntas, notificaciones push y llevar encargado /
  inventario a la app.
- **1.4.0 (2026-11-21)**: la «versión única» — la app se conecta
  de verdad a producción («staffride») con `RepositorioReal`,
  pantalla «Inventario» por unidad y «Cambiar mi nombre».
- **1.3.1 (2026-11-21)**: terminología — en toda la app se dice
  «unidad / unidades», el término correcto y profesional (orden de
  Miguel). Solo textos; sin cambios de funciones.
- **1.3.0 (2026-11-21)**: la tanda de marca y autonomía —
  **logo oficial** (la unidad con la llave, elegido por Miguel) como
  icono y en la pantalla de entrada, y la **paleta del panel nuevo**
  (grafito/ámbar) en modo día y noche; **cola de salida offline**:
  trabajos, lavados, despachos, recepciones y solicitudes nacen con
  el sello «Pendiente de envío», quedan guardados en el teléfono,
  con contador en la barra superior y en el Perfil, reintento
  automático y «Sincronizar ahora» (en demo, interruptor «Simular
  sin conexión» en el Perfil para probarlo); **tutorial de
  bienvenida** por rol la primera vez (con «Omitir»), repetible
  desde el Perfil → «Ver tutorial»; la app respeta la
  **configuración de combustible** de la empresa (solo tipos
  activos en selectores, tanque y formularios; con los **precios
  apagados** en el panel, los formularios no muestran costos y
  manda el precio vigente de administración); mensaje comercial
  amable cuando un módulo extra no está contratado.
- **1.2.0 (2026-11-20)**: rol adicional opcional — el login trae
  los dos roles del usuario; con dos roles CON pantalla, selector
  de función al entrar y «Cambiar de función» en el Perfil; con el
  adicional almacén (sin pantalla), entrada directa. En la demo,
  MEC-01 queda mecánico + almacén, igual que en el panel.
- **1.1.1 (2026-11-20)**: capacidad del tanque — las tarjetas del
  despachador muestran «de N gal · P%» (el nivel real: saldo ÷
  capacidad) cuando la empresa la tiene fijada, y el demo rechaza
  las recepciones que se pasan de la capacidad, igual que el
  servidor.
- **1.1.0 (2026-11-20)**: inventario del tanque de combustible
  (tarjetas por tipo con alerta y días estimados, «Recibir
  combustible», despachos que descuentan del saldo) y solicitudes
  de piezas del mecánico (botón «Pedir pieza», atajo en piezas sin
  stock, estado de sus solicitudes en el Inicio).
- **1.0.0 (2026-11-20)**: primera versión — trabajos con pago
  destajo/sueldo, módulo de lavado y módulo de combustible.

## Actualización automática (desde la 1.0.0)

Regla permanente de Miguel: la app comprueba sola al abrir, descarga
con progreso y abre el instalador del sistema. Canal: el archivo
`actualizacion-mecanico.json` en la raíz del repo público
**elprota21/tallerneto** (raw.githubusercontent.com), cuyo `apkUrl`
apunta al asset del último release de GitHub. Implementación:
`lib/servicios/actualizacion.dart` + canal `tallerneto/instalador`
en `MainActivity.kt` (patrón de RutaNeto).

**Firma permanente:** `firma/tallerneto.jks` (alias `tallerneto`),
contraseña SOLO en `firma/clave.txt`. Esa carpeta es local: NUNCA se
sube a GitHub. Sin esta firma exacta, Android rechaza las
actualizaciones por firma distinta.

## Cómo se compila en esta VM (Gradle sin sockets)

Igual que la app de RutaNeto: Java no puede hablar con el daemon de
Gradle en esta red, así que todo corre en proceso.

```sh
export PATH=~/workspace/tools/flutter-sdk/flutter/bin:$PATH
export JAVA_HOME=~/workspace/tools/jdk17
# OJO: se usa el GRADLE_USER_HOME de la app de RutaNeto porque su
# caché ya trae resuelto el plugin kotlin-dsl de flutter_tools (la
# caché propia de TallerNeto nace vacía y Java no puede bajarlo en
# esta red). Es solo caché compartida; no toca el código de RutaNeto.
export GRADLE_USER_HOME=~/workspace/pago-rutas/app/.gradle-home
# Además, android/local.properties debe traer la ruta de CMake:
#   cmake.dir=/home/hatch/workspace/pago-rutas/app/.android-sdk/cmake/3.22.1
# (el plugin jni de package_info_plus lo exige; sin eso el build
# muere en :jni:configureCMake).
JV="-Xmx3G -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=256m --add-exports=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED"
export GRADLE_OPTS="-javaagent:$GRADLE_USER_HOME/wrapper/dists/gradle-9.5.0-bin/415x5jx4juj5k1tgowuuvl6u9/gradle-9.5.0/lib/agents/gradle-instrumentation-agent-9.5.0.jar $JV"
# 1) Capturar la línea de gradlew (falla, pero la imprime):
flutter build apk --release -v
# 2) Repetir esa línea en android/ añadiendo al principio:
#    "-Dorg.gradle.jvmargs=$JV" -Dkotlin.compiler.execution.strategy=in-process
#    y con la tarea assembleRelease.
# APK: build/app/outputs/flutter-apk/app-release.apk
```

El NDK es un enlace simbólico a la copia de la app de RutaNeto
(`app/.ndk → ~/workspace/pago-rutas/app/.ndk`).

## Publicar una versión nueva

1. Subir `version:` en `pubspec.yaml` (ej. `1.1.0+2`).
2. Compilar (arriba) y copiar el APK a `TallerNeto-Mecanico.apk`.
3. `gh release create vX.Y.Z TallerNeto-Mecanico.apk` en el repo
   `elprota21/tallerneto` (asset con ese nombre exacto).
4. Actualizar `actualizacion-mecanico.json` del repo (versionCode,
   versionName, apkUrl del release, notas) y subirlo a `master`.
5. Verificar que `releases/latest/download/TallerNeto-Mecanico.apk`
   baja el APK nuevo (tamaño y firma con apksigner).
