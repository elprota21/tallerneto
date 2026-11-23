import 'package:flutter_test/flutter_test.dart';
import 'package:tallerneto_mecanico/servicios/borrador.dart';

/// Pruebas del BORRADOR LOCAL del trabajo (1.5.0): el modelo
/// debe viajar a JSON y volver igual, y un formulario vacío no
/// debe contar como borrador.
void main() {
  group('BorradorTrabajo', () {
    test('ida y vuelta por JSON conserva todo', () {
      const original = BorradorTrabajo(
        usuarioId: 'usr-1',
        vehiculoId: 'veh-3',
        tipoTrabajoId: 'tip-2',
        piezas: {'pza-1': 2, 'pza-5': 1},
        descripcion: 'Pastillas delanteras',
        paso: 3,
        guardadoEn: '2026-11-23T08:15:00.000',
      );
      final vuelta = BorradorTrabajo.desdeJson(original.aJson());
      expect(vuelta.usuarioId, original.usuarioId);
      expect(vuelta.vehiculoId, original.vehiculoId);
      expect(vuelta.tipoTrabajoId, original.tipoTrabajoId);
      expect(vuelta.piezas, original.piezas);
      expect(vuelta.descripcion, original.descripcion);
      expect(vuelta.paso, original.paso);
      expect(vuelta.guardadoEn, original.guardadoEn);
      expect(vuelta.tieneContenido, isTrue);
    });

    test('un formulario vacío no tiene contenido', () {
      const vacio = BorradorTrabajo(usuarioId: 'usr-1');
      expect(vacio.tieneContenido, isFalse);
      const soloEspacios =
          BorradorTrabajo(usuarioId: 'usr-1', descripcion: '   ');
      expect(soloEspacios.tieneContenido, isFalse);
    });

    test('solo la descripción ya es contenido retomable', () {
      const b = BorradorTrabajo(
          usuarioId: 'usr-1', descripcion: 'Revisar la correa');
      expect(b.tieneContenido, isTrue);
    });

    test('desdeJson tolera un JSON mínimo', () {
      final b = BorradorTrabajo.desdeJson({'usuarioId': 'usr-9'});
      expect(b.usuarioId, 'usr-9');
      expect(b.piezas, isEmpty);
      expect(b.paso, 0);
      expect(b.tieneContenido, isFalse);
    });
  });
}
