import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../datos/repositorio.dart';
import '../modelos.dart';
import '../servicios/actualizacion.dart';
import '../servicios/tema.dart';
import 'comun.dart';
import 'mis_pagos.dart';
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
        // Cambiar mi nombre: el nombre visible con el que me ven
        // administración y los compañeros; se confirma con mi PIN
        // actual (el servidor solo deja cambiar el nombre propio).
        Card(
          child: ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Cambiar mi nombre'),
            subtitle:
                const Text('El nombre que ven administración y tus compañeros.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) =>
                    _DialogoCambiarNombre(repo: repo, nombreActual: u.nombre),
              );
              if (ok == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tu nombre se cambió. ✅')),
                );
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        // Cambiar mi PIN: la app lo estrena en la 1.5.0 (la
        // función del servidor, pr_cambiar_pin, ya existía y la
        // usa el panel). Al cambiarlo, el servidor revoca las
        // sesiones: la app avisa y cierra la sesión para entrar
        // con el PIN nuevo.
        Card(
          child: ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: const Text('Cambiar mi PIN'),
            subtitle: const Text(
                'Tu clave de entrada de 4 a 6 dígitos. Al cambiarlo '
                'tendrás que entrar de nuevo.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => _DialogoCambiarPin(repo: repo),
              );
              if (ok == true && context.mounted) {
                await showDialog<void>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('PIN cambiado ✅'),
                    content: const Text(
                        'Por seguridad se cerró tu sesión. Entra de '
                        'nuevo con tu PIN nuevo.'),
                    actions: [
                      FilledButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('Entendido'),
                      ),
                    ],
                  ),
                );
                await repo.cerrarSesion();
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        // Mis pagos: solo el mecánico cobra por trabajos (a
        // destajo o como productividad de su sueldo).
        if (u.rolesApp.contains('mecanico'))
          Card(
            child: ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Mis pagos'),
              subtitle: const Text(
                  'El detalle de tu dinero de este mes, trabajo por trabajo.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PantallaMisPagos(repo: repo),
                ),
              ),
            ),
          ),
        if (u.rolesApp.contains('mecanico')) const SizedBox(height: 8),
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

/// Diálogo «Cambiar mi nombre»: nombre nuevo + PIN actual de
/// confirmación. Si el repositorio lo acepta, se cierra con true
/// y el Perfil ya muestra el nombre nuevo (la sesión se actualiza
/// y la principal redibuja).
class _DialogoCambiarNombre extends StatefulWidget {
  const _DialogoCambiarNombre({required this.repo, required this.nombreActual});

  final RepositorioTaller repo;
  final String nombreActual;

  @override
  State<_DialogoCambiarNombre> createState() => _DialogoCambiarNombreState();
}

class _DialogoCambiarNombreState extends State<_DialogoCambiarNombre> {
  late final TextEditingController _nombre =
      TextEditingController(text: widget.nombreActual);
  final TextEditingController _pin = TextEditingController();
  String? _error;
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.repo
          .cambiarNombre(pinActual: _pin.text, nombreNuevo: _nombre.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _guardando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar mi nombre'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nombre,
            decoration: const InputDecoration(labelText: 'Nombre nuevo'),
            textCapitalization: TextCapitalization.words,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pin,
            decoration: const InputDecoration(
                labelText: 'PIN actual (para confirmar que eres tú)'),
            keyboardType: TextInputType.number,
            obscureText: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _guardando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: Text(_guardando ? 'Guardando…' : 'Guardar'),
        ),
      ],
    );
  }
}

/// Diálogo «Cambiar mi PIN»: PIN actual + PIN nuevo dos veces.
/// Las validaciones de la app son las mismas del servidor
/// (pr_cambiar_pin): 4 a 6 dígitos y nunca 1234; el servidor
/// tiene la última palabra. Si el cambio se acepta, se cierra
/// con true y el Perfil avisa y cierra la sesión (el servidor
/// revoca las sesiones al cambiar el PIN).
class _DialogoCambiarPin extends StatefulWidget {
  const _DialogoCambiarPin({required this.repo});

  final RepositorioTaller repo;

  @override
  State<_DialogoCambiarPin> createState() => _DialogoCambiarPinState();
}

class _DialogoCambiarPinState extends State<_DialogoCambiarPin> {
  final TextEditingController _actual = TextEditingController();
  final TextEditingController _nuevo = TextEditingController();
  final TextEditingController _repetir = TextEditingController();
  String? _error;
  bool _guardando = false;

  @override
  void dispose() {
    _actual.dispose();
    _nuevo.dispose();
    _repetir.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    final nuevo = _nuevo.text.trim();
    // Validación local con los mensajes del servidor, para no
    // gastar el viaje si el PIN nuevo ya nace mal.
    if (!RegExp(r'^[0-9]{4,6}$').hasMatch(nuevo)) {
      setState(
          () => _error = 'El PIN nuevo debe tener de 4 a 6 dígitos');
      return;
    }
    if (nuevo == '1234') {
      setState(() => _error =
          'El PIN 1234 está prohibido por seguridad: elige otro PIN');
      return;
    }
    if (nuevo != _repetir.text.trim()) {
      setState(() => _error = 'El PIN nuevo no coincide al repetirlo');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.repo
          .cambiarPin(pinActual: _actual.text, pinNuevo: nuevo);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _guardando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar mi PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _actual,
            decoration:
                const InputDecoration(labelText: 'PIN actual'),
            keyboardType: TextInputType.number,
            obscureText: true,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nuevo,
            decoration: const InputDecoration(
                labelText: 'PIN nuevo (4 a 6 dígitos)'),
            keyboardType: TextInputType.number,
            obscureText: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _repetir,
            decoration:
                const InputDecoration(labelText: 'Repite el PIN nuevo'),
            keyboardType: TextInputType.number,
            obscureText: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _guardando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: Text(_guardando ? 'Guardando…' : 'Guardar'),
        ),
      ],
    );
  }
}
