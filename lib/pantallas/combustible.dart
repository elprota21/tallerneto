import 'package:material_ui/material_ui.dart';

import '../datos/repositorio.dart';
import 'comun.dart';
import 'despacho_form.dart';

/// Interfaz del despachador de combustible (rol `combustible`):
/// los despachos de HOY y el total de galones del día, con el botón
/// para registrar un despacho nuevo. El panel de administración
/// calcula con esto el rendimiento por vehículo.
class PantallaCombustible extends StatelessWidget {
  const PantallaCombustible({super.key, required this.repo});

  final RepositorioTaller repo;

  @override
  Widget build(BuildContext context) {
    final datos = repo.datosCombustible;
    if (datos == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!datos.empresa.combustibleActivo) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'El módulo de combustible no está activo en tu empresa. '
            'Es una función adicional: la activa administración con TallerNeto.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => repo.recargarCombustible(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: cs.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hoy: ${datos.totalGalonesHoy} galones · ${dinero(datos.totalCostoHoy)}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimaryContainer,
                          ),
                    ),
                    Text(
                      '${datos.despachosHoy.length} despachos · '
                      '${datos.empresa.nombre} · ${fechaLarga(datos.fecha)}',
                      style: TextStyle(color: cs.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Despachos de hoy',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (datos.despachosHoy.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Hoy todavía no hay despachos registrados.'),
                ),
              ),
            ...datos.despachosHoy.map(
              (d) => Card(
                child: ListTile(
                  leading: const Icon(Icons.local_gas_station_outlined),
                  title: Text(
                      '${d.vehiculoCodigo} · ${d.galones} gal de ${d.tipoEtiqueta}'),
                  subtitle: Text(
                      'Odómetro ${d.odometro.toStringAsFixed(0)} km · '
                      '${horaCorta(d.creadaEn)}'
                      '${d.despachadorNombre != null ? ' · ${d.despachadorNombre}' : ''}'),
                  trailing: Text(dinero(d.total),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => PantallaDespachoForm(repo: repo),
            ),
          );
          if (ok == true && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Despacho registrado.')),
            );
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Registrar despacho'),
      ),
    );
  }
}
