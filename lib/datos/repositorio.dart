import 'package:flutter/foundation.dart';

import '../modelos.dart';
import 'conexion.dart';
import 'repositorio_demo.dart';

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
///  - lavado: marca las guaguas lavadas del día (si la empresa
///    tiene el módulo de lavado activo).
///
/// Implementación actual: [RepositorioDemo] (sin servidor). Cuando
/// exista el proyecto Supabase «taller-neto», se añade la real sin
/// tocar las pantallas (ver datos/conexion.dart).
abstract class RepositorioTaller extends ChangeNotifier {
  Usuario? get sesion;

  /// Entrada con código + PIN. Si entra, la sesión queda guardada en
  /// el teléfono. Si no, lanza [ErrorServidor] con el mensaje.
  Future<Usuario> iniciarSesion(String codigo, String pin);

  /// Al abrir la app: restaura la sesión guardada, si la hay.
  Future<bool> restaurarSesion();

  /// Cierra la sesión y borra la guardada.
  Future<void> cerrarSesion();

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

  // ---------- lavado ----------
  DatosLavado? get datosLavado;
  Future<void> recargarLavado();
  Future<void> marcarLavado(String vehiculoId);
  Future<void> desmarcarLavado(String vehiculoId);

  // ---------- combustible ----------
  DatosCombustible? get datosCombustible;
  Future<void> recargarCombustible();

  /// Registra un despacho. El odómetro no puede ser menor que el
  /// último registrado para ese vehículo (regla del servidor).
  Future<DespachoCombustible> registrarDespacho({
    required String vehiculoId,
    required double galones,
    required String tipo,
    required double odometro,
    required double costoUnitario,
  });
}

/// Repositorio según la conexión: sin proyecto Supabase configurado,
/// demo local completa (ver datos/conexion.dart).
RepositorioTaller crearRepositorio() {
  if (Conexion.hayConexion) {
    // Aquí irá RepositorioReal cuando exista el proyecto (conexion.dart).
    return RepositorioDemo();
  }
  return RepositorioDemo();
}
