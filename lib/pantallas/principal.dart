import 'package:material_ui/material_ui.dart';

import '../datos/repositorio.dart';
import '../marca.dart';
import '../modelos.dart';
import '../servicios/actualizacion.dart';
import 'combustible.dart';
import 'historial.dart';
import 'inicio.dart';
import 'inventario_unidad.dart';
import 'lavado.dart';
import 'perfil.dart';
import 'registrar.dart';
import 'tutorial.dart';

/// Pantalla principal: las funciones dependen del ROL EN PANTALLA
/// de quien entró (su rol activo: el principal, o el adicional si
/// lo eligió — un usuario puede tener rol principal + adicional).
///  - Mecánico: 5 pestañas — Inicio, Registrar, Mis trabajos,
///    Inventario (por unidad), Perfil.
///  - Lavado: 2 pestañas — Lavado, Perfil (la interfaz de lavado en
///    vez de la de mecánico, en la MISMA app); 3 si el panel lo
///    autorizó a pasar el inventario por unidad (+ Inventario).
///  - Combustible: 2 pestañas — Combustible, Perfil (ídem, con la
///    misma regla del inventario).
/// Si tiene DOS roles con pantalla y aún no eligió, primero sale
/// el selector [PantallaElegirRol]; el cambio también vive en el
/// Perfil. Si el adicional es almacén (sin pantalla), entra
/// directo con su rol de app.
/// Al abrir se comprueba si hay actualización (regla de Miguel).
class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key, required this.repo});

  final RepositorioTaller repo;

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  int _indice = 0;
  bool _tutorialOfrecido = false;

  /// Filtro con el que «Mis trabajos» debe abrir cuando el
  /// Inicio (o el registro recién hecho) lleva hasta ahí. La
  /// llave fuerza una lista nueva con ese filtro puesto.
  String _filtroTrabajos = 'todas';
  int _llaveTrabajos = 0;

  /// Ir a «Mis trabajos» con un filtro de estado ya puesto.
  void _irAMisTrabajos(String filtro) {
    setState(() {
      _filtroTrabajos = filtro;
      _llaveTrabajos++;
      _indice = 2;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Actualizador.comprobar(context);
    });
    widget.repo.addListener(_quizasOfrecerTutorial);
    _quizasOfrecerTutorial();
  }

  @override
  void dispose() {
    widget.repo.removeListener(_quizasOfrecerTutorial);
    super.dispose();
  }

  /// MODO TUTORIAL: la primera vez que el usuario entra (y su
  /// empresa lo tiene activado), se le ofrece el recorrido de
  /// bienvenida de SU función. Se marca visto al cerrarlo; desde
  /// el Perfil puede repetirlo cuando quiera.
  Future<void> _quizasOfrecerTutorial() async {
    if (_tutorialOfrecido || !mounted) return;
    final repo = widget.repo;
    final u = repo.sesion;
    if (u == null) return;
    // Con dos funciones, primero elige con cuál trabaja.
    if (u.tieneDosRolesApp && repo.rolActivo == null) return;
    _tutorialOfrecido = true;
    final activo = repo.datosMecanico?.empresa.tutorialActivo ??
        repo.datosLavado?.empresa.tutorialActivo ??
        repo.datosCombustible?.empresa.tutorialActivo ??
        true;
    if (!activo) return;
    if (await TutorialApp.yaVisto(u.id)) return;
    if (!mounted) return;
    final vista = repo.rolEnPantalla ?? u.rol;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PantallaTutorial(rol: vista)),
    );
    await TutorialApp.marcarVisto(u.id);
  }

  /// Botón de la barra superior con el contador de la cola de
  /// salida: solo aparece si hay registros por enviar; al
  /// tocarlo, sincroniza.
  Widget _botonPendientes() {
    final n = widget.repo.pendientesEnvio;
    if (n == 0) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Registros por enviar: toca para sincronizar ahora',
      onPressed: () async {
        try {
          final enviados = await widget.repo.sincronizarAhora();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(enviados > 0
                    ? 'Se enviaron $enviados registros. ✅'
                    : 'Nada pendiente de envío.'),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(e.toString())));
          }
        }
      },
      icon: Badge(
        label: Text('$n'),
        child: const Icon(Icons.cloud_upload_outlined),
      ),
    );
  }

  List<Widget> get _acciones => [
        ListenableBuilder(
          listenable: widget.repo,
          builder: (_, _) => _botonPendientes(),
        ),
      ];

  /// Al cambiar de función en el Perfil, se vuelve a la primera
  /// pestaña del rol nuevo.
  void _alCambiarRol() => setState(() => _indice = 0);

  @override
  Widget build(BuildContext context) {
    final u = widget.repo.sesion;
    if (u == null) return const SizedBox.shrink();

    // Dos roles con pantalla y ninguno elegido todavía: a elegir.
    if (u.tieneDosRolesApp && widget.repo.rolActivo == null) {
      return PantallaElegirRol(repo: widget.repo);
    }

    final vista = widget.repo.rolEnPantalla ?? u.rol;

    if (vista == 'lavado') {
      // El inventario por unidad se suma como pestaña SOLO si el
      // panel autorizó a este usuario a pasarlo (bandera del
      // servidor); si no, la vista queda como siempre.
      final conInventario = u.puedePasarInventario;
      final paginas = <Widget>[
        PantallaLavado(repo: widget.repo),
        if (conInventario) PantallaInventarioUnidad(repo: widget.repo),
        PantallaPerfil(repo: widget.repo, alCambiarRol: _alCambiarRol),
      ];
      final indice = _indice < paginas.length ? _indice : paginas.length - 1;
      return Scaffold(
        appBar: AppBar(
          title: const Text('${Marca.nombreApp} · Lavado'),
          actions: _acciones,
        ),
        body: ListenableBuilder(
          listenable: widget.repo,
          builder: (_, _) => paginas[indice],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: indice,
          onDestinationSelected: (i) => setState(() => _indice = i),
          destinations: [
            const NavigationDestination(
                icon: Icon(Icons.local_car_wash_outlined),
                selectedIcon: Icon(Icons.local_car_wash),
                label: 'Lavado'),
            if (conInventario)
              const NavigationDestination(
                  icon: Icon(Icons.fact_check_outlined),
                  selectedIcon: Icon(Icons.fact_check),
                  label: 'Inventario'),
            const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Perfil'),
          ],
        ),
      );
    }

    if (vista == 'combustible') {
      // Ídem lavado: pestaña de inventario solo si está autorizado.
      final conInventario = u.puedePasarInventario;
      final paginas = <Widget>[
        PantallaCombustible(repo: widget.repo),
        if (conInventario) PantallaInventarioUnidad(repo: widget.repo),
        PantallaPerfil(repo: widget.repo, alCambiarRol: _alCambiarRol),
      ];
      final indice = _indice < paginas.length ? _indice : paginas.length - 1;
      return Scaffold(
        appBar: AppBar(
          title: const Text('${Marca.nombreApp} · Combustible'),
          actions: _acciones,
        ),
        body: ListenableBuilder(
          listenable: widget.repo,
          builder: (_, _) => paginas[indice],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: indice,
          onDestinationSelected: (i) => setState(() => _indice = i),
          destinations: [
            const NavigationDestination(
                icon: Icon(Icons.local_gas_station_outlined),
                selectedIcon: Icon(Icons.local_gas_station),
                label: 'Combustible'),
            if (conInventario)
              const NavigationDestination(
                  icon: Icon(Icons.fact_check_outlined),
                  selectedIcon: Icon(Icons.fact_check),
                  label: 'Inventario'),
            const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Perfil'),
          ],
        ),
      );
    }

    final pantallas = [
      PantallaInicio(
        repo: widget.repo,
        alRegistrar: () => setState(() => _indice = 1),
        alVerTrabajos: _irAMisTrabajos,
      ),
      PantallaRegistrar(
        repo: widget.repo,
        alTerminar: () {
          // El trabajo recién registrado nace pendiente: se
          // aterriza en «Mis trabajos» filtrado a pendientes,
          // para verlo ahí mismo con su sello.
          _irAMisTrabajos('pendiente');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Trabajo registrado. Queda pendiente de validar en administración.'),
            ),
          );
        },
      ),
      PantallaMisTrabajos(
        key: ValueKey('trabajos-$_llaveTrabajos'),
        repo: widget.repo,
        filtroInicial: _filtroTrabajos,
      ),
      PantallaInventarioUnidad(repo: widget.repo),
      PantallaPerfil(repo: widget.repo, alCambiarRol: _alCambiarRol),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text(Marca.nombreApp), actions: _acciones),
      body: ListenableBuilder(
        listenable: widget.repo,
        builder: (_, _) => IndexedStack(index: _indice, children: pantallas),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: (i) => setState(() => _indice = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Inicio'),
          NavigationDestination(
              icon: Icon(Icons.add_circle_outline),
              selectedIcon: Icon(Icons.add_circle),
              label: 'Registrar'),
          NavigationDestination(
              icon: Icon(Icons.assignment_outlined),
              selectedIcon: Icon(Icons.assignment),
              label: 'Mis trabajos'),
          NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              selectedIcon: Icon(Icons.fact_check),
              label: 'Inventario'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Perfil'),
        ],
      ),
    );
  }
}

/// Selector de función al entrar: solo aparece cuando el usuario
/// tiene DOS roles con pantalla en la app (principal + adicional).
/// Elige uno y la app entera trabaja con ese rol; se puede cambiar
/// cuando quiera desde el Perfil («Cambiar de función»).
class PantallaElegirRol extends StatelessWidget {
  const PantallaElegirRol({super.key, required this.repo});

  final RepositorioTaller repo;

  static IconData _iconoDe(String rol) => switch (rol) {
        'mecanico' => Icons.build_outlined,
        'lavado' => Icons.local_car_wash_outlined,
        'combustible' => Icons.local_gas_station_outlined,
        _ => Icons.badge_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final u = repo.sesion;
    if (u == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text(Marca.nombreApp)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Hola, ${u.nombre}',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Tienes dos funciones en el taller. ¿Con cuál quieres trabajar ahora?',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            for (final rol in u.rolesApp) ...[
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  leading: Icon(_iconoDe(rol), size: 32),
                  title: Text(
                    Usuario.etiquetaDe(rol),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(rol == u.rol
                      ? 'Tu rol principal'
                      : 'Tu rol adicional'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => repo.fijarRolActivo(rol),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            Text(
              'Puedes cambiar de función cuando quieras desde tu Perfil.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
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
        ),
      ),
    );
  }
}
