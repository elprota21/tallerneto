import 'package:material_ui/material_ui.dart';

import '../datos/repositorio.dart';
import '../modelos.dart';
import 'comun.dart';
import 'despacho_form.dart';
import 'recepcion_form.dart';

/// Interfaz del despachador de combustible (rol `combustible`):
/// el estado del TANQUE por tipo (saldo con alerta de poco
/// combustible y días estimados), el botón «Recibir combustible»
/// para anotar las cargas que entran, y los despachos de HOY con
/// el total de galones del día. El panel de administración calcula
/// con esto el rendimiento por vehículo y ve la alerta del tanque.
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
      // Módulo extra no contratado: mensaje amable y comercial.
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            mensajeModuloExtra,
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
                      // Sin precios en la app, ni el total del día
                      // enseña dinero: solo los galones.
                      datos.empresa.preciosEnApp
                          ? 'Hoy: ${datos.totalGalonesHoy} galones · ${dinero(datos.totalCostoHoy)}'
                          : 'Hoy: ${datos.totalGalonesHoy} galones despachados',
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
            const SizedBox(height: 20),
            const Text(
              'Tanque de combustible',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...datos.tanque.map((t) => _TarjetaTanque(tanque: t)),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () async {
                  final ok = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => PantallaRecepcionForm(repo: repo),
                    ),
                  );
                  if (ok == true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Recepción registrada: el tanque se actualizó.')),
                    );
                  }
                },
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Recibir combustible'),
              ),
            ),
            const SizedBox(height: 20),
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
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Odómetro ${d.odometro.toStringAsFixed(0)} km · '
                          '${horaCorta(d.creadaEn)}'
                          '${d.despachadorNombre != null ? ' · ${d.despachadorNombre}' : ''}'),
                      if (d.pendienteEnvio) ...[
                        const SizedBox(height: 4),
                        const ChipPendienteEnvio(),
                      ],
                    ],
                  ),
                  trailing: datos.empresa.preciosEnApp
                      ? Text(dinero(d.total),
                          style: const TextStyle(fontWeight: FontWeight.bold))
                      : null,
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

/// Tarjeta del tanque de un tipo: «Diésel: quedan X gal» y, si
/// la empresa fijó la capacidad, «de N gal · P%» (el nivel real).
/// En alerta (saldo ≤ umbral) se pinta de error y dice «Poco
/// combustible», para que el despachador avise a administración
/// y pidan la recarga a tiempo.
class _TarjetaTanque extends StatelessWidget {
  const _TarjetaTanque({required this.tanque});

  final TanqueTipo tanque;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = tanque;
    return Card(
      color: t.alerta ? cs.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              t.alerta ? Icons.warning_amber_rounded : Icons.oil_barrel_outlined,
              color: t.alerta ? cs.onErrorContainer : cs.primary,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${t.etiqueta}: quedan ${galones(t.saldo)} gal',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: t.alerta ? cs.onErrorContainer : null,
                    ),
                  ),
                  if (t.capacidad != null)
                    Text(
                      'de ${galones(t.capacidad!)} gal'
                      '${t.porcentaje != null ? ' · ${t.porcentaje!.toStringAsFixed(1)}%' : ''}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: t.alerta ? cs.onErrorContainer : cs.onSurfaceVariant,
                      ),
                    ),
                  Text(
                    t.alerta
                        ? 'Poco combustible'
                            '${t.diasEstimados != null ? ' · alcanza para ~${galones(t.diasEstimados!)} días' : ''}'
                            ' — avisa a administración'
                        : t.diasEstimados != null
                            ? 'Alcanza para ~${galones(t.diasEstimados!)} días'
                            : 'Sin consumo reciente',
                    style: TextStyle(
                      color: t.alerta ? cs.onErrorContainer : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
