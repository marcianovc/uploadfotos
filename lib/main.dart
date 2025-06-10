import 'package:flutter/material.dart';
import 'package:uploadfotos/screens/vendas_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Verifica status de login e credenciais
  final authService = AuthService();
  final isLoggedIn = await authService.isLoggedIn();
  final rememberMe = await authService.isRememberMeEnabled();
  final hasSavedCredentials = await authService.hasSavedCredentials();

  runApp(MyApp(
    initialRoute: (isLoggedIn || (rememberMe && hasSavedCredentials)) 
        ? '/vendas' 
        : '/login',
  ));
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Controle de Canhotos',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      initialRoute: initialRoute,
      routes: {
        '/login': (context) => const LoginScreen(),
        '/vendas': (context) => const VendasScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
