import 'package:material_ui/material_ui.dart';

import '../datos/repositorio.dart';
import '../modelos.dart';
import 'comun.dart';

/// Formulario de RECEPCIÓN de combustible: la carga que entra
/// al tanque de la empresa.
///   tipo (con el saldo actual a la vista) → galones → costo por
///   galón de compra (precargado con el precio sugerido, editable)
///   → proveedor opcional → nota opcional → CONFIRMACIÓN → guarda.
/// Al guardar, el saldo del tipo sube en el acto y los despachos
/// pueden seguir saliendo; si el tanque estaba en alerta, sale
/// de ella cuando el saldo supera el umbral.
class PantallaRecepcionForm extends StatefulWidget {
  const PantallaRecepcionForm({super.key, required this.repo});

  final RepositorioTaller repo;

  @override
  State<PantallaRecepcionForm> createState() => _PantallaRecepcionFormState();
}

class _PantallaRecepcionFormState extends State<PantallaRecepcionForm> {
  TipoCombustible? _tipo;
  final _galones = TextEditingController();
  final _costo = TextEditingController();
  final _proveedor = TextEditingController();
  final _nota = TextEditingController();
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
    _costo.dispose();
    _proveedor.dispose();
    _nota.dispose();
    super.dispose();
  }

  TanqueTipo? _tanqueDe(String tipo) {
    final datos = widget.repo.datosCombustible;
    if (datos == null) return null;
    for (final t in datos.tanque) {
      if (t.tipo == tipo) return t;
    }
    return null;
  }

  Future<void> _guardar() async {
    if (_tipo == null) return;
    if (_gal <= 0) {
      _avisar('Escribe la cantidad de galones recibidos (mayor que cero).');
      return;
    }
    if (_costoGal < 0) {
      _avisar('El costo por galón no puede ser negativo.');
      return;
    }
    final saldoActual = _tanqueDe(_tipo!.tipo)?.saldo;
    // Confirmación antes de guardar, con el resumen completo.
    final confirma = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Confirmar recepción?'),
        content: Text(
          'Combustible: ${_tipo!.etiqueta}\n'
          'Entran: $_gal galones\n'
          'Costo por galón: ${dinero(_costoGal)}\n'
          'TOTAL: ${dinero(_total)}'
          '${_proveedor.text.trim().isEmpty ? '' : '\nProveedor: ${_proveedor.text.trim()}'}'
          '${saldoActual != null ? '\nEl tanque quedará con ${galones(saldoActual + _gal)} galones de ${_tipo!.etiqueta}.' : ''}',
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
      await widget.repo.registrarRecepcion(
        tipo: _tipo!.tipo,
        galones: _gal,
        costoUnitario: _costoGal,
        proveedor: _proveedor.text,
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
    final datos = widget.repo.datosCombustible;
    if (datos == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Recibir combustible')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Tipo de combustible',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final t in datos.tipos)
                ChoiceChip(
                  label: Text(
                      '${t.etiqueta} · quedan ${galones(_tanqueDe(t.tipo)?.saldo ?? 0)} gal'),
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
                    labelText: 'Galones que entraron',
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
            controller: _proveedor,
            decoration: const InputDecoration(
              labelText: 'Proveedor (opcional)',
              hintText: 'Ej.: Distribuidora Caribe',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nota,
            decoration: const InputDecoration(
              labelText: 'Nota (opcional)',
              border: OutlineInputBorder(),
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
            onPressed: _guardando || _tipo == null ? null : _guardar,
            icon: const Icon(Icons.oil_barrel_outlined),
            label: Text(_guardando ? 'Guardando…' : 'Guardar recepción'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}
