import 'package:material_ui/material_ui.dart';

import '../datos/repositorio.dart';

import 'comun.dart';
import 'pedir_pieza.dart';

/// Inicio del mecánico: saludo, su dinero según su modo de pago,
/// sus trabajos de hoy con su estado, y SUS SOLICITUDES DE PIEZAS
/// con el botón «Pedir pieza» (administración las gestiona en el
/// panel; aquí ve si están pendientes, en pedido, recibidas o
/// rechazadas con el motivo).
///  - Destajo: «Llevo ganado RD$X» (validados del mes) y
///    «RD$Y en revisión» (pendientes).
///  - Sueldo: «Tu sueldo: RD$X» y el conteo de trabajos realizados;
///    los trabajos no le suman dinero.
class PantallaInicio extends StatelessWidget {
  const PantallaInicio({super.key, required this.repo});

  final RepositorioTaller repo;

  @override
  Widget build(BuildContext context) {
    final datos = repo.datosMecanico;
    if (datos == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final u = datos.usuario;
    final hoy = DateTime.now();
    final hoyIso =
        '${hoy.year.toString().padLeft(4, '0')}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';
    final deHoy = datos.trabajos.where((t) => t.fecha == hoyIso).toList();
    final validadosMes =
        datos.trabajos.where((t) => t.estado == 'validada').length;
    final pendientesMes =
        datos.trabajos.where((t) => t.estado == 'pendiente').length;

    String etiquetaVehiculo(String id) {
      for (final v in datos.vehiculos) {
        if (v.id == id) return v.etiqueta;
      }
      return 'Vehículo';
    }

    return RefreshIndicator(
      onRefresh: () => repo.recargarMecanico(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${saludo()}, ${u.nombre.split(' ').first}',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            '${datos.empresa.nombre} · ${fechaLarga(hoyIso)}',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (u.esSueldo) ...[
            _TarjetaDinero(
              titulo: 'Tu sueldo',
              monto: dinero(u.sueldoMonto ?? 0),
              detalle: 'Salario fijo mensual. Tus trabajos cuentan como '
                  'productividad: llevas $validadosMes validados y '
                  '$pendientesMes en revisión este período.',
              icono: Icons.payments_outlined,
            ),
          ] else ...[
            _TarjetaDinero(
              titulo: 'Llevo ganado',
              monto: dinero(datos.totalValidadoMes),
              detalle: 'Trabajos validados de este mes (a destajo).',
              icono: Icons.payments_outlined,
            ),
            const SizedBox(height: 12),
            _TarjetaDinero(
              titulo: 'En revisión',
              monto: dinero(datos.totalPendienteMes),
              detalle: 'Trabajos pendientes de validar en administración.',
              icono: Icons.hourglass_top_outlined,
              secundaria: true,
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Mis trabajos de hoy (${deHoy.length})',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (deHoy.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'Hoy todavía no registras trabajos. Cuando termines uno, '
                    'anótalo en la pestaña «Registrar».'),
              ),
            ),
          ...deHoy.map(
            (t) => Card(
              child: ListTile(
                title: Text(t.tipoNombre),
                subtitle: Text(etiquetaVehiculo(t.vehiculoId)),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ChipEstadoTrabajo(estado: t.estado),
                    if (!u.esSueldo) ...[
                      const SizedBox(height: 4),
                      Text(dinero(t.precio),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Mis solicitudes de piezas (${datos.solicitudes.length})',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () async {
                final ok = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => PantallaPedirPieza(repo: repo),
                  ),
                );
                if (ok == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Solicitud enviada: administración la revisa en el panel.')),
                  );
                }
              },
              icon: const Icon(Icons.add_shopping_cart_outlined),
              label: const Text('Pedir pieza'),
            ),
          ),
          const SizedBox(height: 8),
          if (datos.solicitudes.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'No has pedido piezas. Si una pieza no está en stock, '
                    'pídela aquí y administración la encarga.'),
              ),
            ),
          ...datos.solicitudes.map(
            (s) => Card(
              child: ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text('${s.nombrePieza} × ${s.cantidad}'),
                subtitle: Text(
                  '${s.vehiculoId != null ? '${etiquetaVehiculo(s.vehiculoId!)} · ' : ''}'
                  '${fechaCorta(s.fecha)}'
                  '${s.esUrgente ? ' · URGENTE' : ''}'
                  '${s.estado == 'rechazada' && s.notaAdmin != null ? '\nMotivo: ${s.notaAdmin}' : ''}'
                  '${s.estado == 'recibida' && s.cantidadRecibida != null ? '\nEntraron ${s.cantidadRecibida} al inventario' : ''}',
                ),
                trailing: ChipEstadoSolicitud(estado: s.estado),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaDinero extends StatelessWidget {
  const _TarjetaDinero({
    required this.titulo,
    required this.monto,
    required this.detalle,
    required this.icono,
    this.secundaria = false,
  });

  final String titulo;
  final String monto;
  final String detalle;
  final IconData icono;
  final bool secundaria;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: secundaria ? cs.surfaceContainerHighest : cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icono,
                size: 36,
                color: secundaria ? cs.onSurfaceVariant : cs.onPrimaryContainer),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: TextStyle(
                          color: secundaria
                              ? cs.onSurfaceVariant
                              : cs.onPrimaryContainer)),
                  Text(
                    monto,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: secundaria ? null : cs.onPrimaryContainer,
                        ),
                  ),
                  Text(detalle,
                      style: TextStyle(
                          fontSize: 13,
                          color: secundaria
                              ? cs.onSurfaceVariant
                              : cs.onPrimaryContainer)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
