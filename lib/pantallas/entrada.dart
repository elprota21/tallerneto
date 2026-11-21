import 'package:material_ui/material_ui.dart';

import '../datos/repositorio.dart';
import '../marca.dart';

/// Entrada con código + PIN (mismo sistema que RutaNeto). En modo
/// demo las cuentas son las de la vitrina: MEC-01 / MEC-02 / LAV-01,
/// PIN 1234.
class PantallaEntrada extends StatefulWidget {
  const PantallaEntrada({super.key, required this.repo});

  final RepositorioTaller repo;

  @override
  State<PantallaEntrada> createState() => _PantallaEntradaState();
}

class _PantallaEntradaState extends State<PantallaEntrada> {
  final _codigo = TextEditingController();
  final _pin = TextEditingController();
  bool _entrando = false;
  String? _error;

  Future<void> _entrar() async {
    if (_entrando) return;
    setState(() {
      _entrando = true;
      _error = null;
    });
    try {
      await widget.repo.iniciarSesion(_codigo.text, _pin.text);
      // La raíz escucha el repositorio y cambia a la principal.
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  @override
  void dispose() {
    _codigo.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.build_circle_outlined, size: 72, color: cs.primary),
                  const SizedBox(height: 12),
                  Text(
                    Marca.nombreApp,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    'App del mecánico y del lavado',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _codigo,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Tu código',
                      hintText: 'MEC-01',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    onSubmitted: (_) => _entrar(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'PIN',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                    onSubmitted: (_) => _entrar(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(color: cs.onErrorContainer),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _entrando ? null : _entrar,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(_entrando ? 'Entrando…' : 'ENTRAR'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Demostración (PIN 1234):\n'
                    'MEC-01 · mecánico a destajo\n'
                    'MEC-02 · mecánico con sueldo\n'
                    'LAV-01 · coordinador de lavado\n'
                    'COM-01 · despachador de combustible',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
