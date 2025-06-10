import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import 'api_config_screen.dart';
import 'vendas_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _senhaController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  String _errorMessage = '';
  String _apiConfigStatus = '';

  @override
  void initState() {
    super.initState();
    _checkApiConfig();
    _loadSavedCredentials();
    _loginController.addListener(_formatarDocumento);
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLogin = prefs.getString('savedLogin');
    final savedPassword = prefs.getString('savedPassword');
    final rememberMe = prefs.getBool('rememberMe') ?? false;

    if (rememberMe && savedLogin != null && savedPassword != null) {
      setState(() {
        _loginController.text = savedLogin;
        _senhaController.text = savedPassword;
        _rememberMe = true;
      });
    }
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('savedLogin', _loginController.text);
      await prefs.setString('savedPassword', _senhaController.text);
      await prefs.setBool('rememberMe', true);
    } else {
      await prefs.remove('savedLogin');
      await prefs.remove('savedPassword');
      await prefs.setBool('rememberMe', false);
    }
  }

  Future<void> _checkApiConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('api_host');
    final port = prefs.getString('api_port');

    setState(() {
      if (host == null || port == null) {
        _apiConfigStatus = 'Configuração da API não definida';
      } else {
        _apiConfigStatus = 'API: http://$host:$port';
      }
    });
  }

  @override
  void dispose() {
    _loginController.removeListener(_formatarDocumento);
    _loginController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  void _formatarDocumento() {
    final text = _loginController.text.replaceAll(RegExp(r'[^0-9]'), '');
    String formattedText = '';

    if (text.length <= 11) { // CPF
      if (text.length > 3) {
        formattedText += '${text.substring(0, 3)}.';
        if (text.length > 6) {
          formattedText += '${text.substring(3, 6)}.';
          if (text.length > 9) {
            formattedText += '${text.substring(6, 9)}-';
            formattedText += text.substring(9);
          } else {
            formattedText += text.substring(6);
          }
        } else {
          formattedText += text.substring(3);
        }
      } else {
        formattedText = text;
      }
    } else { // CNPJ
      if (text.length > 2) {
        formattedText += '${text.substring(0, 2)}.';
        if (text.length > 5) {
          formattedText += '${text.substring(2, 5)}.';
          if (text.length > 8) {
            formattedText += '${text.substring(5, 8)}/';
            if (text.length > 12) {
              formattedText += '${text.substring(8, 12)}-';
              formattedText += text.substring(12);
            } else {
              formattedText += text.substring(8);
            }
          } else {
            formattedText += text.substring(5);
          }
        } else {
          formattedText += text.substring(2);
        }
      } else {
        formattedText = text;
      }
    }

    if (_loginController.text != formattedText) {
      _loginController.value = _loginController.value.copyWith(
        text: formattedText,
        selection: TextSelection.collapsed(offset: formattedText.length),
      );
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('api_host');
    final port = prefs.getString('api_port');

    if (host == null || port == null) {
      setState(() {
        _errorMessage = 'Configure o host e porta da API antes de fazer login';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final authService = AuthService();
      final login = _loginController.text.trim();
      final senha = _senhaController.text.trim();

      // Salva as credenciais se "Lembrar-me" estiver ativado
      await _saveCredentials();

      final response = await authService.login(login, senha);

      if (response['success'] == true) {
        // Salva o status de login
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('userLogin', login);

        // Navega para a tela principal
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const VendasScreen()),
          );
        }
      } else {
        setState(() {
          _errorMessage =
              response['error'] ?? 'Erro desconhecido ao fazer login';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro na conexão: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openApiConfig() async {
    final configUpdated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const ApiConfigScreen()),
    );

    if (configUpdated == true) {
      await _checkApiConfig();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                /* Image.asset(
                  'assets/logo.png', // Substitua pelo caminho da sua logo
                  height: 120,
                ), */
                const SizedBox(height: 32),
                const Text(
                  'Controle de Canhotos',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  _apiConfigStatus,
                  style: TextStyle(
                    color: _apiConfigStatus.contains('não definida')
                        ? Colors.orange
                        : Colors.green,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _loginController,
                  decoration: const InputDecoration(
                    labelText: 'CPF/CNPJ',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                    hintText: '000.000.000-00 ou 00.000.000/0000-00',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    // Remove todos os caracteres não numéricos antes de validar
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                  ],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, informe seu CPF/CNPJ';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _senhaController,
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, informe sua senha';
                    }
                    return null;
                  },
                ),
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: _rememberMe,
                      onChanged: (value) {
                        setState(() {
                          _rememberMe = value ?? false;
                        });
                      },
                    ),
                    const Text('Lembrar login e senha'),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          )
                        : const Text('Entrar', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _openApiConfig,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.settings, size: 18),
                      SizedBox(width: 8),
                      Text('Configurar API'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
