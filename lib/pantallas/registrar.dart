import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../datos/repositorio.dart';
import '../modelos.dart';
import '../servicios/borrador.dart';
import 'comun.dart';
import 'pedir_pieza.dart';

/// Registrar un trabajo terminado, por pasos (como la confirmación
/// de RutaNeto):
///   1 · Vehículo → 2 · Tipo de trabajo (con su precio) →
///   3 · Piezas usadas (opcional) → 4 · Descripción (opcional) →
///   5 · Confirmación «¿Terminaste este trabajo?» con el resumen.
/// El trabajo nace PENDIENTE: lo valida administración en el panel.
///
/// BORRADOR LOCAL (1.5.0, decisión de Miguel): lo que se va
/// llenando se guarda SOLO en este teléfono (ver
/// servicios/borrador.dart) y al volver se retoma tal cual, con
/// su aviso visible. El borrador no se envía solo ni cuenta como
/// registrado: solo el botón de confirmar, con el servidor
/// confirmando, crea el trabajo — y ahí el borrador se borra.
class PantallaRegistrar extends StatefulWidget {
  const PantallaRegistrar({super.key, required this.repo, required this.alTerminar});

  final RepositorioTaller repo;

  /// Al registrar con éxito (la principal cambia a Mis trabajos).
  final VoidCallback alTerminar;

  @override
  State<PantallaRegistrar> createState() => _PantallaRegistrarState();
}

class _PantallaRegistrarState extends State<PantallaRegistrar> {
  int _paso = 0;
  Vehiculo? _vehiculo;
  TipoTrabajo? _tipo;
  final Map<String, int> _piezas = {}; // piezaId → cantidad
  final _descripcion = TextEditingController();
  bool _enviando = false;

  /// Borrador: el usuario dueño del borrador y el cargado del
  /// teléfono que aún no se ha volcado al formulario.
  String? _usuarioId;
  BorradorTrabajo? _pendienteRestaurar;
  bool _hayBorrador = false;

  static const _titulos = ['Vehículo', 'Trabajo', 'Piezas', 'Nota', 'Confirmar'];

  @override
  void initState() {
    super.initState();
    _usuarioId = widget.repo.sesion?.id;
    final id = _usuarioId;
    if (id != null) {
      unawaited(() async {
        final b = await BorradorTrabajoStore.cargar(id);
        if (b != null && mounted) {
          setState(() => _pendienteRestaurar = b);
        }
      }());
    }
  }

  bool get _puedeSeguir {
    return switch (_paso) {
      0 => _vehiculo != null,
      1 => _tipo != null,
      _ => true,
    };
  }

  /// Guarda el estado actual del formulario como borrador en el
  /// teléfono (si quedó vacío, el almacén lo borra solo).
  void _guardarBorrador() {
    final id = _usuarioId;
    if (id == null) return;
    final b = BorradorTrabajo(
      usuarioId: id,
      vehiculoId: _vehiculo?.id,
      tipoTrabajoId: _tipo?.id,
      piezas: Map.of(_piezas),
      descripcion: _descripcion.text,
      paso: _paso,
      guardadoEn: DateTime.now().toIso8601String(),
    );
    unawaited(BorradorTrabajoStore.guardar(b));
    if (b.tieneContenido && !_hayBorrador) {
      setState(() => _hayBorrador = true);
    }
  }

  /// Vuelca el borrador cargado al formulario (solo lo que sigue
  /// existiendo en los datos del servidor: unidad, tipo y piezas).
  void _restaurar(BorradorTrabajo b, DatosMecanico datos) {
    Vehiculo? vehiculo;
    for (final v in datos.vehiculos) {
      if (v.id == b.vehiculoId) vehiculo = v;
    }
    TipoTrabajo? tipo;
    for (final t in datos.tiposTrabajo) {
      if (t.id == b.tipoTrabajoId) tipo = t;
    }
    final piezas = <String, int>{};
    for (final e in b.piezas.entries) {
      if (e.value > 0 && datos.piezas.any((p) => p.id == e.key)) {
        piezas[e.key] = e.value;
      }
    }
    var paso = b.paso;
    if (vehiculo == null) {
      paso = 0;
    } else if (tipo == null && paso > 1) {
      paso = 1;
    }
    setState(() {
      _vehiculo = vehiculo;
      _tipo = tipo;
      _piezas
        ..clear()
        ..addAll(piezas);
      _descripcion.text = b.descripcion;
      _paso = paso.clamp(0, 4);
      _hayBorrador = true;
    });
  }

  Future<void> _descartarBorrador() async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Descartar borrador'),
        content: const Text(
            'Se borra el trabajo a medias guardado en este teléfono '
            'y el formulario queda en blanco. ¿Seguro?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sí, descartar'),
          ),
        ],
      ),
    );
    if (confirma != true) return;
    final id = _usuarioId;
    if (id != null) await BorradorTrabajoStore.borrar(id);
    _reiniciar();
    if (mounted) setState(() => _hayBorrador = false);
  }

  void _reiniciar() {
    setState(() {
      _paso = 0;
      _vehiculo = null;
      _tipo = null;
      _piezas.clear();
      _descripcion.clear();
    });
  }

  Future<void> _enviar() async {
    if (_enviando || _vehiculo == null || _tipo == null) return;
    setState(() => _enviando = true);
    try {
      await widget.repo.registrarTrabajo(
        vehiculoId: _vehiculo!.id,
        tipoTrabajoId: _tipo!.id,
        piezas: _piezas.entries
            .map((e) => PiezaUsada(piezaId: e.key, cantidad: e.value))
            .toList(),
        descripcion: _descripcion.text,
      );
      // El servidor ya confirmó el trabajo: el borrador cumplió
      // y se borra (nunca queda un borrador de algo registrado).
      final id = _usuarioId;
      if (id != null) await BorradorTrabajoStore.borrar(id);
      _hayBorrador = false;
      _reiniciar();
      widget.alTerminar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  void dispose() {
    _descripcion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final datos = widget.repo.datosMecanico;
    if (datos == null) {
      return const Center(child: CircularProgressIndicator());
    }
    // Si había un borrador guardado en el teléfono, se vuelca al
    // formulario en cuanto están los datos para resolver sus ids.
    final pendiente = _pendienteRestaurar;
    if (pendiente != null) {
      _pendienteRestaurar = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restaurar(pendiente, datos);
      });
    }
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final colorBorrador =
        oscuro ? const Color(0xFFFBBF24) : const Color(0xFF92400E);
    return Column(
      children: [
        // Aviso del borrador: visible mientras el trabajo a
        // medias vive solo en el teléfono.
        if (_hayBorrador)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.drafts_outlined, size: 18, color: colorBorrador),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Borrador guardado en este teléfono: todavía no '
                    'está en el sistema. Se registra solo cuando '
                    'confirmes el trabajo.',
                    style: TextStyle(fontSize: 12.5, color: colorBorrador),
                  ),
                ),
                TextButton(
                  onPressed: _descartarBorrador,
                  child: const Text('Descartar'),
                ),
              ],
            ),
          ),
        // Indicador de pasos
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              for (var i = 0; i < _titulos.length; i++) ...[
                if (i > 0) const Expanded(child: Divider()),
                Column(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: i <= _paso
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          color: i <= _paso
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(_titulos[i], style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ],
            ],
          ),
        ),
        Expanded(child: _contenido(datos)),
        // Botones de navegación
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (_paso > 0)
                OutlinedButton(
                  onPressed: _enviando
                      ? null
                      : () {
                          setState(() => _paso -= 1);
                          _guardarBorrador();
                        },
                  child: const Text('Atrás'),
                ),
              const Spacer(),
              if (_paso < 4)
                FilledButton(
                  onPressed: _puedeSeguir
                      ? () {
                          setState(() => _paso += 1);
                          _guardarBorrador();
                        }
                      : null,
                  child: const Text('Continuar'),
                ),
              if (_paso == 4)
                FilledButton.icon(
                  onPressed: _enviando ? null : _enviar,
                  icon: const Icon(Icons.check),
                  label: Text(_enviando ? 'Enviando…' : 'Sí, registrar trabajo'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _contenido(DatosMecanico datos) {
    switch (_paso) {
      case 0:
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('¿En qué vehículo trabajaste?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...datos.vehiculos.map(
              (v) => Card(
                child: ListTile(
                  title: Text('${v.codigo} · ${v.marca} ${v.modelo}'),
                  subtitle: Text('Placa ${v.placa}'),
                  trailing: _vehiculo?.id == v.id
                      ? const Icon(Icons.check_circle)
                      : const Icon(Icons.circle_outlined),
                  selected: _vehiculo?.id == v.id,
                  onTap: () {
                    setState(() => _vehiculo = v);
                    _guardarBorrador();
                  },
                ),
              ),
            ),
          ],
        );
      case 1:
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('¿Qué trabajo terminaste?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('El precio es la mano de obra de ese trabajo.'),
            const SizedBox(height: 8),
            ...datos.tiposTrabajo.map(
              (t) => Card(
                child: ListTile(
                  title: Text(t.nombre),
                  subtitle: Text(t.codigo),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(dinero(t.precioManoObra),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(width: 8),
                      if (_tipo?.id == t.id)
                        const Icon(Icons.check_circle)
                      else
                        const Icon(Icons.circle_outlined),
                    ],
                  ),
                  selected: _tipo?.id == t.id,
                  onTap: () {
                    setState(() => _tipo = t);
                    _guardarBorrador();
                  },
                ),
              ),
            ),
          ],
        );
      case 2:
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Piezas que usaste (opcional)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
                'Se descuentan del inventario cuando administración valide '
                'el trabajo. Si no usaste piezas, sigue sin marcar nada.'),
            const SizedBox(height: 8),
            ...datos.piezas.map((p) {
              final cantidad = _piezas[p.id] ?? 0;
              return Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      title: Text(p.nombre),
                      subtitle: Text(p.stock <= 0
                          ? '${p.codigo} · SIN STOCK'
                          : '${p.codigo} · quedan ${p.stock}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: cantidad == 0
                                ? null
                                : () {
                                    setState(() {
                                      if (cantidad <= 1) {
                                        _piezas.remove(p.id);
                                      } else {
                                        _piezas[p.id] = cantidad - 1;
                                      }
                                    });
                                    _guardarBorrador();
                                  },
                          ),
                          Text('$cantidad',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () {
                              setState(() => _piezas[p.id] = cantidad + 1);
                              _guardarBorrador();
                            },
                          ),
                        ],
                      ),
                    ),
                    // Atajo: si la pieza no tiene stock, se puede
                    // pedir a administración sin salir del registro.
                    if (p.stock <= 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TextButton.icon(
                          onPressed: () async {
                            final ok = await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => PantallaPedirPieza(
                                  repo: widget.repo,
                                  piezaInicial: p,
                                  vehiculoIdInicial: _vehiculo?.id,
                                ),
                              ),
                            );
                            if (ok == true && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Solicitud enviada: administración la verá en el panel.')),
                              );
                            }
                          },
                          icon: const Icon(Icons.add_shopping_cart_outlined),
                          label: const Text('Pedir esta pieza'),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        );
      case 3:
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Descripción (opcional)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _descripcion,
              maxLines: 4,
              onChanged: (_) => _guardarBorrador(),
              decoration: const InputDecoration(
                hintText: 'Ej.: Pastillas delanteras, sonaban al frenar',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        );
      default:
        // Confirmación con el resumen, antes de enviar.
        final piezasTexto = _piezas.entries.map((e) {
          final p = datos.piezas.firstWhere((x) => x.id == e.key);
          return '${p.nombre} × ${e.value}';
        }).join('\n');
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('¿Terminaste este trabajo?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _filaResumen('Vehículo', _vehiculo?.etiqueta ?? ''),
                    _filaResumen('Trabajo', _tipo?.nombre ?? ''),
                    if (!datos.usuario.esSueldo)
                      _filaResumen('Mano de obra', dinero(_tipo?.precioManoObra ?? 0)),
                    _filaResumen('Piezas',
                        _piezas.isEmpty ? 'Sin piezas' : piezasTexto),
                    _filaResumen(
                        'Descripción',
                        _descripcion.text.trim().isEmpty
                            ? '—'
                            : _descripcion.text.trim()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
                'El trabajo queda PENDIENTE hasta que administración lo '
                'valide en el panel. Ahí empieza a contar para tu pago.'),
          ],
        );
    }
  }

  Widget _filaResumen(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(etiqueta,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }
}
