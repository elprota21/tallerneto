import 'package:material_ui/material_ui.dart';

import '../datos/repositorio.dart';
import '../modelos.dart';
import 'comun.dart';

/// Interfaz del coordinador de lavado (rol `lavado`): la lista de
/// vehículos activos de la empresa para HOY. Tocar uno sin lavar lo
/// marca (con confirmación breve); tocar uno lavado permite
/// desmarcarlo. Un vehículo solo puede estar lavado una vez por
/// día. El reporte le llega solo a administración en el panel.
class PantallaLavado extends StatelessWidget {
  const PantallaLavado({super.key, required this.repo});

  final RepositorioTaller repo;

  Future<void> _tocar(BuildContext context, VehiculoLavado v) async {
    final lavada = v.lavadoHoy;
    final confirma = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(lavada ? 'Desmarcar lavado' : 'Marcar como lavada'),
        content: Text(lavada
            ? '¿Quitar el lavado de hoy de la ${v.vehiculo.etiqueta}? '
                'El cambio queda registrado con tu nombre y la hora.'
            : '¿La ${v.vehiculo.etiqueta} ya quedó lavada?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(lavada ? 'Desmarcar' : 'Sí, lavada'),
          ),
        ],
      ),
    );
    if (confirma != true) return;
    try {
      if (lavada) {
        await repo.desmarcarLavado(v.vehiculo.id);
      } else {
        await repo.marcarLavado(v.vehiculo.id);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final datos = repo.datosLavado;
    if (datos == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!datos.empresa.lavadoActivo) {
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
    return RefreshIndicator(
      onRefresh: () => repo.recargarLavado(),
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
                    'Lavadas hoy: ${datos.lavadas} de ${datos.total}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.onPrimaryContainer,
                        ),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: datos.total == 0 ? 0 : datos.lavadas / datos.total,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    datos.faltan.isEmpty
                        ? '¡Todas las unidades quedaron lavadas hoy! 🎉'
                        : 'Faltan: ${datos.faltan.map((v) => v.vehiculo.codigo).join(', ')}',
                    style: TextStyle(color: cs.onPrimaryContainer),
                  ),
                  Text(
                    '${datos.empresa.nombre} · ${fechaLarga(datos.fecha)}',
                    style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Toca una unidad para marcarla lavada (o desmarcarla).',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ...datos.vehiculos.map(
            (v) => Card(
              child: ListTile(
                leading: Icon(
                  v.lavadoHoy
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: v.lavadoHoy ? Colors.green : cs.onSurfaceVariant,
                  size: 30,
                ),
                title: Text(
                  '${v.vehiculo.codigo} · ${v.vehiculo.marca} ${v.vehiculo.modelo}',
                  style: TextStyle(
                    fontWeight:
                        v.lavadoHoy ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.lavadoHoy
                        ? 'Lavada a las ${horaCorta(v.marcadaEn)}'
                            '${v.marcadaPorNombre != null ? ' · por ${v.marcadaPorNombre}' : ''}'
                        : 'Placa ${v.vehiculo.placa} · sin lavar hoy'),
                    if (v.pendienteEnvio) ...[
                      const SizedBox(height: 4),
                      const ChipPendienteEnvio(),
                    ],
                  ],
                ),
                trailing: const Icon(Icons.touch_app_outlined),
                onTap: () => _tocar(context, v),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
