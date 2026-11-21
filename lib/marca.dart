/// Marca y canal de actualización de la app «TallerNeto».
///
/// La actualización automática lee un JSON público y plano en el repo
/// de GitHub elprota21/tallerneto (mismo esquema que RutaNeto):
///   { "versionCode": 2, "versionName": "1.1.0",
///     "apkUrl": "https://github.com/elprota21/tallerneto/releases/
///                download/v1.1.0/TallerNeto-Mecanico.apk",
///     "notas": "Qué trae la versión nueva" }
abstract final class Marca {
  static const String nombreApp = 'TallerNeto';
  static const String subtitulo = 'App del taller';

  /// Canal de actualización del mecánico (archivo en la raíz del repo).
  static const String urlActualizacion =
      'https://raw.githubusercontent.com/elprota21/tallerneto/master/actualizacion-mecanico.json';

  static const String notasActualizacionPorDefecto =
      'Mejoras y correcciones de la app del taller.';
}
