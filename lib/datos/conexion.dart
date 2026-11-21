/// ================================================================
/// PUNTO DE CONEXIÓN A SUPABASE — PREPARADO, SIN ACTIVAR TODAVÍA.
/// ================================================================
/// Hoy la app corre en MODO DEMO (datos locales, ver
/// repositorio_demo.dart) porque el proyecto Supabase «taller-neto»
/// aún no existe: la cuenta gratuita está al límite de proyectos y
/// crear el de TallerNeto espera la aprobación de Miguel (pausar un
/// proyecto vacío de la otra cuenta).
///
/// CUANDO EL PROYECTO EXISTA, para conectar la app de verdad:
///   1. En Supabase: aplicar en orden servidor/esquema.sql,
///      servidor/trabajos.sql, servidor/lavado.sql,
///      servidor/combustible.sql, servidor/tanque.sql y
///      servidor/solicitudes.sql (con sus datos-*-demo.sql si se
///      quiere la demo sembrada).
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
  /// URL del proyecto Supabase (vacía = modo demo).
  static const String urlSupabase = '';

  /// Llave «anon» pública del proyecto (vacía = modo demo).
  static const String anonKey = '';

  static bool get hayConexion => urlSupabase.isNotEmpty && anonKey.isNotEmpty;
}
