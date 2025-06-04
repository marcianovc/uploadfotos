import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import '../models/venda_model.dart';
import '../services/database_helper.dart';
import '../services/image_service.dart';

class VendasScreen extends StatefulWidget {
  const VendasScreen({super.key});

  @override
  _VendasScreenState createState() => _VendasScreenState();
}

class _VendasScreenState extends State<VendasScreen> {
  List<Venda> vendas = [];
  bool isLoading = true;
  late DatabaseHelper _dbHelper;
  final _imageService = ImageService();

  @override
  void initState() {
    super.initState();
    _dbHelper = DatabaseHelper(
      apiBaseUrl: 'http://192.168.100.245:5000', // URL da sua API Python
    );
    _carregarVendas();
  }

  /* Future<void> _carregarVendas() async {
    setState(() => isLoading = true);

    try {
      final params = {
        'filial': 100,
        'distribuidor': 75208,
        'data_inicial': "01.05.2025",
        'data_final': "31.05.2025",
        'status': 'Todas',
      };

      final results = await _dbHelper.executarConsulta(params);
      setState(() {
        vendas = results.map((e) => Venda.fromMap(e)).toList();
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint('Vendas Screen - Erro ao carregar vendas: $e');
      _mostrarSnackBar('Vendas Screen - Erro ao carregar vendas: $e');
    }
  }
 */

  Future<void> _carregarVendas() async {
    setState(() => isLoading = true);

    try {
      final results = await _dbHelper.consultarVendasCanhotos(
        codFilial: 100, // Substitua pelos valores reais
        codVendedor: 75278, // 0 para todos os vendedores
        dataInicio: '01.05.2025', // ou '2023-01-01'
        dataFim: '31.05.2025', // ou '2023-12-31'
        filtroCanhotos: 'Todas', // 'Todas', 'Com Canhotos' ou 'Sem Canhotos'
      );

      setState(() {
        vendas = results.map((e) => Venda.fromMap(e)).toList();
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao carregar vendas: $e')));
    }
  }

  Future<void> _anexarFoto(Venda venda) async {
    final pickedFile = await _imageService.capturarFoto();

    if (pickedFile != null) {
      try {
        setState(() => isLoading = true);

        // Envia a foto diretamente para a API
        await _dbHelper.atualizarAnexo(venda.vendaId, pickedFile);

        // Recarregar a lista
        await _carregarVendas();

        _mostrarSnackBar('Foto anexada com sucesso!');
      } catch (e) {
        setState(() => isLoading = false);
        _mostrarSnackBar('Erro ao anexar foto: $e');
      }
    }
  }

  void _mostrarSnackBar(String mensagem) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  void _visualizarAnexo(String? arquivo) {
    if (arquivo != null) {
      // Implementar visualização do anexo
      // Pode ser um Dialog com a imagem ou navegação para outra tela
      print('Visualizar anexo: $arquivo');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Vendas - Canhotos'),
        actions: [
          IconButton(icon: Icon(Icons.refresh), onPressed: _carregarVendas),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (vendas.isEmpty) {
      return Center(child: Text('Nenhuma venda encontrada'));
    }

    return ListView.builder(
      itemCount: vendas.length,
      itemBuilder: (context, index) => _buildVendaItem(vendas[index]),
    );
  }

  Widget _buildVendaItem(Venda venda) {
    return Slidable(
      key: Key(venda.vendaId.toString()),
      endActionPane: venda.status == 'Sem Canhoto Assinado'
          ? ActionPane(
              motion: const ScrollMotion(),
              children: [
                SlidableAction(
                  onPressed: (_) => _anexarFoto(venda),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  icon: Icons.camera_alt,
                  label: 'Anexar Foto',
                ),
              ],
            )
          : null,
      child: ListTile(
        title: Text('NF: ${venda.numNf} - ${venda.razaoSocial}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vendedor: ${venda.nomeVendedor}'),
            Text('Data: ${DateFormat('dd/MM/yyyy').format(venda.dataComp)}'),
            Text(
              'Valor: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(venda.totalVenda)}',
            ),
            Text(
              'Status: ${venda.status}',
              style: TextStyle(
                color: venda.status == 'Sem Canhoto Assinado'
                    ? Colors.red
                    : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        trailing: venda.arquivo != null
            ? IconButton(
                icon: Icon(Icons.photo, color: Colors.blue),
                onPressed: () => _visualizarAnexo(venda.arquivo),
              )
            : null,
        onTap: () {
          // Ação ao clicar no item, se necessário
        },
      ),
    );
  }
}
