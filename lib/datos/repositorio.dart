import 'package:flutter/foundation.dart';

import '../modelos.dart';
import 'conexion.dart';
import 'repositorio_demo.dart';
import 'repositorio_real.dart';

/// Error con un mensaje listo para mostrar: lo lanza el repositorio
/// cuando el servidor (o la demo) rechaza la operación.
class ErrorServidor implements Exception {
  const ErrorServidor(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Capa de datos de la app del taller.
///
/// La app sirve a DOS roles con la misma interfaz:
///  - mecanico: registra trabajos y ve su pago (destajo o sueldo).
///  - lavado: marca las unidades lavadas del día (si la empresa
///    tiene el módulo de lavado activo).
///
/// Implementación actual: [RepositorioDemo] (sin servidor). Cuando
/// exista el proyecto Supabase «taller-neto», se añade la real sin
/// tocar las pantallas (ver datos/conexion.dart).
abstract class RepositorioTaller extends ChangeNotifier {
  Usuario? get sesion;

  // ---------- rol activo (rol principal + rol adicional) ----------

  String? _rolActivo;

  /// Con cuál de mis roles CON pantalla estoy trabajando ahora
  /// ('mecanico' | 'lavado' | 'combustible'). Null cuando todavía
  /// no se eligió: solo pasa si el usuario tiene DOS roles con
  /// pantalla — la principal muestra entonces el selector. Si el
  /// rol adicional es almacén (sin pantalla), al entrar se fija
  /// solo el rol de app y nunca hace falta elegir.
  String? get rolActivo => _rolActivo;

  /// El rol que manda en pantalla: el activo, o el principal.
  String? get rolEnPantalla => _rolActivo ?? sesion?.rol;

  /// Fija el rol activo (al entrar y al cambiarlo desde el Perfil)
  /// y reconstruye los datos de ese rol en la implementación.
  void fijarRolActivo(String? rol) {
    _rolActivo = rol;
    alFijarRolActivo();
    notifyListeners();
  }

  /// Gancho de las implementaciones: preparar los datos del rol
  /// activo recién fijado. La base no hace nada.
  void alFijarRolActivo() {}

  /// Entrada con código + PIN. Si entra, la sesión queda guardada en
  /// el teléfono. Si no, lanza [ErrorServidor] con el mensaje.
  Future<Usuario> iniciarSesion(String codigo, String pin);

  /// Al abrir la app: restaura la sesión guardada, si la hay.
  Future<bool> restaurarSesion();

  /// Cierra la sesión y borra la guardada.
  Future<void> cerrarSesion();

  /// Cambia MI nombre visible (el que ven administración y los
  /// compañeros). El servidor (pr_cambiar_nombre) lo autoriza con
  /// mi PIN actual: cada quien solo puede cambiar el suyo.
  Future<void> cambiarNombre({
    required String pinActual,
    required String nombreNuevo,
  });

  /// Cambia MI PIN de acceso (el servidor, pr_cambiar_pin, lo
  /// autoriza con mi PIN actual y exige 4–6 dígitos, nunca 1234).
  /// OJO: al cambiar el PIN el servidor REVOCA todas mis
  /// sesiones, así que tras un cambio correcto la app debe
  /// cerrar la sesión local y pedirme entrar con el PIN nuevo
  /// (eso lo hace la pantalla del Perfil tras esta llamada).
  Future<void> cambiarPin({
    required String pinActual,
    required String pinNuevo,
  });

  // ---------- mecánico ----------
  DatosMecanico? get datosMecanico;
  Future<void> recargarMecanico();

  /// Registra un trabajo terminado (nace pendiente de validar).
  Future<Trabajo> registrarTrabajo({
    required String vehiculoId,
    required String tipoTrabajoId,
    required List<PiezaUsada> piezas,
    String? descripcion,
  });

  /// Pide una pieza a administración (nace pendiente). O del
  /// catálogo ([piezaId]) o de texto libre ([nombre]). Solo el
  /// rol mecánico, siempre a su propio nombre.
  Future<SolicitudPieza> solicitarPieza({
    String? piezaId,
    String? nombre,
    required int cantidad,
    String? vehiculoId,
    String urgencia = 'normal',
    String? nota,
  });

  // ---------- lavado ----------
  DatosLavado? get datosLavado;
  Future<void> recargarLavado();
  Future<void> marcarLavado(String vehiculoId);
  Future<void> desmarcarLavado(String vehiculoId);

  // ---------- combustible ----------
  DatosCombustible? get datosCombustible;
  Future<void> recargarCombustible();

  /// Registra un despacho. El odómetro no puede ser menor que el
  /// último registrado para ese vehículo, y el tanque debe tener
  /// saldo suficiente del tipo (reglas del servidor).
  Future<DespachoCombustible> registrarDespacho({
    required String vehiculoId,
    required double galones,
    required String tipo,
    required double odometro,
    required double costoUnitario,
  });

  /// Registra una recepción: la carga que entró al tanque
  /// (suma al saldo del tipo). Solo el rol combustible (y admin).
  Future<RecepcionCombustible> registrarRecepcion({
    required String tipo,
    required double galones,
    required double costoUnitario,
    String? proveedor,
    String? nota,
  });

  // ---------- inventario por unidad ----------

  /// Las unidades con su ficha VIGENTE del servidor: la lista de
  /// artículos la define el administrador en el panel y la app la
  /// lee tal cual cada vez (nada de listas fijas en la app).
  DatosInventarioUnidad? get datosInventarioUnidad;
  Future<void> recargarInventarioUnidad();

  /// Guarda una pasada de inventario: recorre la ficha completa
  /// de la unidad marcando cada artículo (bueno / dañado /
  /// faltante, con nota si hace falta). Solo quien puede pasar
  /// inventario (mecánico o usuario autorizado desde el panel);
  /// pasar inventario NUNCA edita la ficha. El resultado vuelve
  /// al panel (historial de la unidad).
  Future<RevisionInventario> pasarInventarioUnidad({
    required String vehiculoId,
    required List<MarcaArticulo> marcas,
    String? nota,
  });

  // ---------- cola de salida (offline) ----------

  /// Registros guardados en el teléfono pendientes de envío.
  /// La base no tiene cola: 0.
  int get pendientesEnvio => 0;

  /// Descripciones cortas de lo que está por enviar (Perfil).
  List<String> get descripcionesPendientes => const [];

  /// ¿Esta implementación es la demo local? (La demo añade en el
  /// Perfil el interruptor para simular «sin conexión».)
  bool get esDemo => false;

  /// Simulación de «sin conexión» (solo demo): encendida, nada
  /// se envía y todo queda en la cola hasta apagarla o pulsar
  /// «Sincronizar ahora» con conexión.
  bool get sinConexionSimulada => false;
  Future<void> fijarSinConexionSimulada(bool valor) async {}

  /// Intenta enviar todo lo pendiente. Devuelve cuántos registros
  /// salieron. Si no hay conexión, lanza [ErrorServidor] y la
  /// cola queda intacta.
  Future<int> sincronizarAhora() async => 0;
}

/// Repositorio según la conexión: con el proyecto Supabase de
/// producción configurado en [Conexion], la app trabaja REAL
/// contra el servidor (versión única 1.4.0); la demo local queda
/// solo como respaldo si algún día se vaciara la conexión.
RepositorioTaller crearRepositorio() {
  if (Conexion.hayConexion) {
    return RepositorioReal();
  }
  return RepositorioDemo();
}
