import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../marca.dart';

/// Actualización AUTOMÁTICA dentro de la app (regla permanente de
/// Miguel: la app comprueba sola al abrir, descarga con progreso y
/// abre el instalador del sistema; la instalación manual es solo la
/// primera vez). Activa desde esta primera versión (1.0.0).
///
/// Canal: un JSON público y plano en el repo elprota21/tallerneto
/// (mismo esquema que RutaNeto): ver [Marca.urlActualizacion].
///
/// Sin red o sin respuesta válida, la app sigue normal: nunca
/// bloquea la entrada. Mismo patrón probado en la app de RutaNeto.
class Actualizador {
  static String get urlConfig => Marca.urlActualizacion;

  static const _canal = MethodChannel('tallerneto/instalador');

  static bool _comprobando = false;
  static DateTime? _ultimaComprobacionOk;

  /// Comprueba si hay versión nueva y, si la hay, la ofrece con un
  /// diálogo. [alEstado] recibe textos cortos de estado.
  static Future<void> comprobar(
    BuildContext context, {
    void Function(String)? alEstado,
    bool forzar = false,
  }) async {
    if (_comprobando) return;
    final ultima = _ultimaComprobacionOk;
    if (!forzar &&
        ultima != null &&
        DateTime.now().difference(ultima) < const Duration(minutes: 30)) {
      return;
    }
    _comprobando = true;
    try {
      final info = await PackageInfo.fromPlatform();
      final actual = int.tryParse(info.buildNumber) ?? 0;
      final respuesta = await http
          .get(Uri.parse(urlConfig))
          .timeout(const Duration(seconds: 12));
      if (respuesta.statusCode != 200) {
        alEstado?.call('No se pudo comprobar actualizaciones.');
        return;
      }
      _ultimaComprobacionOk = DateTime.now();
      final datos = jsonDecode(respuesta.body) as Map<String, dynamic>;
      final remoto = (datos['versionCode'] as num?)?.toInt() ?? 0;
      final apkUrl = datos['apkUrl']?.toString() ?? '';
      if (remoto <= actual || apkUrl.isEmpty) {
        alEstado?.call('La app está al día.');
        return;
      }
      alEstado?.call('Hay una versión nueva de la app.');
      if (!context.mounted) return;
      final notas =
          datos['notas']?.toString() ?? Marca.notasActualizacionPorDefecto;
      final nombreVersion = datos['versionName']?.toString();
      final acepta = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(nombreVersion == null
              ? 'Actualización disponible'
              : 'Actualización disponible ($nombreVersion)'),
          content: Text(notas),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('DESPUÉS'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('ACTUALIZAR'),
            ),
          ],
        ),
      );
      if (acepta != true || !context.mounted) return;
      await _descargarEInstalar(context, apkUrl);
    } catch (_) {
      // Sin conexión o canal aún sin publicar: la app sigue funcionando.
      alEstado?.call('Sin conexión para comprobar actualizaciones.');
    } finally {
      _comprobando = false;
    }
  }

  static Future<void> _descargarEInstalar(
      BuildContext context, String url) async {
    final progreso = ValueNotifier<_Progreso>(const _Progreso(0, 0));
    var cancelado = false;
    var dialogoAbierto = true;
    StreamSubscription<List<int>>? suscripcion;
    final cliente = http.Client();

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Descargando actualización…'),
        content: ValueListenableBuilder<_Progreso>(
          valueListenable: progreso,
          builder: (_, p, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                  value: p.fraccion > 0 ? p.fraccion : null),
              const SizedBox(height: 12),
              Text(p.total > 0
                  ? '${(p.fraccion * 100).toStringAsFixed(0)} % · '
                      '${p.mbRecibidos} / ${p.mbTotal} MB'
                  : 'Descargando… ${p.mbRecibidos} MB'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelado = true;
              Navigator.pop(c);
            },
            child: const Text('CANCELAR'),
          ),
        ],
      ),
    ).whenComplete(() => dialogoAbierto = false));

    File? archivo;
    try {
      final dir = await getTemporaryDirectory();
      archivo = File('${dir.path}/tallerneto-mecanico.apk');
      final respuesta = await cliente.send(http.Request('GET', Uri.parse(url)));
      if (respuesta.statusCode != 200) {
        throw 'El servidor respondió ${respuesta.statusCode}';
      }
      final total = respuesta.contentLength ?? 0;
      var recibidos = 0;
      // Detección de atasco: si la conexión se traba a mitad de la
      // descarga (sin datos nuevos en ~20 s, o más de 4 min en
      // total), se aborta sola en vez de dejar el diálogo de
      // progreso colgado para siempre con la app «congelada».
      var atascada = false;
      var ultimoByte = DateTime.now();
      final inicioDescarga = DateTime.now();
      final sink = archivo.openWrite();
      final completer = Completer<void>();
      unawaited(completer.future.catchError((_) {}));
      suscripcion = respuesta.stream.listen(
        (chunk) {
          if (cancelado) return;
          sink.add(chunk);
          recibidos += chunk.length;
          ultimoByte = DateTime.now();
          progreso.value = _Progreso(recibidos, total);
        },
        onDone: () => completer.complete(),
        onError: completer.completeError,
        cancelOnError: true,
      );
      // Vigila la cancelación y el atasco mientras baja.
      while (!completer.isCompleted && !cancelado) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        final ahora = DateTime.now();
        if (ahora.difference(ultimoByte) > const Duration(seconds: 20) ||
            ahora.difference(inicioDescarga) > const Duration(minutes: 4)) {
          atascada = true;
          cancelado = true;
        }
      }
      await suscripcion.cancel();
      await sink.close();
      if (cancelado) {
        if (await archivo.exists()) await archivo.delete();
        if (atascada && context.mounted) {
          // Nadie cerró el diálogo (no fue el botón CANCELAR): se
          // cierra aquí y se avisa con un mensaje claro, para que la
          // app quede usable y el usuario pueda reintentar.
          if (dialogoAbierto) Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('La descarga se interrumpió por la conexión. '
                  'Revisa tu internet y toca Buscar actualización para '
                  'reintentar.'),
              duration: Duration(seconds: 6),
            ),
          );
        }
        return;
      }
      await completer.future; // relanza aquí si el stream falló
      if (context.mounted && dialogoAbierto) {
        Navigator.pop(context); // cierra el progreso
      }

      // Permiso de instalar apps desconocidas (Android 8+): si falta,
      // se guía al usuario en español hasta los ajustes del sistema.
      var puede = true;
      try {
        puede = await _canal.invokeMethod<bool>('puedeInstalar') ?? true;
      } catch (_) {
        puede = true; // Si el canal falla, se intenta instalar igual.
      }
      if (!puede) {
        if (!context.mounted) return;
        final ir = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Permiso para instalar'),
            content: const Text(
                'La actualización ya se descargó, pero Android necesita '
                'que permitas instalar aplicaciones desde esta app.\n\n'
                'Toca «IR A AJUSTES» y activa la opción '
                '«Permitir desde esta fuente». Después vuelve y la '
                'instalación continuará.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('AHORA NO'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('IR A AJUSTES'),
              ),
            ],
          ),
        );
        if (ir == true) {
          await _canal.invokeMethod('abrirAjustesInstalar');
          // Al volver de los ajustes, la instalación continúa sola si
          // el permiso ya quedó activo.
          _reanudarInstalacionAlVolver(archivo.path);
        }
        return;
      }

      // Abre el instalador del sistema con el APK descargado.
      await _canal.invokeMethod('instalar', {'ruta': archivo.path});
    } catch (e) {
      if (archivo != null && await archivo.exists()) {
        await archivo.delete();
      }
      if (context.mounted) {
        if (dialogoAbierto) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar: $e')),
        );
      }
    } finally {
      cliente.close();
      progreso.dispose();
    }
  }

  /// Cuando la app vuelve a primer plano tras los ajustes de
  /// «instalar apps desconocidas», si el permiso ya está activo se
  /// abre el instalador con el APK ya descargado.
  static void _reanudarInstalacionAlVolver(String ruta) {
    late final _ObservadorReanudar observador;
    observador = _ObservadorReanudar(() async {
      WidgetsBinding.instance.removeObserver(observador);
      var puede = false;
      try {
        puede = await _canal.invokeMethod<bool>('puedeInstalar') ?? false;
      } catch (_) {
        puede = false;
      }
      if (puede) {
        try {
          await _canal.invokeMethod('instalar', {'ruta': ruta});
        } catch (_) {
          // Si falla, el usuario puede reintentar desde Perfil.
        }
      }
    });
    WidgetsBinding.instance.addObserver(observador);
  }
}

/// Observador de ciclo de vida de un solo disparo.
class _ObservadorReanudar with WidgetsBindingObserver {
  _ObservadorReanudar(this.alVolver);

  final Future<void> Function() alVolver;
  bool _disparado = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed && !_disparado) {
      _disparado = true;
      alVolver();
    }
  }
}

class _Progreso {
  const _Progreso(this.recibidos, this.total);

  final int recibidos;
  final int total;

  double get fraccion => total > 0 ? recibidos / total : 0;
  String get mbRecibidos => (recibidos / (1024 * 1024)).toStringAsFixed(1);
  String get mbTotal => (total / (1024 * 1024)).toStringAsFixed(1);
}
