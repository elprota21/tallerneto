import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Preferencia de tema del propio usuario: modo DÍA (claro) o modo
/// NOCHE (oscuro). Los mecánicos y el coordinador de lavado trabajan
/// también con luz mala o de noche (misma razón que en RutaNeto:
/// la pantalla clara hace daño en los ojos).
///
/// La preferencia es del TELÉFONO, no del servidor: se guarda en un
/// archivo JSON del directorio de la app (`tema_tallerneto.json`,
/// mismo mecanismo probado de la sesión) y se aplica al instante
/// desde Perfil → «Modo noche». Persiste entre aperturas.
abstract final class TemaApp {
  /// true = modo noche (tema oscuro). La raíz de la app lo escucha y
  /// reconstruye el MaterialApp con el tema que toca.
  static final ValueNotifier<bool> oscuro = ValueNotifier<bool>(false);

  static File? _archivoCache;

  static Future<File> _archivo() async {
    final cache = _archivoCache;
    if (cache != null) return cache;
    final dir = await getApplicationDocumentsDirectory();
    return _archivoCache = File('${dir.path}/tema_tallerneto.json');
  }

  static Map<String, dynamic> temaAGuardar(bool oscuro) => {'oscuro': oscuro};

  static bool oscuroDesdeGuardado(Map<String, dynamic> datos) =>
      datos['oscuro'] == true;

  /// Carga la preferencia al arrancar (antes de pintar la app).
  static Future<void> cargar() async {
    try {
      final archivo = await _archivo();
      if (!await archivo.exists()) return;
      final datos =
          jsonDecode(await archivo.readAsString()) as Map<String, dynamic>;
      oscuro.value = oscuroDesdeGuardado(datos);
    } catch (_) {
      // Sin preferencia legible: modo día.
    }
  }

  /// Cambia el modo y lo guarda. La app se repinta sola al instante.
  static Future<void> fijar(bool valor) async {
    oscuro.value = valor;
    try {
      final archivo = await _archivo();
      await archivo.writeAsString(jsonEncode(temaAGuardar(valor)));
    } catch (_) {
      // Si no se pudo guardar, el modo vale por esta apertura.
    }
  }
}
