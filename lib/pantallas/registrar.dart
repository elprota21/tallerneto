import 'package:material_ui/material_ui.dart';

import '../datos/repositorio.dart';
import '../modelos.dart';
import 'comun.dart';
import 'pedir_pieza.dart';

/// Registrar un trabajo terminado, por pasos (como la confirmación
/// de RutaNeto):
///   1 · Vehículo → 2 · Tipo de trabajo (con su precio) →
///   3 · Piezas usadas (opcional) → 4 · Descripción (opcional) →
///   5 · Confirmación «¿Terminaste este trabajo?» con el resumen.
/// El trabajo nace PENDIENTE: lo valida administración en el panel.
class PantallaRegistrar extends StatefulWidget {
  const PantallaRegistrar({super.key, required this.repo, required this.alTerminar});

  final RepositorioTaller repo;

  /// Al registrar con éxito (la principal cambia a Historial).
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

  static const _titulos = ['Vehículo', 'Trabajo', 'Piezas', 'Nota', 'Confirmar'];

  bool get _puedeSeguir {
    return switch (_paso) {
      0 => _vehiculo != null,
      1 => _tipo != null,
      _ => true,
    };
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
    return Column(
      children: [
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
                  onPressed: _enviando ? null : () => setState(() => _paso -= 1),
                  child: const Text('Atrás'),
                ),
              const Spacer(),
              if (_paso < 4)
                FilledButton(
                  onPressed: _puedeSeguir ? () => setState(() => _paso += 1) : null,
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
                  onTap: () => setState(() => _vehiculo = v),
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
                  onTap: () => setState(() => _tipo = t),
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
                                : () => setState(() {
                                      if (cantidad <= 1) {
                                        _piezas.remove(p.id);
                                      } else {
                                        _piezas[p.id] = cantidad - 1;
                                      }
                                    }),
                          ),
                          Text('$cantidad',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () =>
                                setState(() => _piezas[p.id] = cantidad + 1),
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
