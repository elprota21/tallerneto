import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../modelos.dart';
import 'conexion.dart';
import 'repositorio.dart';

/// ================================================================
/// MODO REAL — contra Supabase de PRODUCCIÓN («staffride»).
/// ================================================================
/// Implementación real de [RepositorioTaller] (versión única
/// 1.4.0, 2026-11-21): la app deja la demo local y trabaja contra
/// las RPC `pr_*` del servidor de producción, con el mismo patrón
/// probado en la app de RutaNeto (REST/RPC con la anon key PÚBLICA
/// de [Conexion]; la seguridad vive en las funciones security
/// definer + RLS sin políticas, y en el token de sesión que
/// entrega `pr_iniciar_sesion` y viaja en cada RPC).
///
/// Funciones que usa:
///  - `pr_iniciar_sesion` (p_contexto 'app') → usuario + empresa
///    + token de sesión. La cuenta del dueño (sin empresa) se
///    rechaza aquí: no opera dentro de las empresas.
///  - `pr_datos_mecanico` / `pr_registrar_trabajo` /
///    `pr_solicitar_pieza` → trabajos y solicitudes del mecánico.
///  - `pr_datos_lavado` / `pr_marcar_lavado` / `pr_desmarcar_lavado`.
///  - `pr_datos_combustible` / `pr_registrar_despacho` /
///    `pr_registrar_recepcion`.
///  - `pr_datos_inventario_app` / `pr_pasar_inventario_unidad` →
///    la ficha VIGENTE que el administrador definió en el panel.
///  - `pr_cambiar_nombre` / `pr_cambiar_pin` → autoservicios del
///    Perfil (el PIN actual autoriza; cambiar el PIN revoca las
///    sesiones en el servidor, así que la app vuelve a la entrada).
///  - `pr_cerrar_sesion` → revoca el token al salir (best-effort).
///
/// Las RPC de registro devuelven la FILA creada (columnas del
/// servidor); tras cada registro se recarga la foto del rol y se
/// devuelve el objeto ya parseado de esa foto, para que las
/// pantallas reciban exactamente los mismos modelos que en demo.
///
/// Sin cola offline en esta implementación: cada registro va
/// directo al servidor y, si no hay conexión, [_rpc] lo dice con
/// un mensaje claro en vez de guardarlo a medias.
class RepositorioReal extends RepositorioTaller {
  Usuario? _sesion;
  String? _token;
  String? _empresaId;
  DatosMecanico? _datosMecanico;
  DatosLavado? _datosLavado;
  DatosCombustible? _datosCombustible;
  DatosInventarioUnidad? _datosInventarioUnidad;

  @override
  Usuario? get sesion => _sesion;
  @override
  DatosMecanico? get datosMecanico => _datosMecanico;
  @override
  DatosLavado? get datosLavado => _datosLavado;
  @override
  DatosCombustible? get datosCombustible => _datosCombustible;
  @override
  DatosInventarioUnidad? get datosInventarioUnidad => _datosInventarioUnidad;

  static const mensajeSinConexion =
      'Sin conexión con el servidor. Revisa tu internet e inténtalo de nuevo.';

  Map<String, String> get _headers => {
        'apikey': Conexion.anonKey,
        'Authorization': 'Bearer ${Conexion.anonKey}',
        'Content-Type': 'application/json',
      };

  /// Llamada RPC genérica: devuelve el JSON decodificado y traduce
  /// los errores del servidor (campo `message`) y los de conexión
  /// a [ErrorServidor] con texto listo para pantalla.
  Future<dynamic> _rpc(String funcion, Map<String, dynamic> params) async {
    final http.Response r;
    try {
      r = await http
          .post(
            Uri.parse('${Conexion.urlSupabase}/rest/v1/rpc/$funcion'),
            headers: _headers,
            body: jsonEncode(params),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ErrorServidor(mensajeSinConexion);
    }
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return r.body.isEmpty ? null : jsonDecode(r.body);
    }
    var mensaje = 'El servidor respondió un error (${r.statusCode}).';
    try {
      final cuerpo = jsonDecode(r.body);
      if (cuerpo is Map && cuerpo['message'] is String) {
        mensaje = cuerpo['message'] as String;
      }
    } catch (_) {
      // El cuerpo no era JSON: se queda el mensaje genérico.
    }
    throw ErrorServidor(mensaje);
  }

  Map<String, dynamic> get _quienToken => {
        'p_quien': _sesion?.id,
        'p_token': _token,
      };

  // ---------- sesión ----------

  Future<File> _archivoSesion() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/sesion_tallerneto.json');
  }

  Future<void> _guardarSesion() async {
    final u = _sesion;
    if (u == null || _token == null) return;
    try {
      final f = await _archivoSesion();
      await f.writeAsString(jsonEncode({
        'real': true,
        'token': _token,
        'empresaId': _empresaId,
        'usuario': {
          'id': u.id,
          'nombre': u.nombre,
          'codigo': u.codigo,
          'rol': u.rol,
          'rolAdicional': u.rolAdicional,
          'modoPago': u.modoPago,
          'sueldoMonto': u.sueldoMonto,
          'puedeInventarioUnidad': u.puedeInventarioUnidad,
        },
      }));
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

  String? _rolInicial(Usuario u) =>
      u.rolesApp.length == 1 ? u.rolesApp.first : null;

  @override
  Future<Usuario> iniciarSesion(String codigo, String pin) async {
    final datos = await _rpc('pr_iniciar_sesion', {
      'p_codigo': codigo.trim(),
      'p_pin': pin.trim(),
      'p_contexto': 'app',
    }) as Map<String, dynamic>;
    final empresa = datos['empresa'] as Map<String, dynamic>?;
    if (empresa == null) {
      // Superadmin/dueño: sin empresa; su puerta es el súper panel.
      throw const ErrorServidor(
          'Ese código es del dueño del sistema y no usa esta app: '
          'su acceso es por el panel.');
    }
    final usuario = Usuario.desdeJson(datos['usuario'] as Map<String, dynamic>);
    if (usuario.rolesApp.isEmpty) {
      throw const ErrorServidor(
          'Esta app es para el personal del taller (mecánico, lavado y '
          'combustible). Tu cuenta entra desde el panel de la empresa.');
    }
    _sesion = usuario;
    _empresaId = empresa['id'].toString();
    _token = (datos['sesion'] as Map<String, dynamic>?)?['token']?.toString();
    fijarRolActivo(_rolInicial(usuario));
    await _cargarDatos();
    await _guardarSesion();
    notifyListeners();
    return _sesion!;
  }

  @override
  Future<bool> restaurarSesion() async {
    try {
      final f = await _archivoSesion();
      if (!await f.exists()) return false;
      final datos = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (datos['real'] != true || datos['token'] == null) return false;
      _token = datos['token'].toString();
      _empresaId = datos['empresaId']?.toString();
      _sesion =
          Usuario.desdeJson(datos['usuario'] as Map<String, dynamic>);
      fijarRolActivo(_rolInicial(_sesion!));
      // Sonda con la foto del rol principal: si el servidor
      // rechaza el token (expiró o fue revocado), la sesión
      // guardada ya no vale y se pide entrar de nuevo. Sin
      // conexión NO se expulsa: se entra con lo guardado.
      try {
        await _cargarDatos();
      } on ErrorServidor catch (e) {
        if (e.mensaje != mensajeSinConexion) {
          _sesion = null;
          _token = null;
          await _borrarSesionGuardada();
          return false;
        }
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> cerrarSesion() async {
    final token = _token;
    if (token != null) {
      try {
        await _rpc('pr_cerrar_sesion', {'p_token': token});
      } catch (_) {
        // Sin conexión se sale igual: la sesión local se borra.
      }
    }
    _sesion = null;
    _token = null;
    _empresaId = null;
    _datosMecanico = null;
    _datosLavado = null;
    _datosCombustible = null;
    _datosInventarioUnidad = null;
    fijarRolActivo(null);
    await _borrarSesionGuardada();
    notifyListeners();
  }

  /// Al fijar el rol activo (al entrar o al cambiarlo en el
  /// Perfil) se recarga la foto de ese rol en segundo plano.
  @override
  void alFijarRolActivo() {
    if (_sesion == null) return;
    unawaited(_cargarDatos().then((_) => notifyListeners(),
        onError: (_) {}));
  }

  /// Baja la foto de cada rol CON pantalla del usuario y la del
  /// inventario si está autorizado. Un módulo extra no activo
  /// hace fallar SOLO su foto (el servidor la rechaza): las demás
  /// siguen cargando y la pantalla de ese módulo mostrará su
  /// mensaje comercial.
  Future<void> _cargarDatos() async {
    final u = _sesion;
    if (u == null) return;
    final roles = u.rolesApp;
    if (roles.contains('mecanico')) {
      try {
        await recargarMecanico();
      } on ErrorServidor catch (e) {
        if (e.mensaje == mensajeSinConexion) rethrow;
      }
    }
    if (roles.contains('lavado')) {
      try {
        await recargarLavado();
      } on ErrorServidor catch (e) {
        if (e.mensaje == mensajeSinConexion) rethrow;
      }
    }
    if (roles.contains('combustible')) {
      try {
        await recargarCombustible();
      } on ErrorServidor catch (e) {
        if (e.mensaje == mensajeSinConexion) rethrow;
      }
    }
    if (u.puedePasarInventario) {
      try {
        await recargarInventarioUnidad();
      } on ErrorServidor catch (e) {
        if (e.mensaje == mensajeSinConexion) rethrow;
      }
    }
  }

  @override
  Future<void> cambiarNombre({
    required String pinActual,
    required String nombreNuevo,
  }) async {
    final u = _sesion;
    if (u == null) throw const ErrorServidor('No hay sesión iniciada');
    await _rpc('pr_cambiar_nombre', {
      'p_usuario': u.id,
      'p_pin_actual': pinActual,
      'p_nombre_nuevo': nombreNuevo.trim(),
    });
    _sesion = Usuario(
      id: u.id,
      nombre: nombreNuevo.trim(),
      codigo: u.codigo,
      rol: u.rol,
      rolAdicional: u.rolAdicional,
      modoPago: u.modoPago,
      sueldoMonto: u.sueldoMonto,
      puedeInventarioUnidad: u.puedeInventarioUnidad,
    );
    await _guardarSesion();
    notifyListeners();
  }

  /// Cambia MI PIN (pr_cambiar_pin; la función ya existía en el
  /// servidor — la usa el panel — y la app la estrena en la
  /// 1.5.0). El servidor revoca TODAS las sesiones del usuario
  /// al cambiar el PIN, incluida esta: la sesión local queda
  /// muerta y el Perfil cierra la sesión tras esta llamada para
  /// pedirme entrar con el PIN nuevo.
  @override
  Future<void> cambiarPin({
    required String pinActual,
    required String pinNuevo,
  }) async {
    final u = _sesion;
    if (u == null) throw const ErrorServidor('No hay sesión iniciada');
    await _rpc('pr_cambiar_pin', {
      'p_usuario': u.id,
      'p_pin_actual': pinActual,
      'p_pin_nuevo': pinNuevo.trim(),
    });
  }

  // ---------- mecánico ----------

  @override
  Future<void> recargarMecanico() async {
    if (_sesion == null) return;
    final datos = await _rpc('pr_datos_mecanico', _quienToken)
        as Map<String, dynamic>;
    _datosMecanico = DatosMecanico.desdeJson(datos);
    notifyListeners();
  }

  @override
  Future<Trabajo> registrarTrabajo({
    required String vehiculoId,
    required String tipoTrabajoId,
    required List<PiezaUsada> piezas,
    String? descripcion,
  }) async {
    final fila = await _rpc('pr_registrar_trabajo', {
      'p_empresa': _empresaId,
      'p_vehiculo': vehiculoId,
      'p_tipo': tipoTrabajoId,
      'p_descripcion': descripcion,
      'p_piezas': piezas.map((p) => p.aJson()).toList(),
      ..._quienToken,
    }) as Map<String, dynamic>;
    await recargarMecanico();
    final id = fila['id'].toString();
    for (final t in _datosMecanico?.trabajos ?? const <Trabajo>[]) {
      if (t.id == id) return t;
    }
    // Respaldo: construir desde la fila del servidor.
    return Trabajo(
      id: id,
      vehiculoId: fila['vehiculo_id'].toString(),
      tipoTrabajoId: fila['tipo_trabajo_id'].toString(),
      tipoNombre: '',
      precio: (fila['precio_snapshot'] as num?)?.toDouble() ?? 0,
      estado: fila['estado']?.toString() ?? 'pendiente',
      fecha: fila['fecha']?.toString() ?? '',
      descripcion: fila['descripcion']?.toString(),
      piezas: piezas,
    );
  }

  @override
  Future<SolicitudPieza> solicitarPieza({
    String? piezaId,
    String? nombre,
    required int cantidad,
    String? vehiculoId,
    String urgencia = 'normal',
    String? nota,
  }) async {
    final fila = await _rpc('pr_solicitar_pieza', {
      'p_empresa': _empresaId,
      'p_nombre': nombre,
      'p_cantidad': cantidad,
      'p_pieza': piezaId,
      'p_vehiculo': vehiculoId,
      'p_urgencia': urgencia,
      'p_nota': nota,
      ..._quienToken,
    }) as Map<String, dynamic>;
    await recargarMecanico();
    final id = fila['id'].toString();
    for (final s in _datosMecanico?.solicitudes ?? const <SolicitudPieza>[]) {
      if (s.id == id) return s;
    }
    return SolicitudPieza(
      id: id,
      piezaId: fila['pieza_id']?.toString(),
      nombrePieza: fila['nombre_pieza']?.toString() ?? '',
      cantidad: (fila['cantidad'] as num?)?.toInt() ?? cantidad,
      vehiculoId: fila['vehiculo_id']?.toString(),
      urgencia: fila['urgencia']?.toString() ?? urgencia,
      nota: fila['nota']?.toString(),
      estado: fila['estado']?.toString() ?? 'pendiente',
      fecha: fila['fecha']?.toString() ?? '',
      creadaEn: fila['creada_en']?.toString() ?? '',
    );
  }

  // ---------- lavado ----------

  @override
  Future<void> recargarLavado() async {
    if (_sesion == null) return;
    final datos = await _rpc('pr_datos_lavado', _quienToken)
        as Map<String, dynamic>;
    _datosLavado = DatosLavado.desdeJson(datos);
    notifyListeners();
  }

  @override
  Future<void> marcarLavado(String vehiculoId) async {
    await _rpc('pr_marcar_lavado', {
      'p_empresa': _empresaId,
      'p_vehiculo': vehiculoId,
      ..._quienToken,
    });
    await recargarLavado();
  }

  @override
  Future<void> desmarcarLavado(String vehiculoId) async {
    await _rpc('pr_desmarcar_lavado', {
      'p_empresa': _empresaId,
      'p_vehiculo': vehiculoId,
      ..._quienToken,
    });
    await recargarLavado();
  }

  // ---------- combustible ----------

  @override
  Future<void> recargarCombustible() async {
    if (_sesion == null) return;
    final datos = await _rpc('pr_datos_combustible', _quienToken)
        as Map<String, dynamic>;
    _datosCombustible = DatosCombustible.desdeJson(datos);
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
    final fila = await _rpc('pr_registrar_despacho', {
      'p_empresa': _empresaId,
      'p_vehiculo': vehiculoId,
      'p_galones': galones,
      'p_tipo': tipo,
      'p_odometro': odometro,
      'p_costo_galon': costoUnitario,
      ..._quienToken,
    }) as Map<String, dynamic>;
    await recargarCombustible();
    final id = fila['id'].toString();
    for (final d in _datosCombustible?.despachosHoy ??
        const <DespachoCombustible>[]) {
      if (d.id == id) return d;
    }
    return DespachoCombustible(
      id: id,
      vehiculoId: fila['vehiculo_id'].toString(),
      vehiculoCodigo: '',
      galones: (fila['galones'] as num?)?.toDouble() ?? galones,
      tipo: fila['tipo_combustible']?.toString() ?? tipo,
      odometro: (fila['odometro'] as num?)?.toDouble() ?? odometro,
      costoUnitario: (fila['costo_galon'] as num?)?.toDouble() ?? costoUnitario,
      total: (fila['total'] as num?)?.toDouble() ?? 0,
      fecha: fila['fecha']?.toString() ?? '',
      creadaEn: fila['creada_en']?.toString() ?? '',
      despachadorNombre: _sesion?.nombre,
    );
  }

  @override
  Future<RecepcionCombustible> registrarRecepcion({
    required String tipo,
    required double galones,
    required double costoUnitario,
    String? proveedor,
    String? nota,
  }) async {
    final fila = await _rpc('pr_registrar_recepcion', {
      'p_empresa': _empresaId,
      'p_tipo': tipo,
      'p_galones': galones,
      'p_costo_galon': costoUnitario,
      'p_proveedor': proveedor,
      'p_nota': nota,
      ..._quienToken,
    }) as Map<String, dynamic>;
    await recargarCombustible();
    return RecepcionCombustible(
      id: fila['id'].toString(),
      tipo: fila['tipo_combustible']?.toString() ?? tipo,
      galones: (fila['galones'] as num?)?.toDouble() ?? galones,
      costoUnitario: (fila['costo_galon'] as num?)?.toDouble() ?? costoUnitario,
      total: (fila['total'] as num?)?.toDouble() ?? 0,
      proveedor: fila['proveedor']?.toString(),
      nota: fila['nota']?.toString(),
      fecha: fila['fecha']?.toString() ?? '',
      creadaEn: fila['creada_en']?.toString() ?? '',
    );
  }

  // ---------- inventario por unidad ----------

  @override
  Future<void> recargarInventarioUnidad() async {
    if (_sesion == null) return;
    final datos = await _rpc('pr_datos_inventario_app', _quienToken)
        as Map<String, dynamic>;
    _datosInventarioUnidad = DatosInventarioUnidad.desdeJson(datos);
    notifyListeners();
  }

  @override
  Future<RevisionInventario> pasarInventarioUnidad({
    required String vehiculoId,
    required List<MarcaArticulo> marcas,
    String? nota,
  }) async {
    final datos = await _rpc('pr_pasar_inventario_unidad', {
      'p_empresa': _empresaId,
      'p_vehiculo': vehiculoId,
      'p_resultados': marcas.map((m) => m.aJson()).toList(),
      'p_nota': nota,
      ..._quienToken,
    }) as Map<String, dynamic>;
    final revision = RevisionInventario.desdeJson(datos);
    await recargarInventarioUnidad();
    return revision;
  }
}
