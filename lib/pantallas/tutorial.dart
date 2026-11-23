import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

/// ================================================================
/// TUTORIAL DE BIENVENIDA de la app (modo tutorial, pedido de
/// Miguel): la primera vez que un usuario entra, la app le enseña
/// en tarjetas qué hace SU función — para que nadie tenga que
/// explicarle a cada empleado cómo se usa. Cada tarjeta: un paso.
/// Botón «Omitir» siempre visible. Se puede repetir cuando
/// quiera desde el Perfil («Ver tutorial»).
///
/// «Ya lo vio» se guarda POR USUARIO en el teléfono
/// (tutorial_tallerneto.json, mismo mecanismo que la sesión y el
/// tema). Si la empresa apagó el modo tutorial en el panel, la
/// bienvenida no se ofrece sola (el botón del Perfil queda).
/// ================================================================

abstract final class TutorialApp {
  static File? _archivoCache;

  static Future<File> _archivo() async {
    final cache = _archivoCache;
    if (cache != null) return cache;
    final dir = await getApplicationDocumentsDirectory();
    return _archivoCache = File('${dir.path}/tutorial_tallerneto.json');
  }

  static Future<Map<String, dynamic>> _leer() async {
    try {
      final archivo = await _archivo();
      if (!await archivo.exists()) return {};
      return jsonDecode(await archivo.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<bool> yaVisto(String usuarioId) async {
    final datos = await _leer();
    return datos[usuarioId] == true;
  }

  static Future<void> marcarVisto(String usuarioId) async {
    try {
      final datos = await _leer();
      datos[usuarioId] = true;
      final archivo = await _archivo();
      await archivo.writeAsString(jsonEncode(datos));
    } catch (_) {
      // Si no se pudo guardar, se ofrecerá de nuevo: sin daño.
    }
  }
}

class _Paso {
  const _Paso(this.icono, this.titulo, this.texto);
  final IconData icono;
  final String titulo;
  final String texto;
}

/// Las tarjetas del recorrido según el rol en pantalla.
List<_Paso> _pasosPara(String rol) {
  final comunes = <_Paso>[
    const _Paso(
      Icons.waving_hand_outlined,
      'Bienvenido a TallerNeto',
      'Esta es la app de tu taller. En dos minutos te enseño lo que '
          'haces tú aquí, paso a paso. Puedes saltarlo con «Omitir» y '
          'volver a verlo cuando quieras desde tu Perfil.',
    ),
  ];
  final porRol = switch (rol) {
    'mecanico' => const [
        _Paso(
          Icons.build_outlined,
          'Registra tus trabajos',
          'Al terminar un trabajo, tócalo en «Registrar trabajo»: '
              'elige la unidad, el tipo de trabajo y las piezas que '
              'usaste. Queda anotado con la fecha de hoy.',
        ),
        _Paso(
          Icons.hourglass_top_outlined,
          'Administración lo valida',
          'Tu trabajo nace PENDIENTE. Cuando administración lo '
              'valida, empieza a contar para tu pago; si lo rechaza, '
              'verás el motivo en «Mis trabajos».',
        ),
        _Paso(
          Icons.shopping_cart_outlined,
          '¿Te falta una pieza?',
          'Pídela desde «Pedir pieza»: si no hay en stock o no '
              'existe, la solicitud le llega a administración y ves '
              'su estado (pendiente, pedida, recibida) en tu Inicio.',
        ),
        _Paso(
          Icons.payments_outlined,
          'Tu pago, claro',
          'En tu Inicio ves cuánto llevas validado este mes y '
              'cuánto está en revisión. Si cobras a destajo, es la '
              'suma de tus trabajos validados; si es sueldo fijo, '
              'tus trabajos cuentan como productividad.',
        ),
        _Paso(
          Icons.drafts_outlined,
          'Tu borrador se guarda solo',
          'Si dejas un trabajo a medias, lo que llevas llenado '
              'queda guardado como borrador en tu teléfono y lo '
              'retomas donde ibas. Ojo: el trabajo solo queda '
              'registrado cuando lo confirmas y el servidor lo '
              'recibe.',
        ),
      ],
    'lavado' => const [
        _Paso(
          Icons.local_car_wash_outlined,
          'Tu parrilla del día',
          'Aquí están todas las unidades de la empresa: en verde '
              'las que ya se lavaron hoy y en rojo las que faltan. '
              'El conteo del día se ve arriba.',
        ),
        _Paso(
          Icons.touch_app_outlined,
          'Toca para marcar',
          'Cuando una unidad quede lavada, tócala y confirma: '
              'queda registrado quién la marcó y a qué hora. Si te '
              'equivocas, la misma tarjeta permite desmarcarla.',
        ),
        _Paso(
          Icons.cloud_off_outlined,
          'Sin conexión, aviso claro',
          'Si te quedas sin conexión, la app te lo dice claro y '
              'el marcado no se guarda a medias: espera a tener '
              'internet y márcalo, para que administración lo '
              'reciba seguro.',
        ),
      ],
    'combustible' => const [
        _Paso(
          Icons.local_gas_station_outlined,
          'Despacha con odómetro',
          'Cada despacho dice la unidad, los galones y el '
              'odómetro. El odómetro nunca puede bajar del último '
              'registrado: esa es la regla que cuida el combustible. '
              'Despachas con el botón naranja «Registrar despacho», '
              'abajo, y «Despachado hoy», también abajo junto a los '
              'botones, se despliega con un toque para ver lo que '
              'ya salió.',
        ),
        _Paso(
          Icons.oil_barrel_outlined,
          'El tanque se vigila solo',
          'El tanque queda fijo arriba: ves cuánto queda de cada '
              'tipo activo de tu empresa y para cuántos días '
              'alcanza, con su alerta si está bajo. Cuando entra '
              'una carga, regístrala con «Recibir combustible», '
              'también abajo, y el saldo sube solo.',
        ),
        _Paso(
          Icons.cloud_off_outlined,
          'Sin conexión, aviso claro',
          'Si te quedas sin conexión, la app te lo dice claro y '
              'el despacho no se guarda a medias: espera a tener '
              'internet y regístralo, para que el tanque quede '
              'bien cuadrado.',
        ),
      ],
    _ => const [
        _Paso(
          Icons.apps_outlined,
          'Tu función en la app',
          'Desde aquí haces tu parte del taller: la app te enseña '
              'solo las funciones de tu rol. Todo lo demás se '
              'administra en el panel web de TallerNeto.',
        ),
      ],
  };
  return [...comunes, ...porRol];
}

/// Pantalla del recorrido: tarjetas a pantalla completa con
/// Siguiente / Empezar y «Omitir» siempre a la vista.
class PantallaTutorial extends StatefulWidget {
  const PantallaTutorial({super.key, required this.rol});

  /// El rol en pantalla ('mecanico' | 'lavado' | 'combustible').
  final String rol;

  @override
  State<PantallaTutorial> createState() => _PantallaTutorialState();
}

class _PantallaTutorialState extends State<PantallaTutorial> {
  final _controlador = PageController();
  int _indice = 0;

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pasos = _pasosPara(widget.rol);
    final cs = Theme.of(context).colorScheme;
    final esUltimo = _indice >= pasos.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tutorial'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Omitir'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controlador,
              itemCount: pasos.length,
              onPageChanged: (i) => setState(() => _indice = i),
              itemBuilder: (context, i) {
                final paso = pasos[i];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (i == 0) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'assets/logo.png',
                            width: 110,
                            height: 110,
                          ),
                        ),
                        const SizedBox(height: 22),
                      ] else ...[
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Icon(paso.icono,
                              size: 46, color: cs.onPrimaryContainer),
                        ),
                        const SizedBox(height: 22),
                      ],
                      Text(
                        paso.titulo,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        paso.texto,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < pasos.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _indice ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _indice
                        ? cs.primary
                        : cs.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (esUltimo) {
                    Navigator.of(context).pop();
                  } else {
                    _controlador.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: Text(esUltimo ? 'Empezar' : 'Siguiente'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
