import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../datos/repositorio.dart';
import '../modelos.dart';
import '../servicios/actualizacion.dart';
import '../servicios/tema.dart';
import 'comun.dart';
import 'tutorial.dart';

/// Perfil: mis datos (con mis DOS roles si tengo adicional), mi
/// modo de pago, CAMBIAR DE FUNCIÓN si tengo dos roles con
/// pantalla, MODO NOCHE/DÍA, buscar actualización y cerrar sesión.
/// Sirve igual para el mecánico, el lavado y el combustible.
class PantallaPerfil extends StatelessWidget {
  const PantallaPerfil({super.key, required this.repo, this.alCambiarRol});

  final RepositorioTaller repo;

  /// La principal lo pasa para volver a la primera pestaña tras
  /// cambiar de función.
  final VoidCallback? alCambiarRol;

  @override
  Widget build(BuildContext context) {
    final u = repo.sesion;
    if (u == null) return const SizedBox.shrink();
    final empresa = repo.datosMecanico?.empresa.nombre ??
        repo.datosLavado?.empresa.nombre ??
        repo.datosCombustible?.empresa.nombre ??
        '';
    // Mis roles: el principal y, si lo hay, el adicional.
    final rolTexto = u.rolAdicional == null
        ? Usuario.etiquetaDe(u.rol)
        : '${Usuario.etiquetaDe(u.rol)} + ${Usuario.etiquetaDe(u.rolAdicional!)}';
    final vista = repo.rolEnPantalla ?? u.rol;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 36,
                child: Text(
                  u.nombre.isNotEmpty ? u.nombre[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 28),
                ),
              ),
              const SizedBox(height: 12),
              Text(u.nombre,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Text('${u.codigo} · $rolTexto'),
              Text(empresa),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Cambiar de función: solo si tengo DOS roles con pantalla.
        // (El adicional almacén no tiene pantalla en la app: ese
        // sombrero se ejerce en el panel, aquí no hay nada que
        // cambiar.)
        if (u.tieneDosRolesApp)
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.swap_horiz_outlined),
                  title: Text('Cambiar de función'),
                  subtitle: Text(
                      'Estás trabajando con un rol; toca el otro para cambiar.'),
                ),
                for (final r in u.rolesApp)
                  ListTile(
                    leading: Icon(r == vista
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked),
                    title: Text(Usuario.etiquetaDe(r)),
                    subtitle: Text(r == u.rol
                        ? 'Rol principal'
                        : 'Rol adicional'),
                    trailing: r == vista
                        ? const Chip(label: Text('Ahora'))
                        : null,
                    onTap: r == vista
                        ? null
                        : () {
                            repo.fijarRolActivo(r);
                            alCambiarRol?.call();
                          },
                  ),
              ],
            ),
          ),
        if (u.tieneDosRolesApp) const SizedBox(height: 8),
        if (u.rolesApp.contains('mecanico'))
          Card(
            child: ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: Text(u.esSueldo ? 'Cobras con sueldo fijo' : 'Cobras a destajo'),
              subtitle: Text(u.esSueldo
                  ? 'Tu sueldo: ${dinero(u.sueldoMonto ?? 0)} al mes. '
                      'Tus trabajos cuentan como productividad.'
                  : 'Te pagan la suma de tus trabajos validados. '
                      'El modo lo fija administración en el panel.'),
            ),
          ),
        const SizedBox(height: 8),
        // Modo noche/día: los mecánicos y el lavado también trabajan
        // con luz mala; la preferencia se guarda en el teléfono.
        ValueListenableBuilder<bool>(
          valueListenable: TemaApp.oscuro,
          builder: (_, oscuro, _) => Card(
            child: SwitchListTile(
              secondary: Icon(oscuro ? Icons.dark_mode : Icons.light_mode),
              title: const Text('Modo noche'),
              subtitle: const Text(
                  'Pantalla oscura para trabajar con poca luz.'),
              value: oscuro,
              onChanged: (v) => TemaApp.fijar(v),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Sincronización (cola de salida offline): lo guardado en
        // el teléfono que aún no ha salido, con su botón.
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(repo.pendientesEnvio > 0
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_done_outlined),
                title: Text(repo.pendientesEnvio > 0
                    ? '${repo.pendientesEnvio} registro${repo.pendientesEnvio == 1 ? '' : 's'} por enviar'
                    : 'Todo enviado'),
                subtitle: Text(repo.pendientesEnvio > 0
                    ? 'Están guardados en tu teléfono y salen solos '
                        'cuando haya conexión. Esto lo fuerza ahora.'
                    : 'Nada pendiente: el teléfono y el sistema van al día.'),
                trailing: repo.pendientesEnvio > 0
                    ? FilledButton.tonal(
                        onPressed: () async {
                          try {
                            final n = await repo.sincronizarAhora();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(n > 0
                                      ? 'Se enviaron $n registros. ✅'
                                      : 'Nada pendiente de envío.'),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            }
                          }
                        },
                        child: const Text('Sincronizar ahora'),
                      )
                    : null,
              ),
              if (repo.pendientesEnvio > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      repo.descripcionesPendientes.take(4).join('\n'),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              // Solo en la demo: probar el comportamiento sin
              // conexión sin tener que apagar el internet.
              if (repo.esDemo)
                SwitchListTile(
                  secondary: const Icon(Icons.wifi_off_outlined),
                  title: const Text('Simular sin conexión (demo)'),
                  subtitle: const Text(
                      'Lo que registres queda en el teléfono hasta apagar esto.'),
                  value: repo.sinConexionSimulada,
                  onChanged: (v) async {
                    await repo.fijarSinConexionSimulada(v);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(v
                              ? 'Sin conexión (simulado): todo queda guardado en el teléfono.'
                              : 'Conexión de vuelta: lo pendiente se envió.'),
                        ),
                      );
                    }
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.school_outlined),
            title: const Text('Ver tutorial'),
            subtitle: const Text(
                'El recorrido de bienvenida: qué haces tú en la app, paso a paso.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PantallaTutorial(rol: vista)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('Buscar actualización'),
            subtitle: const Text('La app se actualiza sola; esto lo fuerza.'),
            onTap: () => Actualizador.comprobar(
              context,
              forzar: true,
              alEstado: (msg) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(msg)));
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (_, snap) => Text(
            snap.hasData ? 'Versión ${snap.data!.version}' : '',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => repo.cerrarSesion(),
          icon: const Icon(Icons.logout),
          label: const Text('Cerrar sesión'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }
}
