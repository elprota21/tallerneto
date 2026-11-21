import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../datos/repositorio.dart';
import '../servicios/actualizacion.dart';
import '../servicios/tema.dart';
import 'comun.dart';

/// Perfil: mis datos, mi modo de pago, MODO NOCHE/DÍA, buscar
/// actualización y cerrar sesión. Sirve igual para el mecánico y
/// para el coordinador de lavado.
class PantallaPerfil extends StatelessWidget {
  const PantallaPerfil({super.key, required this.repo});

  final RepositorioTaller repo;

  @override
  Widget build(BuildContext context) {
    final u = repo.sesion;
    if (u == null) return const SizedBox.shrink();
    final empresa = repo.datosMecanico?.empresa.nombre ??
        repo.datosLavado?.empresa.nombre ??
        repo.datosCombustible?.empresa.nombre ??
        '';
    final rolTexto = switch (u.rol) {
      'mecanico' => 'Mecánico',
      'lavado' => 'Coordinador de lavado',
      'combustible' => 'Despachador de combustible',
      _ => u.rol,
    };

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
        if (u.rol == 'mecanico')
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
