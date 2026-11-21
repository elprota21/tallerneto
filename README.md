# TallerNeto — app del personal del taller

Una sola app, funciones según el ROL de quien entra:

| Rol | Código demo | Qué ve |
|---|---|---|
| Mecánico a destajo | `MEC-01` | Inicio con «Llevo ganado» (suma de trabajos validados del mes) y «En revisión», Registrar trabajo por pasos, Historial, Perfil |
| Mecánico con sueldo | `MEC-02` | Igual, pero el Inicio muestra «Tu sueldo: RD$35,000» y sus trabajos como productividad |
| Coordinador de lavado | `LAV-01` | Interfaz de lavado: guaguas de hoy con marcado/desmarcado y resumen «Lavadas hoy: X de Y» (solo si la empresa tiene el módulo activo) |
| Despachador de combustible | `COM-01` | Interfaz de combustible: despachos de hoy, total de galones del día y registrar despacho (vehículo + galones + tipo + odómetro que no puede bajar + costo por galón) (solo si la empresa tiene el módulo activo) |

PIN demo de todos: **1234**. Tema M3 con **modo noche/día** en el
Perfil (preferencia guardada en el teléfono).

## Modo demo (sin servidor)

La app funciona COMPLETA sin backend: los datos semilla viven en
`lib/datos/repositorio_demo.dart` y son equivalentes a los del panel
demo y a la semilla SQL («Transportes Demo», lavado activado,
catálogo de 6 trabajos, trabajos en estados mixtos, 3 guaguas ya
lavadas hoy). Registrar trabajos y marcar lavados funciona en el
momento, en memoria + sesión guardada en el teléfono.

## Conexión a Supabase (preparada, sin activar)

El proyecto Supabase «taller-neto» aún no existe (límite de
proyectos gratuitos; ver el informe del módulo). El punto de
conexión está documentado en `lib/datos/conexion.dart`: cuando el
proyecto exista se rellenan URL + llave anon, se aplica el SQL del
servidor (esquema → trabajos → lavado) y se crea `RepositorioReal`
contra las RPC `pr_iniciar_sesion`, `pr_datos_mecanico`,
`pr_registrar_trabajo`, `pr_datos_lavado`, `pr_marcar_lavado` y
`pr_desmarcar_lavado`, sin tocar las pantallas.

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
