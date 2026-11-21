import 'package:material_ui/material_ui.dart';

/// Dinero en pesos dominicanos: RD$1,700.00 (como el panel).
String dinero(double n) {
  final partes = n.toStringAsFixed(2).split('.');
  final entera = partes[0];
  final buf = StringBuffer();
  for (var i = 0; i < entera.length; i++) {
    if (i > 0 && (entera.length - i) % 3 == 0) buf.write(',');
    buf.write(entera[i]);
  }
  return 'RD\$$buf.${partes[1]}';
}

/// yyyy-mm-dd → dd/mm/yyyy.
String fechaCorta(String iso) {
  final p = iso.split('-');
  if (p.length != 3) return iso;
  return '${p[2]}/${p[1]}/${p[0]}';
}

const _dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// yyyy-mm-dd → «viernes 20 de noviembre».
String fechaLarga(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${_dias[d.weekday - 1]} ${d.day} de ${_meses[d.month - 1]}';
}

/// ISO con hora → «7:15 a. m.».
String horaCorta(String? iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final ampm = d.hour >= 12 ? 'p. m.' : 'a. m.';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} $ampm';
}

/// Galones sin ceros de más: 391 → «391», 40.5 → «40.5».
String galones(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  var s = v.toStringAsFixed(2);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}

/// Etiqueta de estado de una solicitud de pieza, con color.
class ChipEstadoSolicitud extends StatelessWidget {
  const ChipEstadoSolicitud({super.key, required this.estado});

  /// 'pendiente' | 'pedida' | 'recibida' | 'rechazada'
  final String estado;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (Color fondo, Color texto, String etiqueta) = switch (estado) {
      'recibida' => (Colors.green.withValues(alpha: 0.15), Colors.green.shade800, 'Recibida'),
      'rechazada' => (cs.errorContainer, cs.onErrorContainer, 'Rechazada'),
      'pedida' => (Colors.blue.withValues(alpha: 0.15), Colors.blue.shade800, 'En pedido'),
      _ => (Colors.amber.withValues(alpha: 0.18), Colors.amber.shade900, 'Pendiente'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        etiqueta,
        style: TextStyle(color: texto, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

/// Etiqueta de estado de un trabajo, con color.
class ChipEstadoTrabajo extends StatelessWidget {
  const ChipEstadoTrabajo({super.key, required this.estado});

  final String estado;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (Color fondo, Color texto, String etiqueta) = switch (estado) {
      'validada' => (Colors.green.withValues(alpha: 0.15), Colors.green.shade800, 'Validada'),
      'rechazada' => (cs.errorContainer, cs.onErrorContainer, 'Rechazada'),
      _ => (Colors.amber.withValues(alpha: 0.18), Colors.amber.shade900, 'Pendiente'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        etiqueta,
        style: TextStyle(color: texto, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

/// Saludo según la hora del día.
String saludo() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Buenos días';
  if (h < 19) return 'Buenas tardes';
  return 'Buenas noches';
}
