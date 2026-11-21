import 'package:material_ui/material_ui.dart';

import '../datos/repositorio.dart';
import '../modelos.dart';
import 'comun.dart';

/// Formulario de despacho de combustible:
///   vehículo (obligatorio, con su último odómetro a la vista) →
///   tipo (diésel/gasolina/GLP) con el costo por galón PRECARGADO
///   con el precio sugerido y editable → galones → odómetro →
///   total calculado en vivo → CONFIRMACIÓN antes de guardar.
/// El odómetro no puede ser menor que el último del vehículo:
/// el servidor (y la demo) lo rechazan con un error claro.
class PantallaDespachoForm extends StatefulWidget {
  const PantallaDespachoForm({super.key, required this.repo});

  final RepositorioTaller repo;

  @override
  State<PantallaDespachoForm> createState() => _PantallaDespachoFormState();
}

class _PantallaDespachoFormState extends State<PantallaDespachoForm> {
  VehiculoCombustible? _vehiculo;
  TipoCombustible? _tipo;
  final _galones = TextEditingController();
  final _odometro = TextEditingController();
  final _costo = TextEditingController();
  bool _guardando = false;

  double get _gal => double.tryParse(_galones.text.replaceAll(',', '.')) ?? 0;
  double get _costoGal => double.tryParse(_costo.text.replaceAll(',', '.')) ?? 0;
  double get _total => _gal * _costoGal;

  @override
  void initState() {
    super.initState();
    final datos = widget.repo.datosCombustible;
    if (datos != null && datos.tipos.isNotEmpty) {
      _tipo = datos.tipos.first;
      _costo.text = _tipo!.precioSugerido.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _galones.dispose();
    _odometro.dispose();
    _costo.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final datos = widget.repo.datosCombustible;
    if (datos == null || _vehiculo == null || _tipo == null) return;
    final odo = double.tryParse(_odometro.text.replaceAll(',', '.'));
    if (_gal <= 0) {
      _avisar('Escribe la cantidad de galones (mayor que cero).');
      return;
    }
    if (odo == null || odo < 0) {
      _avisar('Escribe el odómetro del vehículo al despachar.');
      return;
    }
    if (_costoGal < 0) {
      _avisar('El costo por galón no puede ser negativo.');
      return;
    }
    // Confirmación antes de guardar, con el resumen completo.
    final confirma = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Confirmar despacho?'),
        content: Text(
          'Vehículo: ${_vehiculo!.vehiculo.etiqueta}\n'
          'Combustible: ${_tipo!.etiqueta}\n'
          'Cantidad: $_gal galones\n'
          'Odómetro: ${odo.toStringAsFixed(0)} km\n'
          'Costo por galón: ${dinero(_costoGal)}\n'
          'TOTAL: ${dinero(_total)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Revisar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sí, guardar'),
          ),
        ],
      ),
    );
    if (confirma != true) return;
    setState(() => _guardando = true);
    try {
      await widget.repo.registrarDespacho(
        vehiculoId: _vehiculo!.vehiculo.id,
        galones: _gal,
        tipo: _tipo!.tipo,
        odometro: odo,
        costoUnitario: _costoGal,
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final datos = widget.repo.datosCombustible;
    if (datos == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar despacho')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Vehículo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...datos.vehiculos.map(
            (vc) => Card(
              child: ListTile(
                title: Text(
                    '${vc.vehiculo.codigo} · ${vc.vehiculo.marca} ${vc.vehiculo.modelo}'),
                subtitle: Text(vc.ultimoOdometro == null
                    ? 'Placa ${vc.vehiculo.placa} · sin despachos todavía'
                    : 'Placa ${vc.vehiculo.placa} · último odómetro: '
                        '${vc.ultimoOdometro!.toStringAsFixed(0)} km'),
                trailing: _vehiculo?.vehiculo.id == vc.vehiculo.id
                    ? const Icon(Icons.check_circle)
                    : const Icon(Icons.circle_outlined),
                selected: _vehiculo?.vehiculo.id == vc.vehiculo.id,
                onTap: () => setState(() => _vehiculo = vc),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Tipo de combustible',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final t in datos.tipos)
                ChoiceChip(
                  label: Text('${t.etiqueta} · ${dinero(t.precioSugerido)}/gal'),
                  selected: _tipo?.tipo == t.tipo,
                  onSelected: (_) => setState(() {
                    _tipo = t;
                    _costo.text = t.precioSugerido.toStringAsFixed(0);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _galones,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Galones',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _costo,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Costo por galón (RD\$)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _odometro,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Odómetro al despachar (km)',
              hintText: _vehiculo?.ultimoOdometro != null
                  ? 'Último: ${_vehiculo!.ultimoOdometro!.toStringAsFixed(0)} km (no puede bajar)'
                  : 'Ej.: 121200',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOTAL',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(dinero(_total),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed:
                _guardando || _vehiculo == null || _tipo == null ? null : _guardar,
            icon: const Icon(Icons.local_gas_station),
            label: Text(_guardando ? 'Guardando…' : 'Guardar despacho'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          if (_vehiculo == null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Primero elige el vehículo: todo despacho lo exige.'),
            ),
        ],
      ),
    );
  }
}
