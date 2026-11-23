import 'package:material_ui/material_ui.dart';

import '../datos/repositorio.dart';
import '../modelos.dart';
import 'comun.dart';
import 'despacho_form.dart';
import 'recepcion_form.dart';

/// Interfaz del despachador de combustible (rol `combustible`):
/// el estado del TANQUE por tipo (saldo con alerta de poco
/// combustible y días estimados) y el total de galones del día.
/// Abajo, juntos en la barra inferior (orden de Miguel,
/// 2026-11-21, para que la pantalla no tenga reguero): «Recibir
/// combustible» (las cargas que entran) y «Registrar despacho»
/// (lo que sale). «Despachado hoy» va TAMBIÉN abajo, sobre los
/// botones, recogido: al tocarlo la lista se despliega en el
/// medio de la pantalla. El panel de
/// administración calcula con esto el rendimiento por vehículo
/// y ve la alerta del tanque.
class PantallaCombustible extends StatefulWidget {
  const PantallaCombustible({super.key, required this.repo});

  final RepositorioTaller repo;

  @override
  State<PantallaCombustible> createState() => _PantallaCombustibleState();
}

class _PantallaCombustibleState extends State<PantallaCombustible> {
  /// «Despachado hoy» nace recogido: se despliega al tocarlo.
  bool _verDespachos = false;

  RepositorioTaller get repo => widget.repo;

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
      body: Column(
        children: [
          // FIJO ARRIBA (orden de Miguel, 2026-11-21): el resumen
          // del día y el TANQUE no se mueven de ahí — se ve cuánto
          // queda y para cuántos días alcanza. Cuando la empresa
          // active más tipos (gasolina, GLP), sus tarjetas se
          // colocan en esta misma zona, debajo de la anterior.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // Encabezado por rol (1.5.0): quién soy y mi función,
            // igual que el Inicio del mecánico.
            Text(
              '${saludo()}, ${datos.usuario.nombre.split(' ').first}',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              'Despachador de combustible',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 12),
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
              ],
            ),
          ),
          // Zona del medio: la lista de despachos SOLO aparece
          // cuando «Despachado hoy» está desplegado — su botón
          // vive ABAJO, junto a los demás (corrección de Miguel,
          // 2026-11-21). Recogido, la pantalla queda limpia.
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => repo.recargarCombustible(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_verDespachos) ...[
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
            ],
            const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
      // Abajo, juntos TODOS (corrección de Miguel, 2026-11-21):
      // «Despachado hoy» sobre la fila de «Recibir combustible» y
      // «Registrar despacho», sin reguero en el cuerpo de la
      // pantalla. Los dos botones van rellenos en el ámbar de la
      // marca: que el despachador encuentre «Registrar despacho»
      // sin buscar, igual de destacado que «Recibir combustible»
      // (el tema ya pinta todo FilledButton con el ámbar oscuro
      // de la marca; ver servicios/colores.dart).
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.local_gas_station_outlined),
                  title: Text(
                    'Despachado hoy · ${datos.despachosHoy.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: Icon(_verDespachos
                      ? Icons.expand_more
                      : Icons.expand_less),
                  onTap: () =>
                      setState(() => _verDespachos = !_verDespachos),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    final ok = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => PantallaRecepcionForm(repo: repo),
                      ),
                    );
                    if (ok == true && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Recepción registrada: el tanque se actualizó.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Recibir combustible'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
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
              ),
                ],
              ),
            ],
          ),
        ),
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
