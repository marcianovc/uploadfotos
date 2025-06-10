import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  Future<String> getApiBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('api_host') ?? '192.168.100.82';
    final port = prefs.getString('api_port') ?? '5000';
    return 'http://$host:$port';
  }

  Future<Map<String, dynamic>> login(String login, String senha) async {
    try {
      final apiBaseUrl = await getApiBaseUrl();
      final response = await http.post(
        Uri.parse('$apiBaseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'login': login, 'senha': senha}),
      );

      final responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        return responseData;
      } else {
        return {
          'success': false,
          'error': responseData['error'] ?? 'Erro desconhecido',
          'error_code': responseData['error_code'] ?? 'UNKNOWN_ERROR',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Erro na conexão: ${e.toString()}',
        'error_code': 'CONNECTION_ERROR',
      };
    }
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }

  Future<bool> isApiConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('api_host') != null &&
        prefs.getString('api_port') != null;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
    await prefs.remove('userLogin');
    
    // Não limpa as credenciais salvas se "Lembrar-me" estiver ativado
    final rememberMe = prefs.getBool('rememberMe') ?? false;
    if (!rememberMe) {
      await prefs.remove('savedLogin');
      await prefs.remove('savedPassword');
    }
  }

  Future<bool> isRememberMeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('rememberMe') ?? false;
  }

  Future<bool> hasSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('savedLogin') != null && 
           prefs.getString('savedPassword') != null;
  }
}
