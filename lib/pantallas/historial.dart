import 'package:material_ui/material_ui.dart';

import '../datos/repositorio.dart';
import 'comun.dart';

/// Historial del mecánico: sus trabajos con filtro por estado. Si un
/// trabajo fue rechazado, se muestra el motivo que escribió
/// administración.
class PantallaHistorial extends StatefulWidget {
  const PantallaHistorial({super.key, required this.repo});

  final RepositorioTaller repo;

  @override
  State<PantallaHistorial> createState() => _PantallaHistorialState();
}

class _PantallaHistorialState extends State<PantallaHistorial> {
  String _filtro = 'todas';

  static const _opciones = <(String, String)>[
    ('todas', 'Todas'),
    ('pendiente', 'Pendientes'),
    ('validada', 'Validadas'),
    ('rechazada', 'Rechazadas'),
  ];

  @override
  Widget build(BuildContext context) {
    final datos = widget.repo.datosMecanico;
    if (datos == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final trabajos = datos.trabajos
        .where((t) => _filtro == 'todas' || t.estado == _filtro)
        .toList();

    String etiquetaVehiculo(String id) {
      for (final v in datos.vehiculos) {
        if (v.id == id) return v.etiqueta;
      }
      return 'Vehículo';
    }

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              for (final (valor, etiqueta) in _opciones) ...[
                ChoiceChip(
                  label: Text(etiqueta),
                  selected: _filtro == valor,
                  onSelected: (_) => setState(() => _filtro = valor),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => widget.repo.recargarMecanico(),
            child: trabajos.isEmpty
                ? ListView(
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                            'No tienes trabajos en este grupo todavía.'),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: trabajos.length,
                    itemBuilder: (_, i) {
                      final t = trabajos[i];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(t.tipoNombre,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15)),
                                  ),
                                  ChipEstadoTrabajo(estado: t.estado),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(etiquetaVehiculo(t.vehiculoId)),
                              Text(fechaCorta(t.fecha)),
                              if (t.descripcion != null) ...[
                                const SizedBox(height: 4),
                                Text(t.descripcion!),
                              ],
                              if (!datos.usuario.esSueldo &&
                                  t.estado == 'validada') ...[
                                const SizedBox(height: 4),
                                Text(dinero(t.precio),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ],
                              if (t.estado == 'rechazada' &&
                                  t.notaAdmin != null) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .errorContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Motivo del rechazo: ${t.notaAdmin}',
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onErrorContainer),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
