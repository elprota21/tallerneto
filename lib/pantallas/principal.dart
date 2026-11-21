import 'package:material_ui/material_ui.dart';

import '../datos/repositorio.dart';
import '../marca.dart';
import '../servicios/actualizacion.dart';
import 'combustible.dart';
import 'historial.dart';
import 'inicio.dart';
import 'lavado.dart';
import 'perfil.dart';
import 'registrar.dart';

/// Pantalla principal: las funciones dependen del ROL de quien entró.
///  - Mecánico: 4 pestañas — Inicio, Registrar, Historial, Perfil.
///  - Lavado: 2 pestañas — Lavado, Perfil (la interfaz de lavado en
///    vez de la de mecánico, en la MISMA app).
///  - Combustible: 2 pestañas — Combustible, Perfil (ídem).
/// Al abrir se comprueba si hay actualización (regla de Miguel).
class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key, required this.repo});

  final RepositorioTaller repo;

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  int _indice = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Actualizador.comprobar(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.repo.sesion;
    if (u == null) return const SizedBox.shrink();

    if (u.esLavado) {
      return Scaffold(
        appBar: AppBar(title: const Text('${Marca.nombreApp} · Lavado')),
        body: ListenableBuilder(
          listenable: widget.repo,
          builder: (_, _) => _indice == 0
              ? PantallaLavado(repo: widget.repo)
              : PantallaPerfil(repo: widget.repo),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _indice,
          onDestinationSelected: (i) => setState(() => _indice = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.local_car_wash_outlined),
                selectedIcon: Icon(Icons.local_car_wash),
                label: 'Lavado'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Perfil'),
          ],
        ),
      );
    }

    if (u.esCombustible) {
      return Scaffold(
        appBar: AppBar(title: const Text('${Marca.nombreApp} · Combustible')),
        body: ListenableBuilder(
          listenable: widget.repo,
          builder: (_, _) => _indice == 0
              ? PantallaCombustible(repo: widget.repo)
              : PantallaPerfil(repo: widget.repo),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _indice,
          onDestinationSelected: (i) => setState(() => _indice = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.local_gas_station_outlined),
                selectedIcon: Icon(Icons.local_gas_station),
                label: 'Combustible'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Perfil'),
          ],
        ),
      );
    }

    final pantallas = [
      PantallaInicio(repo: widget.repo),
      PantallaRegistrar(
        repo: widget.repo,
        alTerminar: () {
          setState(() => _indice = 2);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Trabajo registrado. Queda pendiente de validar en administración.'),
            ),
          );
        },
      ),
      PantallaHistorial(repo: widget.repo),
      PantallaPerfil(repo: widget.repo),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text(Marca.nombreApp)),
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
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'Historial'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Perfil'),
        ],
      ),
    );
  }
}
