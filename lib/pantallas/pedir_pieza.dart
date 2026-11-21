import 'package:material_ui/material_ui.dart';

import '../datos/repositorio.dart';
import '../modelos.dart';

/// Formulario para PEDIR una pieza a administración
/// (servidor/solicitudes.sql): la solicitud nace PENDIENTE y
/// administración la gestiona en el panel (pedida → recibida,
/// y el stock entra solo; o rechazada con el motivo).
/// Dos entradas:
///  - Botón «Pedir pieza» de la pantalla del mecánico: elige del
///    catálogo una pieza SIN STOCK o escribe el nombre libre si
///    la pieza no existe en el catálogo.
///  - Atajo desde «Registrar trabajo» cuando una pieza está en
///    0: entra con [piezaInicial] ya elegida (y el vehículo).
class PantallaPedirPieza extends StatefulWidget {
  const PantallaPedirPieza({
    super.key,
    required this.repo,
    this.piezaInicial,
    this.vehiculoIdInicial,
  });

  final RepositorioTaller repo;
  final Pieza? piezaInicial;
  final String? vehiculoIdInicial;

  @override
  State<PantallaPedirPieza> createState() => _PantallaPedirPiezaState();
}

class _PantallaPedirPiezaState extends State<PantallaPedirPieza> {
  /// true = elegir del catálogo (piezas sin stock);
  /// false = texto libre (la pieza no existe en el catálogo).
  bool _modoCatalogo = true;
  Pieza? _pieza;
  final _nombre = TextEditingController();
  final _cantidad = TextEditingController(text: '1');
  Vehiculo? _vehiculo;
  String _urgencia = 'normal';
  final _nota = TextEditingController();
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _pieza = widget.piezaInicial;
    if (widget.piezaInicial != null) _modoCatalogo = true;
    final datos = widget.repo.datosMecanico;
    if (datos != null && widget.vehiculoIdInicial != null) {
      for (final v in datos.vehiculos) {
        if (v.id == widget.vehiculoIdInicial) _vehiculo = v;
      }
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _cantidad.dispose();
    _nota.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final delCatalogo = widget.piezaInicial != null || _modoCatalogo;
    final nombreFinal = widget.piezaInicial?.nombre ??
        (delCatalogo ? _pieza?.nombre : _nombre.text.trim());
    if (delCatalogo && _pieza == null && widget.piezaInicial == null) {
      _avisar('Elige la pieza del catálogo o escribe su nombre.');
      return;
    }
    if (!delCatalogo && (nombreFinal == null || nombreFinal.isEmpty)) {
      _avisar('Escribe el nombre de la pieza que necesitas.');
      return;
    }
    final cantidad = int.tryParse(_cantidad.text.trim()) ?? 0;
    if (cantidad <= 0) {
      _avisar('La cantidad debe ser mayor que cero.');
      return;
    }
    final confirma = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Enviar la solicitud?'),
        content: Text(
          'Pieza: $nombreFinal\n'
          'Cantidad: $cantidad\n'
          'Vehículo: ${_vehiculo?.etiqueta ?? 'sin vehículo específico'}\n'
          'Urgencia: ${_urgencia == 'urgente' ? 'URGENTE' : 'Normal'}\n\n'
          'Administración la ve en el panel: la encarga, la recibe '
          '(el stock entra solo) o la rechaza con el motivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Revisar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sí, pedir'),
          ),
        ],
      ),
    );
    if (confirma != true) return;
    setState(() => _guardando = true);
    try {
      await widget.repo.solicitarPieza(
        piezaId: delCatalogo ? (widget.piezaInicial?.id ?? _pieza?.id) : null,
        nombre: delCatalogo ? null : nombreFinal,
        cantidad: cantidad,
        vehiculoId: _vehiculo?.id,
        urgencia: _urgencia,
        nota: _nota.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _avisar(e.toString());
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _avisar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final datos = widget.repo.datosMecanico;
    if (datos == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final sinStock = datos.piezas.where((p) => p.stock <= 0).toList();
    final fija = widget.piezaInicial;
    return Scaffold(
      appBar: AppBar(title: const Text('Pedir una pieza')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('¿Qué pieza necesitas?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (fija != null) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text('${fija.codigo} · ${fija.nombre}'),
                subtitle: const Text('Sin stock en el almacén'),
                trailing: const Icon(Icons.check_circle),
              ),
            ),
          ] else ...[
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Del catálogo (sin stock)'),
                  selected: _modoCatalogo,
                  onSelected: (_) => setState(() => _modoCatalogo = true),
                ),
                ChoiceChip(
                  label: const Text('No está en el catálogo'),
                  selected: !_modoCatalogo,
                  onSelected: (_) => setState(() => _modoCatalogo = false),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_modoCatalogo) ...[
              if (sinStock.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        'Todas las piezas del catálogo tienen stock. '
                        'Si la que necesitas no existe, elige «No está en el catálogo».'),
                  ),
                ),
              ...sinStock.map(
                (p) => Card(
                  child: ListTile(
                    title: Text('${p.codigo} · ${p.nombre}'),
                    subtitle: const Text('Sin stock'),
                    trailing: _pieza?.id == p.id
                        ? const Icon(Icons.check_circle)
                        : const Icon(Icons.circle_outlined),
                    selected: _pieza?.id == p.id,
                    onTap: () => setState(() => _pieza = p),
                  ),
                ),
              ),
            ] else
              TextField(
                controller: _nombre,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la pieza',
                  hintText: 'Ej.: Correa de accesorios',
                  border: OutlineInputBorder(),
                ),
              ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cantidad,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cantidad',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Urgencia'),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Normal'),
                          selected: _urgencia == 'normal',
                          onSelected: (_) =>
                              setState(() => _urgencia = 'normal'),
                        ),
                        ChoiceChip(
                          label: const Text('Urgente'),
                          selected: _urgencia == 'urgente',
                          onSelected: (_) =>
                              setState(() => _urgencia = 'urgente'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('¿Para qué vehículo? (opcional)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              title: const Text('Sin vehículo específico'),
              trailing: _vehiculo == null
                  ? const Icon(Icons.check_circle)
                  : const Icon(Icons.circle_outlined),
              selected: _vehiculo == null,
              onTap: () => setState(() => _vehiculo = null),
            ),
          ),
          ...datos.vehiculos.map(
            (v) => Card(
              child: ListTile(
                title: Text(v.etiqueta),
                subtitle: Text('Placa ${v.placa}'),
                trailing: _vehiculo?.id == v.id
                    ? const Icon(Icons.check_circle)
                    : const Icon(Icons.circle_outlined),
                selected: _vehiculo?.id == v.id,
                onTap: () => setState(() => _vehiculo = v),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nota,
            decoration: const InputDecoration(
              labelText: 'Nota (opcional)',
              hintText: 'Ej.: la unidad no sale sin esto',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: const Icon(Icons.send_outlined),
            label: Text(_guardando ? 'Enviando…' : 'Enviar solicitud'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}
