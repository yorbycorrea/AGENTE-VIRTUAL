// screens/auth/login_screen.dart

import 'package:flutter/material.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/screens/auth/register_screen.dart';
import 'package:mobile/screens/home/home_screen.dart';
import 'package:mobile/services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  // StatefulWidget = widget con estado interno que puede cambiar
  // Se usa cuando algo en la pantalla puede cambiar: texto, cargando, errores, etc.
  // StatelessWidget = widget sin estado, solo muestra datos que recibe
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
  // createState crea el objeto de estado separado
  // El "_" al inicio = convención Dart para privado (solo visible en este archivo)
}

class _LoginScreenState extends State<LoginScreen> {
  // Esta clase contiene el estado y la lógica de LoginScreen

  final _formKey        = GlobalKey<FormState>();
  // GlobalKey permite acceder al Form desde afuera del widget
  // Lo usamos para validar todos los campos a la vez

  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  // TextEditingController "escucha" lo que el usuario escribe en un TextField
  // Con .text obtenés el valor actual: _emailController.text

  bool _cargando       = false;
  bool _verPassword    = false;
  String? _errorMensaje;
  // String? = puede ser null (cuando no hay error, es null)

  @override
  void dispose() {
    // dispose se llama cuando la pantalla se destruye (el usuario navega a otra)
    // Liberar controllers evita memory leaks (memoria que nunca se libera)
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesion() async {
    setState(() { _errorMensaje = null; _cargando = true; });

    if (!_formKey.currentState!.validate()) {
      setState(() => _cargando = false);
      return;
    }

    // Llamada real al backend
    final resultado = await AuthService.login(
      email:    _emailController.text.trim(),
      password: _passwordController.text,
    );

    setState(() => _cargando = false);
    if (!mounted) return;

    if (resultado['exito']) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      setState(() => _errorMensaje = resultado['error']);
    }
    // pushReplacement navega a HomeScreen Y elimina LoginScreen de la historia
    // El usuario no puede volver atrás con el botón "back"
    // Tiene sentido: después de loguearse no queremos que vuelva al login
  }

  @override
  Widget build(BuildContext context) {
    // build() describe cómo se ve la pantalla
    // Flutter lo llama cada vez que setState() se ejecuta
    // "context" = información sobre dónde está este widget en el árbol

    return Scaffold(
      // Scaffold = estructura básica de una pantalla
      // Provee: fondo, AppBar, body, FloatingActionButton, BottomBar, etc.
      body: SafeArea(
        // SafeArea evita que el contenido quede detrás de la cámara o la barra de notificaciones
        child: SingleChildScrollView(
          // SingleChildScrollView permite hacer scroll cuando el teclado aparece
          // y empuja el contenido hacia arriba
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              // CrossAxisAlignment.start = alinea los hijos a la izquierda
              children: [
                const SizedBox(height: 48),
                // SizedBox es simplemente un espacio vacío con un tamaño fijo

                // ── Ícono / logo ────────────────────────────────────────
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppTheme.primario.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.primario,
                    size: 36,
                  ),
                ),

                const SizedBox(height: 32),

                // ── Títulos ──────────────────────────────────────────────
                Text('Bienvenido', style: Theme.of(context).textTheme.headlineLarge),
                // Theme.of(context) accede al tema global definido en AppTheme
                const SizedBox(height: 8),
                Text(
                  'Iniciá sesión para ver tu agenda',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),

                const SizedBox(height: 40),

                // ── Campo email ──────────────────────────────────────────
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  // Muestra el teclado con @, .com, etc.
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    // validator se ejecuta cuando llamás _formKey.currentState!.validate()
                    // Si devuelve String → muestra ese texto como error
                    // Si devuelve null  → campo válido
                    if (value == null || value.isEmpty) return 'Ingresá tu email';
                    if (!value.contains('@'))            return 'Email inválido';
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // ── Campo contraseña ─────────────────────────────────────
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_verPassword,
                  // obscureText: true = muestra *** en lugar del texto
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      // Botón para mostrar/ocultar la contraseña
                      icon: Icon(_verPassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _verPassword = !_verPassword),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Ingresá tu contraseña';
                    if (value.length < 6) return 'Mínimo 6 caracteres';
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // ── Mensaje de error ─────────────────────────────────────
                if (_errorMensaje != null)
                // "if" dentro del árbol de widgets — si es null, no se renderiza nada
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.peligro.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppTheme.peligro, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_errorMensaje!, style: const TextStyle(color: AppTheme.peligro))),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),

                // ── Botón de login ───────────────────────────────────────
                ElevatedButton(
                  onPressed: _cargando ? null : _iniciarSesion,
                  // Si está cargando, onPressed = null → botón desactivado
                  child: _cargando
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Iniciar sesión'),
                ),

                const SizedBox(height: 24),

                // ── Link a registro ──────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('¿No tenés cuenta?', style: Theme.of(context).textTheme.bodyMedium),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RegisterScreen()),
                      ),
                      child: const Text('Registrate', style: TextStyle(color: AppTheme.primario)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
