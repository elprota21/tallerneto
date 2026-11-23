import 'package:material_ui/material_ui.dart';

import '../datos/repositorio.dart';
import '../modelos.dart';

/// Inventario por unidad: lo que cada unidad debe llevar.
///
/// Flujo panel → app: la ficha de cada unidad la define el
/// ADMINISTRADOR en el panel; esta pantalla la lee del
/// repositorio tal cual llega del servidor (al abrir y al
/// recargar) — la app no trae listas fijas. Quien puede pasar
/// inventario (el mecánico, o quien el panel autorizó) recorre
/// la ficha marcando cada artículo bueno / dañado / faltante y
/// guarda la pasada; el resultado se ve en el panel. Pasar
/// inventario NUNCA edita la ficha: si falta un artículo en la
/// lista, lo añade administración en el panel.
class PantallaInventarioUnidad extends StatelessWidget {
  const PantallaInventarioUnidad({super.key, required this.repo});

  final RepositorioTaller repo;

  @override
  Widget build(BuildContext context) {
    final datos = repo.datosInventarioUnidad;
    if (datos == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: () => repo.recargarInventarioUnidad(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            datos.puedePasar
                ? 'Elige una unidad y recorre su ficha: marca cada artículo como bueno, dañado o faltante.'
                : 'Estas son las fichas que definió administración. Tu usuario no está autorizado a pasar inventario: puedes consultarlas, y el permiso se concede desde el panel.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          for (final u in datos.unidades) ...[
            Card(
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: const Icon(Icons.directions_bus_outlined, size: 30),
                title: Text(
                  u.vehiculo.etiqueta,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  u.tieneFicha
                      ? '${u.articulos.length} artículos'
                          '${u.ultimaRevisionPor != null ? ' · Última pasada: ${u.ultimaRevisionPor}' : ''}'
                      : 'Administración aún no crea su ficha en el panel',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChipInventarioUnidad(estado: u.estadoGeneral),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PantallaPasarInventario(repo: repo, unidad: u),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// Chip del estado general de una ficha o del estado de un
/// artículo (comparten colores: verde bueno, ámbar dañado,
/// rojo faltante, gris sin revisar / sin ficha).
class ChipInventarioUnidad extends StatelessWidget {
  const ChipInventarioUnidad({super.key, required this.estado});

  /// Estado general ('completa', 'con_faltantes', 'con_danados',
  /// 'sin_revisar', 'sin_ficha') o de artículo ('bueno',
  /// 'danado', 'faltante', 'sin_revisar').
  final String estado;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (Color fondo, Color texto) = switch (estado) {
      'completa' || 'bueno' => (
          Colors.green.withValues(alpha: 0.15),
          Colors.green.shade800
        ),
      'con_faltantes' || 'faltante' => (cs.errorContainer, cs.onErrorContainer),
      'con_danados' || 'danado' => (
          Colors.amber.withValues(alpha: 0.18),
          Colors.amber.shade900
        ),
      _ => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    final etiqueta = switch (estado) {
      'completa' => 'Completa',
      'bueno' => 'Bueno',
      'con_faltantes' => 'Con faltantes',
      'faltante' => 'Faltante',
      'con_danados' => 'Con dañados',
      'danado' => 'Dañado',
      'sin_revisar' => 'Sin revisar',
      _ => 'Sin ficha',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        etiqueta,
        style:
            TextStyle(color: texto, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

/// La pasada en sí: recorre la ficha VIGENTE de la unidad (la
/// que trajo el repositorio del servidor) marcando artículo por
/// artículo. Sin permiso, la ficha se ve en modo consulta.
class PantallaPasarInventario extends StatefulWidget {
  const PantallaPasarInventario({
    super.key,
    required this.repo,
    required this.unidad,
  });

  final RepositorioTaller repo;
  final UnidadInventarioFicha unidad;

  @override
  State<PantallaPasarInventario> createState() =>
      _PantallaPasarInventarioState();
}

class _PantallaPasarInventarioState extends State<PantallaPasarInventario> {
  /// Estado elegido por artículo (null = aún sin marcar) y su
  /// nota. Arranca con el estado de la última pasada, para
  /// confirmar artículo por artículo en vez de teclear de cero.
  final Map<String, String?> _estados = {};
  final Map<String, TextEditingController> _notas = {};
  final TextEditingController _notaGeneral = TextEditingController();
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    for (final a in widget.unidad.articulos) {
      _estados[a.id] = a.estado == 'sin_revisar' ? null : a.estado;
      _notas[a.id] = TextEditingController(text: a.nota ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in _notas.values) {
      c.dispose();
    }
    _notaGeneral.dispose();
    super.dispose();
  }

  bool get _completa =>
      widget.unidad.articulos.every((a) => _estados[a.id] != null);

  Future<void> _guardar() async {
    final repo = widget.repo;
    setState(() => _guardando = true);
    try {
      final revision = await repo.pasarInventarioUnidad(
        vehiculoId: widget.unidad.vehiculo.id,
        marcas: [
          for (final a in widget.unidad.articulos)
            MarcaArticulo(
              articuloId: a.id,
              estado: _estados[a.id]!,
              nota: _notas[a.id]?.text,
            ),
        ],
        nota: _notaGeneral.text,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Inventario guardado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${revision.buenos} buenos · ${revision.danados} dañados · '
                '${revision.faltantes} faltantes (de ${revision.total}).',
              ),
              if (revision.diferencias.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Diferencias detectadas:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                for (final d in revision.diferencias)
                  Text(
                    '• ${d.nombre}: ${ArticuloFichaUnidad.etiquetaEstado(d.estado)}'
                    '${d.nota != null ? ' — ${d.nota}' : ''}',
                  ),
                const SizedBox(height: 8),
                const Text('Administración las ve en el panel.'),
              ],
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.unidad;
    final puedePasar = widget.repo.datosInventarioUnidad?.puedePasar ?? false;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Inventario · ${u.vehiculo.codigo}')),
      body: !u.tieneFicha
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Esta unidad aún no tiene ficha.\nLa crea el administrador en el panel '
                  '(sección «Inventario por unidad») y entonces aparecerá aquí tal cual.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${u.vehiculo.marca} ${u.vehiculo.modelo} · ${u.vehiculo.placa}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  puedePasar
                      ? 'Marca cada artículo. La lista es la que definió administración: no se puede editar aquí.'
                      : 'Modo consulta: tu usuario no puede pasar inventario (el permiso se concede en el panel).',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                for (final a in u.articulos) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  a.nombre,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15),
                                ),
                              ),
                              ChipInventarioUnidad(estado: a.estado),
                            ],
                          ),
                          Text(
                            '${ArticuloFichaUnidad.etiquetaCategoria(a.categoria)}'
                            ' · Cantidad esperada: ${a.cantidadEsperada}',
                            style: TextStyle(
                                color: cs.onSurfaceVariant, fontSize: 13),
                          ),
                          if (puedePasar) ...[
                            const SizedBox(height: 8),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                    value: 'bueno',
                                    icon: Icon(Icons.check_circle_outline),
                                    label: Text('Bueno')),
                                ButtonSegment(
                                    value: 'danado',
                                    icon: Icon(Icons.build_outlined),
                                    label: Text('Dañado')),
                                ButtonSegment(
                                    value: 'faltante',
                                    icon: Icon(Icons.cancel_outlined),
                                    label: Text('Faltante')),
                              ],
                              selected: {
                                if (_estados[a.id] != null) _estados[a.id]!,
                              },
                              emptySelectionAllowed: true,
                              onSelectionChanged: (s) => setState(
                                  () => _estados[a.id] = s.firstOrNull),
                            ),
                            TextField(
                              controller: _notas[a.id],
                              decoration: const InputDecoration(
                                labelText: 'Nota (opcional)',
                                hintText: 'Ej.: está roto el seguro',
                              ),
                            ),
                          ] else if (a.nota != null) ...[
                            const SizedBox(height: 4),
                            Text('Nota: ${a.nota}',
                                style: TextStyle(color: cs.onSurfaceVariant)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (puedePasar) ...[
                  TextField(
                    controller: _notaGeneral,
                    decoration: const InputDecoration(
                      labelText: 'Nota general de la pasada (opcional)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: (_completa && !_guardando) ? _guardar : null,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_guardando
                        ? 'Guardando…'
                        : _completa
                            ? 'Guardar inventario'
                            : 'Marca todos los artículos para guardar'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
