import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/auth_state.dart';
import 'server_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await auth.register(_name.text, _email.text, _password.text);
      } else {
        await auth.login(_email.text, _password.text);
      }
      // the router redirects to home once logged in
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.health_and_safety, size: 72, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 12),
                    Text('Helmet Check',
                        textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(_register ? 'Create your account' : 'Sign in to continue',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    if (_register) ...[
                      TextFormField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Name'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _hide,
                      onFieldSubmitted: (_) => _busy ? null : _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _hide = !_hide),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter your password';
                        if (_register && v.length < 8) return 'At least 8 characters';
                        return null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      child: _busy
                          ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_register ? 'Create account' : 'Sign in'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _register = !_register;
                                _error = null;
                              }),
                      child: Text(_register ? 'I already have an account' : 'Create a new account'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await showServerDialog(context, api);
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.dns, size: 18),
                      label: Text('Server: ${api.baseUrl}', overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
