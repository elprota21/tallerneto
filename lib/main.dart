import 'package:material_ui/material_ui.dart';

import 'datos/repositorio.dart';
import 'marca.dart';
import 'pantallas/entrada.dart';
import 'pantallas/principal.dart';
import 'servicios/colores.dart';
import 'servicios/tema.dart';

/// App «TallerNeto» — la del personal del taller:
///  - El MECÁNICO registra los trabajos que terminó (vehículo, tipo
///    con su precio, piezas usadas) y ve cuánto lleva ganado si cobra
///    a destajo, o su sueldo si cobra fijo. Administración valida o
///    rechaza cada trabajo en el panel; solo lo validado paga.
///  - El COORDINADOR DE LAVADO (si la empresa tiene el módulo activo)
///    marca las guaguas lavadas del día; el reporte le llega solo a
///    administración.
/// Tema M3 con MODO NOCHE/DÍA guardado en el teléfono, y
/// actualización automática dentro de la app desde la 1.0.0.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TemaApp.cargar();
  runApp(const AppTallerNeto());
}

class AppTallerNeto extends StatefulWidget {
  const AppTallerNeto({super.key});

  @override
  State<AppTallerNeto> createState() => _AppTallerNetoState();
}

class _AppTallerNetoState extends State<AppTallerNeto> {
  final RepositorioTaller _repo = crearRepositorio();
  bool _listo = false;

  @override
  void initState() {
    super.initState();
    _repo.restaurarSesion().whenComplete(() {
      if (mounted) setState(() => _listo = true);
    });
  }

  @override
  void dispose() {
    _repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: TemaApp.oscuro,
      builder: (_, oscuro, _) => MaterialApp(
        title: Marca.nombreApp,
        debugShowCheckedModeBanner: false,
        // Paleta de marca: la misma del panel (grafito + ámbar).
        theme: ColoresMarca.temaClaro(),
        darkTheme: ColoresMarca.temaOscuro(),
        themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
        home: AnimatedBuilder(
          animation: _repo,
          builder: (_, _) {
            if (!_listo) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (_repo.sesion == null) {
              return PantallaEntrada(repo: _repo);
            }
            return PantallaPrincipal(repo: _repo);
          },
        ),
      ),
    );
  }
}
