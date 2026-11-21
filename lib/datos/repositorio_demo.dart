import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../modelos.dart';
import 'repositorio.dart';

/// ================================================================
/// MODO DEMO — sin servidor.
/// ================================================================
/// Datos semilla LOCALES equivalentes a los del panel demo
/// (panel/src/data/demoAdapter.ts) y a la semilla del servidor
/// (servidor/datos-demo.sql + datos-trabajos-demo.sql +
/// datos-lavado-demo.sql):
///   · Empresa «Transportes Demo», módulo de lavado ACTIVADO.
///   · MEC-01 (destajo) y MEC-02 (sueldo RD$35,000/mes), PIN 1234.
///   · LAV-01 «Coordinador de Lavado», PIN 1234.
///   · Catálogo de 6 trabajos, 6 vehículos, 16 piezas, trabajos en
///     estados mixtos y 3 guaguas ya lavadas hoy.
/// La app funciona COMPLETA así: registrar trabajos, ver el pago y
/// marcar lavados, sin backend. Al conectar Supabase (conexion.dart)
/// esta clase se sustituye por la real sin tocar las pantallas.
class RepositorioDemo extends RepositorioTaller {
  Usuario? _sesion;
  DatosMecanico? _datosMecanico;
  DatosLavado? _datosLavado;
  DatosCombustible? _datosCombustible;

  @override
  Usuario? get sesion => _sesion;
  @override
  DatosMecanico? get datosMecanico => _datosMecanico;
  @override
  DatosLavado? get datosLavado => _datosLavado;
  @override
  DatosCombustible? get datosCombustible => _datosCombustible;

  // ---------- semilla (equivalente a la del panel demo) ----------

  static const _empresa = Empresa(
    id: 'emp-demo',
    nombre: 'Transportes Demo',
    lavadoActivo: true,
    combustibleActivo: true,
  );

  static const _usuarios = <({Usuario usuario, String pin})>[
    (
      usuario: Usuario(
          id: 'usr-mec1',
          nombre: 'Juan Carlos Pérez',
          codigo: 'MEC-01',
          rol: 'mecanico',
          modoPago: 'destajo'),
      pin: '1234',
    ),
    (
      usuario: Usuario(
          id: 'usr-mec2',
          nombre: 'Luis Manuel Ortiz',
          codigo: 'MEC-02',
          rol: 'mecanico',
          modoPago: 'sueldo',
          sueldoMonto: 35000),
      pin: '1234',
    ),
    (
      usuario: Usuario(
          id: 'usr-lavado',
          nombre: 'Coordinador de Lavado',
          codigo: 'LAV-01',
          rol: 'lavado'),
      pin: '1234',
    ),
    (
      usuario: Usuario(
          id: 'usr-combustible',
          nombre: 'Despachador de Combustible',
          codigo: 'COM-01',
          rol: 'combustible'),
      pin: '1234',
    ),
  ];

  static const _vehiculos = <Vehiculo>[
    Vehiculo(id: 'veh-1', codigo: 'V-01', placa: 'A-523841', marca: 'Hyundai', modelo: 'County', anio: 2019),
    Vehiculo(id: 'veh-2', codigo: 'V-02', placa: 'A-610237', marca: 'Toyota', modelo: 'Coaster', anio: 2018),
    Vehiculo(id: 'veh-3', codigo: 'V-03', placa: 'A-478920', marca: 'Mitsubishi', modelo: 'Fuso Rosa', anio: 2020),
    Vehiculo(id: 'veh-4', codigo: 'V-04', placa: 'A-702155', marca: 'Hyundai', modelo: 'County', anio: 2021),
    Vehiculo(id: 'veh-5', codigo: 'V-05', placa: 'A-389466', marca: 'Toyota', modelo: 'Hiace', anio: 2017),
    Vehiculo(id: 'veh-6', codigo: 'V-06', placa: 'A-655308', marca: 'Mitsubishi', modelo: 'Fuso Canter', anio: 2016),
  ];

  static const _piezas = <Pieza>[
    Pieza(id: 'pza-1', codigo: 'P-01', nombre: 'Filtro de aceite', stock: 14, costo: 650),
    Pieza(id: 'pza-2', codigo: 'P-02', nombre: 'Filtro de combustible', stock: 9, costo: 890),
    Pieza(id: 'pza-3', codigo: 'P-03', nombre: 'Filtro de aire', stock: 4, costo: 1450),
    Pieza(id: 'pza-4', codigo: 'P-04', nombre: 'Batería 12V 100Ah', stock: 3, costo: 8500),
    Pieza(id: 'pza-5', codigo: 'P-05', nombre: 'Goma 215/75 R17.5', stock: 6, costo: 12800),
    Pieza(id: 'pza-6', codigo: 'P-06', nombre: 'Correa de distribución', stock: 5, costo: 2300),
    Pieza(id: 'pza-7', codigo: 'P-07', nombre: 'Bujía', stock: 22, costo: 380),
    Pieza(id: 'pza-8', codigo: 'P-08', nombre: 'Pastillas de freno (juego)', stock: 2, costo: 3150),
    Pieza(id: 'pza-9', codigo: 'P-09', nombre: 'Disco de freno', stock: 4, costo: 4600),
    Pieza(id: 'pza-10', codigo: 'P-10', nombre: 'Aceite de motor 15W-40 (galón)', stock: 18, costo: 1850),
    Pieza(id: 'pza-11', codigo: 'P-11', nombre: 'Amortiguador delantero', stock: 3, costo: 5400),
    Pieza(id: 'pza-12', codigo: 'P-12', nombre: 'Alternador', stock: 1, costo: 14500),
    Pieza(id: 'pza-13', codigo: 'P-13', nombre: 'Motor de arranque', stock: 2, costo: 11900),
    Pieza(id: 'pza-14', codigo: 'P-14', nombre: 'Refrigerante (galón)', stock: 7, costo: 720),
    Pieza(id: 'pza-15', codigo: 'P-15', nombre: 'Kit de clutch', stock: 1, costo: 18750),
    Pieza(id: 'pza-16', codigo: 'P-16', nombre: 'Foco delantero', stock: 5, costo: 2950),
  ];

  static const _tipos = <TipoTrabajo>[
    TipoTrabajo(id: 'tt-1', codigo: 'TT-01', nombre: 'Cambio de aceite', precioManoObra: 500),
    TipoTrabajo(id: 'tt-2', codigo: 'TT-02', nombre: 'Rotación de gomas', precioManoObra: 400),
    TipoTrabajo(id: 'tt-3', codigo: 'TT-03', nombre: 'Cambio de pastillas de freno', precioManoObra: 800),
    TipoTrabajo(id: 'tt-4', codigo: 'TT-04', nombre: 'Afinamiento (bujías y filtros)', precioManoObra: 600),
    TipoTrabajo(id: 'tt-5', codigo: 'TT-05', nombre: 'Cambio de batería', precioManoObra: 300),
    TipoTrabajo(id: 'tt-6', codigo: 'TT-06', nombre: 'Alineación y balanceo', precioManoObra: 900),
  ];

  /// Trabajos vivos de la demo (la semilla + los que se registren).
  final List<Trabajo> _trabajos = [];
  bool _sembrado = false;
  int _contador = 100;

  /// Lavadas de HOY en la demo: vehiculoId → hora ISO del marcado.
  final Map<String, String> _lavadasHoy = {};

  /// Despachos de combustible de la demo (semilla + nuevos).
  final List<DespachoCombustible> _despachos = [];

  static const _tiposCombustible = <TipoCombustible>[
    TipoCombustible(tipo: 'diesel', precioSugerido: 250),
    TipoCombustible(tipo: 'gasolina', precioSugerido: 290),
    TipoCombustible(tipo: 'glp', precioSugerido: 145),
  ];

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _hoy() => _iso(DateTime.now());

  void _sembrar() {
    if (_sembrado) return;
    _sembrado = true;
    final hoy = DateTime.now();
    String hace(int dias) => _iso(hoy.subtract(Duration(days: dias)));

    Trabajo tr(
      String id,
      String vehiculoId,
      String tipoId,
      double precio,
      String estado,
      int diasAtras,
      List<PiezaUsada> piezas,
      String? descripcion, {
      String? notaAdmin,
    }) =>
        Trabajo(
          id: id,
          vehiculoId: vehiculoId,
          tipoTrabajoId: tipoId,
          tipoNombre: _tipos.firstWhere((t) => t.id == tipoId).nombre,
          precio: precio,
          estado: estado,
          fecha: hace(diasAtras),
          descripcion: descripcion,
          notaAdmin: notaAdmin,
          piezas: piezas,
        );

    // Los trabajos de MEC-01 y MEC-02, como en el panel demo. Los de
    // cada mecánico se filtran al construir sus datos: aquí viven
    // todos juntos con su dueño anotado en un mapa auxiliar.
    _duenos
      ..['tr-1'] = 'usr-mec1'
      ..['tr-2'] = 'usr-mec1'
      ..['tr-3'] = 'usr-mec1'
      ..['tr-8'] = 'usr-mec1'
      ..['tr-4'] = 'usr-mec2'
      ..['tr-5'] = 'usr-mec2'
      ..['tr-6'] = 'usr-mec2'
      ..['tr-7'] = 'usr-mec2';
    _trabajos.addAll([
      tr('tr-1', 'veh-3', 'tt-3', 800, 'validada', 2,
          [const PiezaUsada(piezaId: 'pza-8', cantidad: 1)], 'Pastillas delanteras'),
      tr('tr-2', 'veh-1', 'tt-1', 500, 'validada', 1, [
        const PiezaUsada(piezaId: 'pza-1', cantidad: 1),
        const PiezaUsada(piezaId: 'pza-10', cantidad: 2),
      ], 'Cambio de aceite y filtro'),
      tr('tr-3', 'veh-4', 'tt-4', 600, 'pendiente', 0,
          [const PiezaUsada(piezaId: 'pza-7', cantidad: 6)], 'Afinamiento completo'),
      tr('tr-8', 'veh-2', 'tt-2', 400, 'validada', 5,
          const [], 'Rotación de gomas'),
      tr('tr-4', 'veh-3', 'tt-1', 500, 'validada', 3, [
        const PiezaUsada(piezaId: 'pza-10', cantidad: 3),
        const PiezaUsada(piezaId: 'pza-1', cantidad: 2),
      ], 'Cambio de aceite'),
      tr('tr-5', 'veh-5', 'tt-5', 300, 'validada', 1,
          [const PiezaUsada(piezaId: 'pza-4', cantidad: 1)], 'Batería nueva instalada'),
      tr('tr-6', 'veh-2', 'tt-2', 400, 'rechazada', 2, const [],
          'Rotación de las cuatro gomas',
          notaAdmin: 'La rotación no se hizo: las gomas están en buen estado'),
      tr('tr-7', 'veh-6', 'tt-6', 900, 'pendiente', 0,
          const [], 'Alineación y balanceo'),
    ]);

    // Lavadas de hoy sembradas (como en el panel): V-01, V-02 y V-04.
    final hoyIso = _hoy();
    _lavadasHoy['veh-1'] = '${hoyIso}T07:15:00';
    _lavadasHoy['veh-2'] = '${hoyIso}T08:05:00';
    _lavadasHoy['veh-4'] = '${hoyIso}T09:40:00';

    // Despachos de combustible sembrados (como en el panel): varios
    // días con odómetros coherentes; la V-05 rinde 10.0 km/gal
    // (la mala a propósito).
    DespachoCombustible des(String id, String vehiculoId, int diasAtras,
            String hora, double galones, double odometro, double costo) =>
        DespachoCombustible(
          id: id,
          vehiculoId: vehiculoId,
          vehiculoCodigo:
              _vehiculos.firstWhere((v) => v.id == vehiculoId).codigo,
          galones: galones,
          tipo: 'diesel',
          odometro: odometro,
          costoUnitario: costo,
          total: (galones * costo * 100).round() / 100,
          fecha: hace(diasAtras),
          creadaEn: '${hace(diasAtras)}T$hora:00',
          despachadorNombre: 'Despachador de Combustible',
        );
    _despachos.addAll([
      des('des-1', 'veh-1', 6, '08:00', 18, 120000, 250),
      des('des-2', 'veh-1', 3, '08:05', 17, 120540, 250),
      des('des-3', 'veh-1', 0, '08:10', 16, 121050, 252),
      des('des-4', 'veh-2', 5, '07:45', 15, 98200, 250),
      des('des-5', 'veh-2', 2, '08:15', 16, 98780, 250),
      des('des-6', 'veh-2', 0, '08:25', 15, 99310, 252),
      des('des-7', 'veh-3', 0, '09:05', 11, 65410, 252),
      des('des-8', 'veh-4', 5, '07:30', 16, 45200, 248),
      des('des-9', 'veh-4', 0, '07:50', 17, 46100, 252),
      des('des-10', 'veh-5', 6, '08:20', 14, 210300, 250),
      des('des-11', 'veh-5', 3, '08:30', 15, 210520, 250),
      des('des-12', 'veh-5', 1, '08:40', 14, 210700, 250),
      des('des-13', 'veh-5', 0, '09:30', 15, 210880, 252),
      des('des-14', 'veh-6', 2, '10:00', 10, 178900, 250),
    ]);
  }

  /// Dueño de cada trabajo de la semilla (el modelo Trabajo no lleva
  /// mecanicoId porque la app solo ve los del propio usuario).
  final Map<String, String> _duenos = {};

  // ---------- sesión ----------

  Future<File> _archivoSesion() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/sesion_tallerneto.json');
  }

  Future<void> _guardarSesion(String usuarioId) async {
    try {
      final f = await _archivoSesion();
      await f.writeAsString(jsonEncode({'usuarioId': usuarioId, 'demo': true}));
    } catch (_) {
      // Si el teléfono no deja guardar, la sesión vale por esta apertura.
    }
  }

  Future<void> _borrarSesionGuardada() async {
    try {
      final f = await _archivoSesion();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  @override
  Future<Usuario> iniciarSesion(String codigo, String pin) async {
    _sembrar();
    final buscado = codigo.trim().toUpperCase();
    for (final entrada in _usuarios) {
      if (entrada.usuario.codigo.toUpperCase() == buscado) {
        if (entrada.pin != pin) {
          throw const ErrorServidor('Código o PIN incorrecto');
        }
        _sesion = entrada.usuario;
        await _guardarSesion(entrada.usuario.id);
        _prepararDatos();
        notifyListeners();
        return entrada.usuario;
      }
    }
    throw const ErrorServidor('Código o PIN incorrecto');
  }

  @override
  Future<bool> restaurarSesion() async {
    _sembrar();
    try {
      final f = await _archivoSesion();
      if (!await f.exists()) return false;
      final datos = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final id = datos['usuarioId']?.toString();
      for (final entrada in _usuarios) {
        if (entrada.usuario.id == id) {
          _sesion = entrada.usuario;
          _prepararDatos();
          notifyListeners();
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> cerrarSesion() async {
    _sesion = null;
    _datosMecanico = null;
    _datosLavado = null;
    _datosCombustible = null;
    await _borrarSesionGuardada();
    notifyListeners();
  }

  void _prepararDatos() {
    final u = _sesion;
    if (u == null) return;
    if (u.esLavado) {
      _datosLavado = _construirDatosLavado(u);
    } else if (u.esCombustible) {
      _datosCombustible = _construirDatosCombustible(u);
    } else {
      _datosMecanico = _construirDatosMecanico(u);
    }
  }

  // ---------- mecánico ----------

  DatosMecanico _construirDatosMecanico(Usuario u) {
    final mes = '${_hoy().substring(0, 8)}01';
    final mios = _trabajos.where((t) => _duenos[t.id] == u.id).toList()
      ..sort((a, b) => b.fecha.compareTo(a.fecha));
    double suma(String estado) => mios
        .where((t) => t.estado == estado && t.fecha.compareTo(mes) >= 0)
        .fold(0.0, (s, t) => s + t.precio);
    return DatosMecanico(
      usuario: u,
      empresa: _empresa,
      tiposTrabajo: _tipos,
      vehiculos: _vehiculos,
      piezas: _piezas,
      trabajos: mios,
      totalValidadoMes: suma('validada'),
      totalPendienteMes: suma('pendiente'),
    );
  }

  @override
  Future<void> recargarMecanico() async {
    final u = _sesion;
    if (u == null || u.esLavado) return;
    _datosMecanico = _construirDatosMecanico(u);
    notifyListeners();
  }

  @override
  Future<Trabajo> registrarTrabajo({
    required String vehiculoId,
    required String tipoTrabajoId,
    required List<PiezaUsada> piezas,
    String? descripcion,
  }) async {
    final u = _sesion;
    if (u == null || u.rol != 'mecanico') {
      throw const ErrorServidor('Solo un mecánico registra trabajos');
    }
    final tipos = _tipos.where((t) => t.id == tipoTrabajoId);
    if (tipos.isEmpty) throw const ErrorServidor('Tipo de trabajo no válido');
    final tipo = tipos.first;
    if (!_vehiculos.any((v) => v.id == vehiculoId)) {
      throw const ErrorServidor('Vehículo no válido');
    }
    _contador += 1;
    final nuevo = Trabajo(
      id: 'tr-nuevo-$_contador',
      vehiculoId: vehiculoId,
      tipoTrabajoId: tipo.id,
      tipoNombre: tipo.nombre,
      // Copia del precio del catálogo al registrar (snapshot).
      precio: tipo.precioManoObra,
      estado: 'pendiente',
      fecha: _hoy(),
      descripcion: (descripcion == null || descripcion.trim().isEmpty)
          ? null
          : descripcion.trim(),
      piezas: List.of(piezas),
    );
    _duenos[nuevo.id] = u.id;
    _trabajos.insert(0, nuevo);
    _datosMecanico = _construirDatosMecanico(u);
    notifyListeners();
    return nuevo;
  }

  // ---------- lavado ----------

  DatosLavado _construirDatosLavado(Usuario u) {
    return DatosLavado(
      usuario: u,
      empresa: _empresa,
      fecha: _hoy(),
      vehiculos: _vehiculos
          .map(
            (v) => VehiculoLavado(
              vehiculo: v,
              lavadoHoy: _lavadasHoy.containsKey(v.id),
              marcadaEn: _lavadasHoy[v.id],
              marcadaPorNombre:
                  _lavadasHoy.containsKey(v.id) ? 'Coordinador de Lavado' : null,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<void> recargarLavado() async {
    final u = _sesion;
    if (u == null || !u.esLavado) return;
    _datosLavado = _construirDatosLavado(u);
    notifyListeners();
  }

  @override
  Future<void> marcarLavado(String vehiculoId) async {
    final u = _sesion;
    if (u == null || !u.esLavado) {
      throw const ErrorServidor('Solo el coordinador de lavado marca lavados');
    }
    if (!_empresa.lavadoActivo) {
      throw const ErrorServidor('El módulo de lavado no está activo en esta empresa');
    }
    if (_lavadasHoy.containsKey(vehiculoId)) {
      // Anti-duplicado: una guagua, una vez por día (como el servidor).
      final v = _vehiculos.firstWhere((x) => x.id == vehiculoId);
      throw ErrorServidor('El vehículo ${v.codigo} ya está marcado como lavado hoy');
    }
    _lavadasHoy[vehiculoId] = DateTime.now().toIso8601String();
    _datosLavado = _construirDatosLavado(u);
    notifyListeners();
  }

  @override
  Future<void> desmarcarLavado(String vehiculoId) async {
    final u = _sesion;
    if (u == null || !u.esLavado) {
      throw const ErrorServidor('Solo el coordinador de lavado desmarca lavados');
    }
    if (!_lavadasHoy.containsKey(vehiculoId)) {
      final v = _vehiculos.firstWhere((x) => x.id == vehiculoId);
      throw ErrorServidor('El vehículo ${v.codigo} no está marcado como lavado hoy');
    }
    // En el servidor el desmarcado queda auditado (quién y cuándo);
    // en la demo basta con quitar el marcado del día.
    _lavadasHoy.remove(vehiculoId);
    _datosLavado = _construirDatosLavado(u);
    notifyListeners();
  }

  // ---------- combustible ----------

  double? _ultimoOdometro(String vehiculoId) {
    double? ultimo;
    for (final d in _despachos) {
      if (d.vehiculoId == vehiculoId &&
          (ultimo == null || d.odometro > ultimo)) {
        ultimo = d.odometro;
      }
    }
    return ultimo;
  }

  DatosCombustible _construirDatosCombustible(Usuario u) {
    final hoy = _hoy();
    final deHoy = _despachos.where((d) => d.fecha == hoy).toList()
      ..sort((a, b) => b.creadaEn.compareTo(a.creadaEn));
    return DatosCombustible(
      usuario: u,
      empresa: _empresa,
      fecha: hoy,
      tipos: _tiposCombustible,
      vehiculos: _vehiculos
          .map((v) => VehiculoCombustible(
                vehiculo: v,
                ultimoOdometro: _ultimoOdometro(v.id),
              ))
          .toList(),
      despachosHoy: deHoy,
      totalGalonesHoy: deHoy.fold(0.0, (s, d) => s + d.galones),
      totalCostoHoy: deHoy.fold(0.0, (s, d) => s + d.total),
    );
  }

  @override
  Future<void> recargarCombustible() async {
    final u = _sesion;
    if (u == null || !u.esCombustible) return;
    _datosCombustible = _construirDatosCombustible(u);
    notifyListeners();
  }

  @override
  Future<DespachoCombustible> registrarDespacho({
    required String vehiculoId,
    required double galones,
    required String tipo,
    required double odometro,
    required double costoUnitario,
  }) async {
    final u = _sesion;
    if (u == null || !u.esCombustible) {
      throw const ErrorServidor('Solo el despachador registra despachos');
    }
    if (!_empresa.combustibleActivo) {
      throw const ErrorServidor(
          'El módulo de combustible no está activo en esta empresa');
    }
    final vehiculos = _vehiculos.where((v) => v.id == vehiculoId);
    if (vehiculos.isEmpty) {
      throw const ErrorServidor('Todo despacho debe decir el vehículo');
    }
    final v = vehiculos.first;
    if (galones <= 0) {
      throw const ErrorServidor('La cantidad de galones debe ser mayor que cero');
    }
    if (!_tiposCombustible.any((t) => t.tipo == tipo)) {
      throw ErrorServidor('Tipo de combustible no válido: $tipo');
    }
    // Regla de integridad (espejo del servidor): el odómetro no baja.
    final ultimo = _ultimoOdometro(vehiculoId);
    if (ultimo != null && odometro < ultimo) {
      throw ErrorServidor(
          'El odómetro ($odometro) es menor que el último registrado '
          '($ultimo) para el vehículo ${v.codigo}: revísalo');
    }
    _contador += 1;
    final nuevo = DespachoCombustible(
      id: 'des-nuevo-$_contador',
      vehiculoId: v.id,
      vehiculoCodigo: v.codigo,
      galones: galones,
      tipo: tipo,
      odometro: odometro,
      costoUnitario: costoUnitario,
      total: (galones * costoUnitario * 100).round() / 100,
      fecha: _hoy(),
      creadaEn: DateTime.now().toIso8601String(),
      despachadorNombre: u.nombre,
    );
    _despachos.insert(0, nuevo);
    _datosCombustible = _construirDatosCombustible(u);
    notifyListeners();
    return nuevo;
  }
}
