/// Modelos de la app — espejo de las respuestas del servidor
/// (servidor/trabajos.sql: pr_datos_mecanico; servidor/lavado.sql:
/// pr_datos_lavado). En modo demo los produce el repositorio local
/// con la misma forma.
library;

class Usuario {
  const Usuario({
    required this.id,
    required this.nombre,
    required this.codigo,
    required this.rol,
    this.modoPago = 'destajo',
    this.sueldoMonto,
  });

  final String id;
  final String nombre;
  final String codigo;

  /// 'mecanico' | 'lavado' (la app también la usa administración en
  /// pruebas, pero sus pantallas son estas dos).
  final String rol;

  /// Solo mecánicos: 'destajo' (cobra la suma de trabajos validados)
  /// o 'sueldo' (salario fijo mensual).
  final String modoPago;
  final double? sueldoMonto;

  bool get esSueldo => modoPago == 'sueldo';
  bool get esLavado => rol == 'lavado';
  bool get esCombustible => rol == 'combustible';

  factory Usuario.desdeJson(Map<String, dynamic> j) => Usuario(
        id: j['id'].toString(),
        nombre: j['nombre'].toString(),
        codigo: j['codigo'].toString(),
        rol: j['rol'].toString(),
        modoPago: j['modoPago']?.toString() ?? 'destajo',
        sueldoMonto: (j['sueldoMonto'] as num?)?.toDouble(),
      );
}

class Empresa {
  const Empresa({
    required this.id,
    required this.nombre,
    this.lavadoActivo = false,
    this.combustibleActivo = false,
  });

  final String id;
  final String nombre;

  /// Módulo de lavado (extra por empresa): apagado = la app no
  /// muestra nada de lavado.
  final bool lavadoActivo;

  /// Módulo de combustible (extra por empresa): ídem.
  final bool combustibleActivo;

  factory Empresa.desdeJson(Map<String, dynamic> j) => Empresa(
        id: j['id'].toString(),
        nombre: j['nombre'].toString(),
        lavadoActivo: j['lavadoActivo'] == true,
        combustibleActivo: j['combustibleActivo'] == true,
      );
}

class Vehiculo {
  const Vehiculo({
    required this.id,
    required this.codigo,
    required this.placa,
    required this.marca,
    required this.modelo,
    this.anio,
    this.activo = true,
  });

  final String id;
  final String codigo;
  final String placa;
  final String marca;
  final String modelo;
  final int? anio;
  final bool activo;

  String get etiqueta => '$codigo · $marca $modelo ($placa)';

  factory Vehiculo.desdeJson(Map<String, dynamic> j) => Vehiculo(
        id: j['id'].toString(),
        codigo: j['codigo'].toString(),
        placa: j['placa'].toString(),
        marca: j['marca'].toString(),
        modelo: j['modelo'].toString(),
        anio: (j['anio'] as num?)?.toInt(),
        activo: j['activo'] != false,
      );
}

class Pieza {
  const Pieza({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.stock,
    this.costo = 0,
  });

  final String id;
  final String codigo;
  final String nombre;
  final int stock;
  final double costo;

  String get etiqueta => '$codigo · $nombre';

  factory Pieza.desdeJson(Map<String, dynamic> j) => Pieza(
        id: j['id'].toString(),
        codigo: j['codigo'].toString(),
        nombre: j['nombre'].toString(),
        stock: (j['stock'] as num?)?.toInt() ?? 0,
        costo: (j['costo'] as num?)?.toDouble() ?? 0,
      );
}

class TipoTrabajo {
  const TipoTrabajo({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.precioManoObra,
  });

  final String id;
  final String codigo;
  final String nombre;

  /// Lo que cobra el mecánico de destajo cuando el trabajo se valida.
  final double precioManoObra;

  factory TipoTrabajo.desdeJson(Map<String, dynamic> j) => TipoTrabajo(
        id: j['id'].toString(),
        codigo: j['codigo'].toString(),
        nombre: j['nombre'].toString(),
        precioManoObra: (j['precioManoObra'] as num?)?.toDouble() ?? 0,
      );
}

class PiezaUsada {
  const PiezaUsada({required this.piezaId, required this.cantidad});

  final String piezaId;
  final int cantidad;

  Map<String, dynamic> aJson() => {'piezaId': piezaId, 'cantidad': cantidad};

  factory PiezaUsada.desdeJson(Map<String, dynamic> j) => PiezaUsada(
        piezaId: j['piezaId'].toString(),
        cantidad: (j['cantidad'] as num?)?.toInt() ?? 1,
      );
}

/// Trabajo registrado por el mecánico. Nace 'pendiente'; solo cuenta
/// para el pago (destajo) cuando administración lo pasa a 'validada'.
class Trabajo {
  const Trabajo({
    required this.id,
    required this.vehiculoId,
    required this.tipoTrabajoId,
    required this.tipoNombre,
    required this.precio,
    required this.estado,
    required this.fecha,
    this.descripcion,
    this.notaAdmin,
    this.piezas = const [],
  });

  final String id;
  final String vehiculoId;
  final String tipoTrabajoId;
  final String tipoNombre;

  /// Precio del catálogo AL REGISTRAR (copia): no cambia si la
  /// administración edita el catálogo después.
  final double precio;

  /// 'pendiente' | 'validada' | 'rechazada'
  final String estado;

  /// yyyy-mm-dd
  final String fecha;
  final String? descripcion;

  /// Motivo del rechazo (lo escribe administración; el mecánico lo ve).
  final String? notaAdmin;
  final List<PiezaUsada> piezas;

  factory Trabajo.desdeJson(Map<String, dynamic> j) => Trabajo(
        id: j['id'].toString(),
        vehiculoId: j['vehiculoId'].toString(),
        tipoTrabajoId: j['tipoTrabajoId'].toString(),
        tipoNombre: j['tipoNombre']?.toString() ?? '',
        precio: (j['precio'] as num?)?.toDouble() ?? 0,
        estado: j['estado'].toString(),
        fecha: j['fecha'].toString(),
        descripcion: j['descripcion']?.toString(),
        notaAdmin: j['notaAdmin']?.toString(),
        piezas: ((j['piezas'] as List?) ?? const [])
            .map((p) => PiezaUsada.desdeJson(p as Map<String, dynamic>))
            .toList(),
      );
}

/// Todo lo que la app del mecánico necesita (pr_datos_mecanico).
class DatosMecanico {
  const DatosMecanico({
    required this.usuario,
    required this.empresa,
    required this.tiposTrabajo,
    required this.vehiculos,
    required this.piezas,
    required this.trabajos,
    required this.totalValidadoMes,
    required this.totalPendienteMes,
    this.solicitudes = const [],
  });

  final Usuario usuario;
  final Empresa empresa;
  final List<TipoTrabajo> tiposTrabajo;
  final List<Vehiculo> vehiculos;
  final List<Pieza> piezas;
  final List<Trabajo> trabajos;

  /// Mis solicitudes de piezas, con su estado (solo las propias).
  final List<SolicitudPieza> solicitudes;

  /// Suma de precios de trabajos VALIDADOS del mes (lo que lleva
  /// ganado un mecánico de destajo).
  final double totalValidadoMes;

  /// Suma de precios de trabajos PENDIENTES del mes (en revisión).
  final double totalPendienteMes;

  factory DatosMecanico.desdeJson(Map<String, dynamic> j) => DatosMecanico(
        usuario: Usuario.desdeJson(j['mecanico'] as Map<String, dynamic>),
        empresa: Empresa.desdeJson(j['empresa'] as Map<String, dynamic>),
        tiposTrabajo: ((j['tiposTrabajo'] as List?) ?? const [])
            .map((t) => TipoTrabajo.desdeJson(t as Map<String, dynamic>))
            .toList(),
        vehiculos: ((j['vehiculos'] as List?) ?? const [])
            .map((v) => Vehiculo.desdeJson(v as Map<String, dynamic>))
            .toList(),
        piezas: ((j['piezas'] as List?) ?? const [])
            .map((p) => Pieza.desdeJson(p as Map<String, dynamic>))
            .toList(),
        trabajos: ((j['trabajos'] as List?) ?? const [])
            .map((t) => Trabajo.desdeJson(t as Map<String, dynamic>))
            .toList(),
        totalValidadoMes: (j['totalValidadoMes'] as num?)?.toDouble() ?? 0,
        totalPendienteMes: (j['totalPendienteMes'] as num?)?.toDouble() ?? 0,
        solicitudes: ((j['solicitudes'] as List?) ?? const [])
            .map((s) => SolicitudPieza.desdeJson(s as Map<String, dynamic>))
            .toList(),
      );
}

/// Un vehículo en la lista de lavado de hoy (pr_datos_lavado).
class VehiculoLavado {
  const VehiculoLavado({
    required this.vehiculo,
    required this.lavadoHoy,
    this.marcadaEn,
    this.marcadaPorNombre,
  });

  final Vehiculo vehiculo;
  final bool lavadoHoy;

  /// ISO con hora de cuándo se marcó (si está lavada).
  final String? marcadaEn;
  final String? marcadaPorNombre;

  factory VehiculoLavado.desdeJson(Map<String, dynamic> j) => VehiculoLavado(
        vehiculo: Vehiculo.desdeJson(j),
        lavadoHoy: j['lavadoHoy'] == true,
        marcadaEn: j['marcadaEn']?.toString(),
        marcadaPorNombre: j['marcadaPorNombre']?.toString(),
      );
}

/// Tipo de combustible con su precio sugerido por galón (RD$).
class TipoCombustible {
  const TipoCombustible({required this.tipo, required this.precioSugerido});

  /// 'diesel' | 'gasolina' | 'glp'
  final String tipo;
  final double precioSugerido;

  String get etiqueta => switch (tipo) {
        'diesel' => 'Diésel',
        'gasolina' => 'Gasolina',
        'glp' => 'GLP',
        _ => tipo,
      };

  factory TipoCombustible.desdeJson(Map<String, dynamic> j) => TipoCombustible(
        tipo: j['tipo'].toString(),
        precioSugerido: (j['precioSugerido'] as num?)?.toDouble() ?? 0,
      );
}

/// Un despacho de combustible registrado por el despachador.
class DespachoCombustible {
  const DespachoCombustible({
    required this.id,
    required this.vehiculoId,
    required this.vehiculoCodigo,
    required this.galones,
    required this.tipo,
    required this.odometro,
    required this.costoUnitario,
    required this.total,
    required this.fecha,
    required this.creadaEn,
    this.despachadorNombre,
  });

  final String id;
  final String vehiculoId;
  final String vehiculoCodigo;
  final double galones;

  /// 'diesel' | 'gasolina' | 'glp'
  final String tipo;
  final double odometro;

  /// Costo por galón al despachar.
  final double costoUnitario;
  final double total;

  /// yyyy-mm-dd
  final String fecha;

  /// ISO con hora.
  final String creadaEn;
  final String? despachadorNombre;

  String get tipoEtiqueta => TipoCombustible(tipo: tipo, precioSugerido: 0).etiqueta;

  factory DespachoCombustible.desdeJson(Map<String, dynamic> j) =>
      DespachoCombustible(
        id: j['id'].toString(),
        vehiculoId: j['vehiculoId'].toString(),
        vehiculoCodigo: j['vehiculoCodigo']?.toString() ?? '',
        galones: (j['galones'] as num?)?.toDouble() ?? 0,
        tipo: j['tipo'].toString(),
        odometro: (j['odometro'] as num?)?.toDouble() ?? 0,
        costoUnitario: (j['costoUnitario'] as num?)?.toDouble() ?? 0,
        total: (j['total'] as num?)?.toDouble() ?? 0,
        fecha: j['fecha']?.toString() ?? '',
        creadaEn: j['creadaEn']?.toString() ?? '',
        despachadorNombre: j['despachadorNombre']?.toString(),
      );
}

/// Estado del tanque de la empresa para un tipo de combustible
/// (servidor/tanque.sql): saldo = recepciones − despachos, umbral
/// de «poco combustible», alerta y días estimados de alcance.
class TanqueTipo {
  const TanqueTipo({
    required this.tipo,
    required this.saldo,
    required this.umbral,
    required this.alerta,
    this.consumoPromedioDiario,
    this.diasEstimados,
  });

  /// 'diesel' | 'gasolina' | 'glp'
  final String tipo;
  final double saldo;
  final double umbral;
  final bool alerta;
  final double? consumoPromedioDiario;

  /// Días que alcanza el saldo al ritmo de consumo reciente;
  /// null si no hubo consumo en los últimos 14 días.
  final double? diasEstimados;

  String get etiqueta => TipoCombustible(tipo: tipo, precioSugerido: 0).etiqueta;

  factory TanqueTipo.desdeJson(Map<String, dynamic> j) => TanqueTipo(
        tipo: j['tipo'].toString(),
        saldo: (j['saldo'] as num?)?.toDouble() ?? 0,
        umbral: (j['umbral'] as num?)?.toDouble() ?? 0,
        alerta: j['alerta'] == true,
        consumoPromedioDiario: (j['consumoPromedioDiario'] as num?)?.toDouble(),
        diasEstimados: (j['diasEstimados'] as num?)?.toDouble(),
      );
}

/// Una recepción de combustible: la carga que entró al tanque
/// (la registra el despachador; suma al saldo del tipo).
class RecepcionCombustible {
  const RecepcionCombustible({
    required this.id,
    required this.tipo,
    required this.galones,
    required this.costoUnitario,
    required this.total,
    required this.fecha,
    required this.creadaEn,
    this.proveedor,
    this.nota,
  });

  final String id;

  /// 'diesel' | 'gasolina' | 'glp'
  final String tipo;
  final double galones;
  final double costoUnitario;
  final double total;
  final String? proveedor;
  final String? nota;

  /// yyyy-mm-dd
  final String fecha;

  /// ISO con hora.
  final String creadaEn;

  String get tipoEtiqueta => TipoCombustible(tipo: tipo, precioSugerido: 0).etiqueta;

  factory RecepcionCombustible.desdeJson(Map<String, dynamic> j) =>
      RecepcionCombustible(
        id: j['id'].toString(),
        tipo: j['tipo'].toString(),
        galones: (j['galones'] as num?)?.toDouble() ?? 0,
        costoUnitario: (j['costoUnitario'] as num?)?.toDouble() ?? 0,
        total: (j['total'] as num?)?.toDouble() ?? 0,
        proveedor: j['proveedor']?.toString(),
        nota: j['nota']?.toString(),
        fecha: j['fecha']?.toString() ?? '',
        creadaEn: j['creadaEn']?.toString() ?? '',
      );
}

/// Solicitud de pieza de un mecánico (servidor/solicitudes.sql).
/// Flujo: 'pendiente' → 'pedida' → 'recibida' / 'rechazada'.
/// Al recibirse, el stock entra solo al inventario.
class SolicitudPieza {
  const SolicitudPieza({
    required this.id,
    required this.nombrePieza,
    required this.cantidad,
    required this.urgencia,
    required this.estado,
    required this.fecha,
    required this.creadaEn,
    this.piezaId,
    this.vehiculoId,
    this.nota,
    this.notaAdmin,
    this.cantidadRecibida,
    this.costoRecibido,
  });

  final String id;

  /// Pieza del catálogo si se eligió una; null = texto libre.
  final String? piezaId;
  final String nombrePieza;
  final int cantidad;
  final String? vehiculoId;

  /// 'normal' | 'urgente'
  final String urgencia;
  final String? nota;

  /// 'pendiente' | 'pedida' | 'recibida' | 'rechazada'
  final String estado;

  /// Motivo del rechazo (lo escribe administración; el mecánico lo ve).
  final String? notaAdmin;
  final int? cantidadRecibida;
  final double? costoRecibido;

  /// yyyy-mm-dd
  final String fecha;

  /// ISO con hora.
  final String creadaEn;

  bool get esUrgente => urgencia == 'urgente';

  factory SolicitudPieza.desdeJson(Map<String, dynamic> j) => SolicitudPieza(
        id: j['id'].toString(),
        piezaId: j['piezaId']?.toString(),
        nombrePieza: j['nombrePieza'].toString(),
        cantidad: (j['cantidad'] as num?)?.toInt() ?? 1,
        vehiculoId: j['vehiculoId']?.toString(),
        urgencia: j['urgencia']?.toString() ?? 'normal',
        nota: j['nota']?.toString(),
        estado: j['estado'].toString(),
        notaAdmin: j['notaAdmin']?.toString(),
        cantidadRecibida: (j['cantidadRecibida'] as num?)?.toInt(),
        costoRecibido: (j['costoRecibido'] as num?)?.toDouble(),
        fecha: j['fecha']?.toString() ?? '',
        creadaEn: j['creadaEn']?.toString() ?? '',
      );
}

/// Un vehículo en la vista del despachador, con su último odómetro.
class VehiculoCombustible {
  const VehiculoCombustible({required this.vehiculo, this.ultimoOdometro});

  final Vehiculo vehiculo;

  /// Último odómetro registrado (el nuevo despacho no puede bajar
  /// de aquí); null si nunca ha despachado.
  final double? ultimoOdometro;

  factory VehiculoCombustible.desdeJson(Map<String, dynamic> j) =>
      VehiculoCombustible(
        vehiculo: Vehiculo.desdeJson(j),
        ultimoOdometro: (j['ultimoOdometro'] as num?)?.toDouble(),
      );
}

/// Todo lo que la app del despachador de combustible necesita
/// (pr_datos_combustible).
class DatosCombustible {
  const DatosCombustible({
    required this.usuario,
    required this.empresa,
    required this.fecha,
    required this.tipos,
    required this.vehiculos,
    required this.despachosHoy,
    required this.totalGalonesHoy,
    required this.totalCostoHoy,
    this.tanque = const [],
  });

  final Usuario usuario;
  final Empresa empresa;

  /// yyyy-mm-dd (hoy, hora RD en el servidor).
  final String fecha;
  final List<TipoCombustible> tipos;
  final List<VehiculoCombustible> vehiculos;
  final List<DespachoCombustible> despachosHoy;
  final double totalGalonesHoy;
  final double totalCostoHoy;

  /// Inventario del tanque por tipo (saldo, umbral, alerta, días).
  final List<TanqueTipo> tanque;

  factory DatosCombustible.desdeJson(Map<String, dynamic> j) => DatosCombustible(
        usuario: Usuario.desdeJson(j['usuario'] as Map<String, dynamic>),
        empresa: Empresa.desdeJson(j['empresa'] as Map<String, dynamic>),
        fecha: j['fecha'].toString(),
        tipos: ((j['tipos'] as List?) ?? const [])
            .map((t) => TipoCombustible.desdeJson(t as Map<String, dynamic>))
            .toList(),
        tanque: ((j['tanque'] as List?) ?? const [])
            .map((t) => TanqueTipo.desdeJson(t as Map<String, dynamic>))
            .toList(),
        vehiculos: ((j['vehiculos'] as List?) ?? const [])
            .map((v) => VehiculoCombustible.desdeJson(v as Map<String, dynamic>))
            .toList(),
        despachosHoy: ((j['despachosHoy'] as List?) ?? const [])
            .map((d) => DespachoCombustible.desdeJson(d as Map<String, dynamic>))
            .toList(),
        totalGalonesHoy: (j['totalGalonesHoy'] as num?)?.toDouble() ?? 0,
        totalCostoHoy: (j['totalCostoHoy'] as num?)?.toDouble() ?? 0,
      );
}

/// Todo lo que la app del coordinador de lavado necesita.
class DatosLavado {
  const DatosLavado({
    required this.usuario,
    required this.empresa,
    required this.fecha,
    required this.vehiculos,
  });

  final Usuario usuario;
  final Empresa empresa;

  /// yyyy-mm-dd (hoy, hora RD en el servidor).
  final String fecha;
  final List<VehiculoLavado> vehiculos;

  int get lavadas => vehiculos.where((v) => v.lavadoHoy).length;
  int get total => vehiculos.length;
  List<VehiculoLavado> get faltan => vehiculos.where((v) => !v.lavadoHoy).toList();

  factory DatosLavado.desdeJson(Map<String, dynamic> j) => DatosLavado(
        usuario: Usuario.desdeJson(j['usuario'] as Map<String, dynamic>),
        empresa: Empresa.desdeJson(j['empresa'] as Map<String, dynamic>),
        fecha: j['fecha'].toString(),
        vehiculos: ((j['vehiculos'] as List?) ?? const [])
            .map((v) => VehiculoLavado.desdeJson(v as Map<String, dynamic>))
            .toList(),
      );
}
