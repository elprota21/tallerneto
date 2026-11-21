import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// COLA DE SALIDA (offline) de la app.
///
/// Todo registro que el personal crea en el teléfono (un trabajo,
/// un marcado de lavado, un despacho, una recepción, una
/// solicitud de pieza) entra primero aquí: queda GUARDADO en el
/// propio teléfono (archivo JSON en el directorio de la app,
/// mismo mecanismo que la sesión y el tema) con el sello de
/// «Pendiente de envío», y sale cuando hay conexión — con el
/// reintento automático o con el botón «Sincronizar ahora» del
/// Perfil.
///
/// En esta versión la app corre en modo demo (repositorio local),
/// así que «enviar» significa que el repositorio demo confirma el
/// registro: nace pendiente y pasa a enviado al sincronizar, tal
/// cual lo verá el usuario cuando exista el servidor. La cola
/// guarda solo la REFERENCIA del registro (tipo + id + una
/// descripción legible); el registro en sí vive en el
/// repositorio, que es quien lo marca enviado.
class ElementoCola {
  const ElementoCola({
    required this.tipo,
    required this.registroId,
    required this.descripcion,
    required this.creadaEn,
  });

  /// 'trabajo' | 'solicitud' | 'despacho' | 'recepcion' | 'lavado'
  final String tipo;

  /// Id del registro en el repositorio (en lavado: el id del
  /// vehículo, porque el marcado es por vehículo y día).
  final String registroId;

  /// Texto corto para mostrar en el Perfil («Trabajo: Cambio de
  /// aceite · V-03»).
  final String descripcion;

  /// ISO con hora de cuándo se guardó en el teléfono.
  final String creadaEn;

  Map<String, dynamic> aJson() => {
        'tipo': tipo,
        'registroId': registroId,
        'descripcion': descripcion,
        'creadaEn': creadaEn,
      };

  factory ElementoCola.desdeJson(Map<String, dynamic> j) => ElementoCola(
        tipo: j['tipo'].toString(),
        registroId: j['registroId'].toString(),
        descripcion: j['descripcion']?.toString() ?? '',
        creadaEn: j['creadaEn']?.toString() ?? '',
      );
}

class ColaSalida {
  final List<ElementoCola> _items = [];
  File? _archivoCache;

  List<ElementoCola> get items => List.unmodifiable(_items);
  int get cantidad => _items.length;
  bool get vacia => _items.isEmpty;

  bool contiene(String tipo, String registroId) =>
      _items.any((e) => e.tipo == tipo && e.registroId == registroId);

  Future<File> _archivo() async {
    final cache = _archivoCache;
    if (cache != null) return cache;
    final dir = await getApplicationDocumentsDirectory();
    return _archivoCache = File('${dir.path}/cola_tallerneto.json');
  }

  /// Carga la cola guardada (al arrancar / al entrar). Si el
  /// archivo no existe o está dañado, la cola arranca vacía.
  Future<void> cargar() async {
    try {
      final archivo = await _archivo();
      if (!await archivo.exists()) return;
      final lista = jsonDecode(await archivo.readAsString()) as List;
      _items
        ..clear()
        ..addAll(lista.map(
          (e) => ElementoCola.desdeJson(e as Map<String, dynamic>),
        ));
    } catch (_) {
      _items.clear();
    }
  }

  Future<void> _guardar() async {
    try {
      final archivo = await _archivo();
      await archivo.writeAsString(
        jsonEncode(_items.map((e) => e.aJson()).toList()),
      );
    } catch (_) {
      // Sin almacenamiento la cola vale por esta apertura.
    }
  }

  /// Añade un registro a la cola. Si ya había uno igual (mismo
  /// tipo y registro — ej.: marcar y desmarcar la misma guagua),
  /// se REEMPLAZA: lo que vale es la última acción.
  Future<void> agregar(ElementoCola elemento) async {
    _items.removeWhere(
      (e) => e.tipo == elemento.tipo && e.registroId == elemento.registroId,
    );
    _items.add(elemento);
    await _guardar();
  }

  /// Quita un registro (ya enviado).
  Future<void> quitar(String tipo, String registroId) async {
    _items.removeWhere((e) => e.tipo == tipo && e.registroId == registroId);
    await _guardar();
  }

  /// Vacía la cola (todo enviado).
  Future<void> vaciar() async {
    _items.clear();
    await _guardar();
  }
}
