/// ================================================================
/// PUNTO DE CONEXIÓN A SUPABASE — PREPARADO, SIN ACTIVAR TODAVÍA.
/// ================================================================
/// Hoy la app corre en MODO DEMO (datos locales, ver
/// repositorio_demo.dart). ACTUALIZACIÓN 2026-11-21: la producción
/// de TallerNeto vive dentro del proyecto Supabase «staffride»
/// (cuenta ml) y las constantes de abajo YA apuntan a él; la app
/// sigue en demo hasta que exista `RepositorioReal` y se publique
/// la versión única con todos los cambios juntos (orden de Miguel).
///
/// CUANDO EL PROYECTO EXISTA, para conectar la app de verdad:
///   1. En Supabase: aplicar en orden servidor/esquema.sql,
///      servidor/trabajos.sql, servidor/lavado.sql,
///      servidor/combustible.sql, servidor/tanque.sql,
///      servidor/solicitudes.sql y servidor/roles.sql (con sus
///      datos-*-demo.sql si se quiere la demo sembrada). El login
///      devuelve `rolAdicional` además de `rol`: con dos roles con
///      pantalla, la app pide elegir función al entrar.
///   2. Rellenar aquí la URL del proyecto y la llave «anon» pública
///      (la misma que usa el panel en panel/src/config.ts; la llave
///      anon es pública por diseño — la seguridad la dan las
///      funciones pr_* con sesión y RLS sin políticas).
///   3. Crear `RepositorioReal` espejo de las RPC:
///        pr_iniciar_sesion(codigo, pin, 'app')  → sesión + token
///        pr_datos_mecanico(quien, token)        → DatosMecanico
///        pr_registrar_trabajo(...)              → Trabajo
///        pr_datos_lavado(quien, token)          → DatosLavado
///        pr_marcar_lavado / pr_desmarcar_lavado → DatosLavado
///        pr_datos_combustible(quien, token)     → DatosCombustible
///        pr_registrar_despacho(...)             → DatosCombustible
///        pr_registrar_recepcion(...)            → DatosCombustible
///        pr_solicitar_pieza(...)                → DatosMecanico
///      (mismo patrón que la app de RutaNeto, lib/datos/
///      repositorio_real.dart) y devolverlo en `crearRepositorio()`
///      de repositorio.dart cuando [hayConexion] sea true.
///   4. Subir la versión (pubspec + canal de actualización) y
///      publicar el release: la app se actualiza sola en los
///      teléfonos, sin reinstalar a mano.
abstract final class Conexion {
  /// URL del proyecto Supabase de producción («staffride»).
  static const String urlSupabase = 'https://qkwzcbdocriuwfblndlk.supabase.co';

  /// Llave «anon» pública del proyecto (pública por diseño).
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFrd3pjYmRvY3JpdXdmYmxuZGxrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ1MzgxODYsImV4cCI6MjExMDExNDE4Nn0.hL5_aDnSpCz6dptk0FLntkQCINObl5zDcm3Bb8xVejg';

  static bool get hayConexion => urlSupabase.isNotEmpty && anonKey.isNotEmpty;
}
