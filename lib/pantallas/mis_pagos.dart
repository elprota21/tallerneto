import 'package:material_ui/material_ui.dart';

import '../datos/repositorio.dart';
import '../modelos.dart';
import 'comun.dart';
import 'detalle_trabajo.dart';

/// MIS PAGOS del mecánico (1.5.0): el detalle de su dinero del
/// mes con los datos que la app YA baja del servidor
/// (pr_datos_mecanico) — sin inventar estados que el sistema no
/// tiene: aquí no hay «pagado» ni comprobantes, porque el pago
/// lo procesa administración en el panel a partir de los
/// trabajos VALIDADOS. Lo que esta pantalla hace es enseñar el
/// cálculo completo, trabajo por trabajo:
///  - Destajo: cuánto lleva validado (eso es lo que cobra),
///    cuánto está en revisión y qué fue rechazado (no cuenta).
///  - Sueldo: su sueldo fijo y sus trabajos como productividad.
/// Tocar un trabajo abre su detalle.
class PantallaMisPagos extends StatelessWidget {
  const PantallaMisPagos({super.key, required this.repo});

  final RepositorioTaller repo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis pagos')),
      body: ListenableBuilder(
        listenable: repo,
        builder: (_, _) {
          final datos = repo.datosMecanico;
          if (datos == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _contenido(context, datos);
        },
      ),
    );
  }

  Widget _contenido(BuildContext context, DatosMecanico datos) {
    final cs = Theme.of(context).colorScheme;
    final u = datos.usuario;
    final ahora = DateTime.now();
    final mes =
        '${ahora.year.toString().padLeft(4, '0')}-${ahora.month.toString().padLeft(2, '0')}-01';
    final delMes =
        datos.trabajos.where((t) => t.fecha.compareTo(mes) >= 0).toList();
    final validados = delMes.where((t) => t.estado == 'validada').toList();
    final pendientes = delMes.where((t) => t.estado == 'pendiente').toList();
    final rechazados = delMes.where((t) => t.estado == 'rechazada').toList();

    String etiquetaVehiculo(String id) {
      for (final v in datos.vehiculos) {
        if (v.id == id) return v.etiqueta;
      }
      return 'Unidad';
    }

    Widget filaTrabajo(Trabajo t, {required bool conPrecio}) {
      return Card(
        child: ListTile(
          title: Text(t.tipoNombre),
          subtitle: Text(
              '${etiquetaVehiculo(t.vehiculoId)} · ${fechaCorta(t.fecha)}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (conPrecio)
                Text(dinero(t.precio),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              if (conPrecio) const SizedBox(width: 8),
              ChipEstadoTrabajo(estado: t.estado),
            ],
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  PantallaDetalleTrabajo(trabajo: t, datos: datos),
            ),
          ),
        ),
      );
    }

    Widget seccion(String titulo, List<Trabajo> lista,
        {required bool conPrecio, String? vacio}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$titulo (${lista.length})',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (lista.isEmpty && vacio != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(vacio),
              ),
            ),
          ...lista.map((t) => filaTrabajo(t, conPrecio: conPrecio)),
          const SizedBox(height: 20),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () => repo.recargarMecanico(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Este mes · ${datos.empresa.nombre}',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (u.esSueldo) ...[
            Card(
              color: cs.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tu sueldo',
                        style: TextStyle(color: cs.onPrimaryContainer)),
                    Text(
                      dinero(u.sueldoMonto ?? 0),
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimaryContainer,
                          ),
                    ),
                    Text(
                      'Salario fijo mensual. Tus trabajos no suman dinero: '
                      'cuentan como productividad.',
                      style: TextStyle(
                          fontSize: 13, color: cs.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TarjetaConteo(
                    etiqueta: 'Validados',
                    valor: '${validados.length}',
                    icono: Icons.check_circle_outline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TarjetaConteo(
                    etiqueta: 'En revisión',
                    valor: '${pendientes.length}',
                    icono: Icons.hourglass_top_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TarjetaConteo(
                    etiqueta: 'Rechazados',
                    valor: '${rechazados.length}',
                    icono: Icons.cancel_outlined,
                  ),
                ),
              ],
            ),
          ] else ...[
            Card(
              color: cs.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Validado: eso es lo que cobras',
                        style: TextStyle(color: cs.onPrimaryContainer)),
                    Text(
                      dinero(datos.totalValidadoMes),
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimaryContainer,
                          ),
                    ),
                    Text(
                      'La suma de tus trabajos validados de este mes, '
                      'a destajo.',
                      style: TextStyle(
                          fontSize: 13, color: cs.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _filaTotal('En revisión (pendiente de validar)',
                        dinero(datos.totalPendienteMes)),
                    const Divider(),
                    _filaTotal(
                        'Rechazados (no cuentan)',
                        rechazados.isEmpty
                            ? dinero(0)
                            : '${rechazados.length} trabajo'
                                '${rechazados.length == 1 ? '' : 's'}'),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          seccion('Trabajos validados', validados,
              conPrecio: !u.esSueldo,
              vacio: 'Todavía no tienes trabajos validados este mes.'),
          seccion('En revisión', pendientes,
              conPrecio: !u.esSueldo,
              vacio: 'Nada en revisión: administración va al día contigo.'),
          if (rechazados.isNotEmpty)
            seccion('Rechazados', rechazados, conPrecio: !u.esSueldo),
          Text(
            'El pago lo procesa administración desde el panel, con '
            'estos mismos trabajos validados. Si algo no cuadra, '
            'muéstrale esta pantalla.',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _filaTotal(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(etiqueta)),
          Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
