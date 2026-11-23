import 'package:material_ui/material_ui.dart';

import '../datos/repositorio.dart';
import '../modelos.dart';

import 'comun.dart';
import 'mis_pagos.dart';
import 'pedir_pieza.dart';

/// Inicio del mecánico (rediseño 1.5.0): encabezado con su
/// nombre, su rol y su empresa; su dinero según su modo de pago
/// (la tarjeta abre «Mis pagos», el detalle completo); los
/// conteos de SUS trabajos de este mes por estado real
/// (pendiente de validación / validada / rechazada), que llevan
/// a «Mis trabajos» con ese filtro puesto; las DOS acciones
/// principales en grande (REGISTRAR TRABAJO y VER MIS TRABAJOS);
/// sus trabajos de hoy; y SUS SOLICITUDES DE PIEZAS con el botón
/// «Pedir pieza» (administración las gestiona en el panel; aquí
/// ve si están pendientes, en pedido, recibidas o rechazadas
/// con el motivo).
///  - Destajo: «Llevo ganado RD$X» (validados del mes) y
///    «RD$Y en revisión» (pendientes).
///  - Sueldo: «Tu sueldo: RD$X» y el conteo de trabajos realizados;
///    los trabajos no le suman dinero.
class PantallaInicio extends StatelessWidget {
  const PantallaInicio({
    super.key,
    required this.repo,
    this.alRegistrar,
    this.alVerTrabajos,
  });

  final RepositorioTaller repo;

  /// Acción principal: ir a la pestaña «Registrar» (la pone la
  /// principal). Sin ella, el botón no se muestra.
  final VoidCallback? alRegistrar;

  /// Ir a «Mis trabajos» con un filtro de estado ya puesto
  /// ('pendiente' | 'validada' | 'rechazada' | 'todas').
  final void Function(String filtro)? alVerTrabajos;

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
    final mesIso = '${hoyIso.substring(0, 8)}01';
    final deHoy = datos.trabajos.where((t) => t.fecha == hoyIso).toList();
    final delMes =
        datos.trabajos.where((t) => t.fecha.compareTo(mesIso) >= 0).toList();
    final validadosMes = delMes.where((t) => t.estado == 'validada').length;
    final pendientesMes = delMes.where((t) => t.estado == 'pendiente').length;
    final rechazadosMes = delMes.where((t) => t.estado == 'rechazada').length;

    String etiquetaVehiculo(String id) {
      for (final v in datos.vehiculos) {
        if (v.id == id) return v.etiqueta;
      }
      return 'Vehículo';
    }

    void abrirMisPagos() {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PantallaMisPagos(repo: repo)),
      );
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
          Text(
            '${Usuario.etiquetaDe(u.rol)} · '
            '${u.esSueldo ? 'Sueldo fijo' : 'Pago a destajo'}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          if (u.esSueldo) ...[
            _TarjetaDinero(
              titulo: 'Tu sueldo',
              monto: dinero(u.sueldoMonto ?? 0),
              detalle: 'Salario fijo mensual. Tus trabajos cuentan como '
                  'productividad: llevas $validadosMes validados y '
                  '$pendientesMes en revisión este mes. '
                  'Toca para ver «Mis pagos».',
              icono: Icons.payments_outlined,
              alTocar: abrirMisPagos,
            ),
          ] else ...[
            _TarjetaDinero(
              titulo: 'Llevo ganado',
              monto: dinero(datos.totalValidadoMes),
              detalle: 'Trabajos validados de este mes (a destajo). '
                  'Toca para ver «Mis pagos».',
              icono: Icons.payments_outlined,
              alTocar: abrirMisPagos,
            ),
            const SizedBox(height: 12),
            _TarjetaDinero(
              titulo: 'En revisión',
              monto: dinero(datos.totalPendienteMes),
              detalle: 'Trabajos pendientes de validar en administración.',
              icono: Icons.hourglass_top_outlined,
              secundaria: true,
              alTocar: abrirMisPagos,
            ),
          ],
          const SizedBox(height: 16),
          // Conteos de MIS trabajos de este mes, por estado real.
          // Cada tarjeta lleva a «Mis trabajos» con su filtro.
          Row(
            children: [
              Expanded(
                child: TarjetaConteo(
                  etiqueta: 'En revisión',
                  valor: '$pendientesMes',
                  icono: Icons.hourglass_top_outlined,
                  alTocar: () => alVerTrabajos?.call('pendiente'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TarjetaConteo(
                  etiqueta: 'Validados',
                  valor: '$validadosMes',
                  icono: Icons.check_circle_outline,
                  alTocar: () => alVerTrabajos?.call('validada'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TarjetaConteo(
                  etiqueta: 'Rechazados',
                  valor: '$rechazadosMes',
                  icono: Icons.cancel_outlined,
                  alTocar: () => alVerTrabajos?.call('rechazada'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Las dos acciones principales, en grande.
          if (alRegistrar != null) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: alRegistrar,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('REGISTRAR TRABAJO'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (alVerTrabajos != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => alVerTrabajos!.call('todas'),
                icon: const Icon(Icons.assignment_outlined),
                label: const Text('VER MIS TRABAJOS'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
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
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(etiquetaVehiculo(t.vehiculoId)),
                    if (t.pendienteEnvio) ...[
                      const SizedBox(height: 4),
                      const ChipPendienteEnvio(),
                    ],
                  ],
                ),
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
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s.vehiculoId != null ? '${etiquetaVehiculo(s.vehiculoId!)} · ' : ''}'
                      '${fechaCorta(s.fecha)}'
                      '${s.esUrgente ? ' · URGENTE' : ''}'
                      '${s.estado == 'rechazada' && s.notaAdmin != null ? '\nMotivo: ${s.notaAdmin}' : ''}'
                      '${s.estado == 'recibida' && s.cantidadRecibida != null ? '\nEntraron ${s.cantidadRecibida} al inventario' : ''}',
                    ),
                    if (s.pendienteEnvio) ...[
                      const SizedBox(height: 4),
                      const ChipPendienteEnvio(),
                    ],
                  ],
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
    this.alTocar,
  });

  final String titulo;
  final String monto;
  final String detalle;
  final IconData icono;
  final bool secundaria;

  /// Al tocarla (abre «Mis pagos» con el detalle completo).
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: secundaria ? cs.surfaceContainerHighest : cs.primaryContainer,
      child: InkWell(
        onTap: alTocar,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icono,
                  size: 36,
                  color:
                      secundaria ? cs.onSurfaceVariant : cs.onPrimaryContainer),
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
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: secundaria
                                    ? null
                                    : cs.onPrimaryContainer,
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
              if (alTocar != null)
                Icon(Icons.chevron_right,
                    color: secundaria
                        ? cs.onSurfaceVariant
                        : cs.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
