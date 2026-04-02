// screens/auth/register_screen.dart

import 'package:flutter/material.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/screens/home/home_screen.dart';
import 'package:mobile/services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey            = GlobalKey<FormState>();
  final _nombreController   = TextEditingController();
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  bool _cargando    = false;
  bool _verPassword = false;
  String? _errorMensaje;

  @override
  void dispose() {
    _nombreController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _registrarse() async {
    setState(() { _errorMensaje = null; _cargando = true; });

    if (!_formKey.currentState!.validate()) {
      setState(() => _cargando = false);
      return;
    }

    final resultado = await AuthService.registro(
      nombre:   _nombreController.text.trim(),
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.of(context).pop(),
          // pop() = volver a la pantalla anterior (Login)
        ),
        title: const Text('Crear cuenta'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Text('Empezá hoy', style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 8),
                Text('Creá tu cuenta y organizá tu día', style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 40),

                TextFormField(
                  controller: _nombreController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Ingresá tu nombre';
                    if (value.trim().length < 2) return 'Nombre muy corto';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Ingresá tu email';
                    if (!value.contains('@')) return 'Email inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _passwordController,
                  obscureText: !_verPassword,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_verPassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _verPassword = !_verPassword),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Ingresá una contraseña';
                    if (value.length < 6) return 'Mínimo 6 caracteres';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                if (_errorMensaje != null)
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

                ElevatedButton(
                  onPressed: _cargando ? null : _registrarse,
                  child: _cargando
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Crear cuenta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
