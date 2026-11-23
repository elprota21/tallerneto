import 'package:material_ui/material_ui.dart';

import '../modelos.dart';
import 'comun.dart';

/// Detalle de UN trabajo mío (desde «Mis trabajos»): la unidad,
/// el estado, la descripción que registré, las piezas que usé
/// (con sus cantidades) y, si administración lo rechazó, el
/// motivo. Todo sale de los datos que la app ya baja del
/// servidor: nada se edita aquí — un trabajo registrado solo lo
/// mueve administración desde el panel.
class PantallaDetalleTrabajo extends StatelessWidget {
  const PantallaDetalleTrabajo({
    super.key,
    required this.trabajo,
    required this.datos,
  });

  final Trabajo trabajo;
  final DatosMecanico datos;

  @override
  Widget build(BuildContext context) {
    final t = trabajo;
    final cs = Theme.of(context).colorScheme;

    String etiquetaVehiculo(String id) {
      for (final v in datos.vehiculos) {
        if (v.id == id) return v.etiqueta;
      }
      return 'Unidad';
    }

    String nombrePieza(String id) {
      for (final p in datos.piezas) {
        if (p.id == id) return p.nombre;
      }
      return 'Pieza';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del trabajo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  t.tipoNombre,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              ChipEstadoTrabajo(estado: t.estado),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${etiquetaVehiculo(t.vehiculoId)} · ${fechaLarga(t.fecha)}',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          if (t.pendienteEnvio) ...[
            const SizedBox(height: 8),
            const ChipPendienteEnvio(),
          ],
          const SizedBox(height: 16),
          if (!datos.usuario.esSueldo)
            Card(
              child: ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Mano de obra de este trabajo'),
                subtitle: Text(switch (t.estado) {
                  'validada' => 'Ya cuenta para tu pago.',
                  'rechazada' => 'Rechazado: no cuenta para tu pago.',
                  _ => 'Cuenta para tu pago cuando administración lo valide.',
                }),
                trailing: Text(
                  dinero(t.precio),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          if (!datos.usuario.esSueldo) const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Descripción',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(t.descripcion?.trim().isNotEmpty == true
                      ? t.descripcion!.trim()
                      : 'Sin descripción.'),
                  const SizedBox(height: 16),
                  const Text('Piezas usadas',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  if (t.piezas.isEmpty)
                    const Text('No usaste piezas en este trabajo.')
                  else
                    ...t.piezas.map(
                      (p) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.settings_outlined, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(nombrePieza(p.piezaId))),
                            Text('× ${p.cantidad}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  if (t.piezas.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Se descuentan del inventario cuando administración '
                      'valida el trabajo.',
                      style:
                          TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (t.estado == 'rechazada' && t.notaAdmin != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Motivo del rechazo: ${t.notaAdmin}',
                style: TextStyle(color: cs.onErrorContainer),
              ),
            ),
          ],
          if (t.estado == 'pendiente') ...[
            const SizedBox(height: 12),
            Text(
              'Este trabajo está en revisión: administración lo valida '
              'o lo rechaza desde el panel.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
