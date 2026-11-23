import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// ================================================================
/// BORRADOR LOCAL del formulario de trabajo (decisión de Miguel,
/// 2026-11-23: punto 6 de la discusión de la app — SOLO borradores).
/// ================================================================
/// Si el mecánico deja un trabajo a medias (eligió la unidad, el
/// tipo, alguna pieza o escribió la descripción y se fue a otra
/// cosa), el formulario se guarda SOLO en este teléfono y al
/// volver a «Registrar» lo encuentra tal como lo dejó.
///
/// Esto NO es una cola de envío ni sincroniza nada:
///  - El borrador nunca sale del teléfono por su cuenta.
///  - Nada se da por registrado hasta que el servidor confirma
///    el trabajo con el botón de confirmar, como siempre.
///  - Al registrarse el trabajo (o al descartar el borrador),
///    el borrador se borra.
/// Se guarda un borrador por usuario (archivo JSON en el
/// directorio de la app, mismo mecanismo que la sesión y la
/// cola de la demo): si dos personas usan el mismo teléfono,
/// cada una ve solo el suyo.
class BorradorTrabajo {
  const BorradorTrabajo({
    required this.usuarioId,
    this.vehiculoId,
    this.tipoTrabajoId,
    this.piezas = const {},
    this.descripcion = '',
    this.paso = 0,
    this.guardadoEn = '',
  });

  final String usuarioId;
  final String? vehiculoId;
  final String? tipoTrabajoId;

  /// piezaId → cantidad.
  final Map<String, int> piezas;
  final String descripcion;

  /// Paso del asistente donde iba (0–4).
  final int paso;

  /// ISO con hora del último guardado.
  final String guardadoEn;

  /// ¿Tiene algo que valga la pena retomar? Un formulario vacío
  /// no se guarda como borrador.
  bool get tieneContenido =>
      vehiculoId != null ||
      tipoTrabajoId != null ||
      piezas.isNotEmpty ||
      descripcion.trim().isNotEmpty;

  Map<String, dynamic> aJson() => {
        'usuarioId': usuarioId,
        'vehiculoId': vehiculoId,
        'tipoTrabajoId': tipoTrabajoId,
        'piezas': piezas,
        'descripcion': descripcion,
        'paso': paso,
        'guardadoEn': guardadoEn,
      };

  factory BorradorTrabajo.desdeJson(Map<String, dynamic> j) =>
      BorradorTrabajo(
        usuarioId: j['usuarioId'].toString(),
        vehiculoId: j['vehiculoId']?.toString(),
        tipoTrabajoId: j['tipoTrabajoId']?.toString(),
        piezas: ((j['piezas'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
        ),
        descripcion: j['descripcion']?.toString() ?? '',
        paso: (j['paso'] as num?)?.toInt() ?? 0,
        guardadoEn: j['guardadoEn']?.toString() ?? '',
      );
}

/// Almacén de borradores: un archivo JSON con un borrador por
/// usuario. Todas las operaciones son tolerantes a fallos (sin
/// almacenamiento, el borrador simplemente vale por la apertura).
class BorradorTrabajoStore {
  static File? _archivoCache;

  static Future<File> _archivo() async {
    final cache = _archivoCache;
    if (cache != null) return cache;
    final dir = await getApplicationDocumentsDirectory();
    return _archivoCache = File('${dir.path}/borradores_tallerneto.json');
  }

  static Future<Map<String, BorradorTrabajo>> _leerTodos() async {
    try {
      final archivo = await _archivo();
      if (!await archivo.exists()) return {};
      final mapa = jsonDecode(await archivo.readAsString())
          as Map<String, dynamic>;
      return mapa.map(
        (k, v) => MapEntry(
          k,
          BorradorTrabajo.desdeJson(v as Map<String, dynamic>),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> _escribirTodos(
      Map<String, BorradorTrabajo> todos) async {
    try {
      final archivo = await _archivo();
      await archivo.writeAsString(
        jsonEncode(todos.map((k, v) => MapEntry(k, v.aJson()))),
      );
    } catch (_) {
      // Sin almacenamiento el borrador vale por esta apertura.
    }
  }

  /// El borrador guardado de este usuario, si lo hay y tiene
  /// contenido.
  static Future<BorradorTrabajo?> cargar(String usuarioId) async {
    final b = (await _leerTodos())[usuarioId];
    if (b == null || !b.tieneContenido) return null;
    return b;
  }

  /// Guarda (o reemplaza) el borrador del usuario. Si el
  /// formulario quedó vacío, lo borra en vez de guardarlo.
  static Future<void> guardar(BorradorTrabajo borrador) async {
    final todos = await _leerTodos();
    if (borrador.tieneContenido) {
      todos[borrador.usuarioId] = borrador;
    } else {
      todos.remove(borrador.usuarioId);
    }
    await _escribirTodos(todos);
  }

  /// Borra el borrador del usuario (trabajo ya registrado o
  /// borrador descartado a propósito).
  static Future<void> borrar(String usuarioId) async {
    final todos = await _leerTodos();
    if (todos.remove(usuarioId) != null) {
      await _escribirTodos(todos);
    }
  }
}
