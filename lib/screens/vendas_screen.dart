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
  String _erroCarregamento = '';

  @override
  void initState() {
    super.initState();
    _dbHelper = DatabaseHelper(apiBaseUrl: 'http://192.168.100.245:5000');
    _carregarVendas();
  }

  Future<void> _carregarVendas() async {
    setState(() {
      isLoading = true;
      _erroCarregamento = '';
    });

    try {
      debugPrint('Iniciando consulta de vendas...');

      // A função agora retorna diretamente a lista de dados (campo 'data' da API)
      final listaDados = await _dbHelper.consultarVendasCanhotos(
        codFilial: 100,
        codVendedor: 75208,
        dataInicio: '01.05.2025',
        dataFim: '31.05.2025',
        filtroCanhotos: 'Todas',
      );

      debugPrint('Quantidade de itens recebidos: ${listaDados.length}');
      if (listaDados.isNotEmpty) {
        debugPrint('Exemplo de item recebido:');
        debugPrint(' - VENDA_ID: ${listaDados[0]['VENDA_ID']}');
        debugPrint(' - NUM_NF: ${listaDados[0]['NUM_NF']}');
      }

      final listaVendas = listaDados.map<Venda>((item) {
        return Venda(
          vendaId: item['VENDA_ID'] as int,
          numNf: item['NUM_NF'].toString(),
          dataComp: DateTime.parse(item['DTACOMP']),
          parceiro: item['PARCEIRO'].toString(),
          razaoSocial: item['RAZAO_SOCIAL'].toString(),
          nomeVendedor: item['NOME_VENDEDOR'].toString(),
          totalVenda: double.parse(item['TOTAL_VENDA'].toString()),
          status: item['STATUS'].toString().trim(),
          anexoId: item['ANEXO_ID'] as int?,
          descricao: item['DESCRICAO']?.toString(),
          arquivo: item['ARQUIVO']?.toString(),
        );
      }).toList();

      setState(() {
        vendas = listaVendas;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar vendas: $e');
      setState(() {
        isLoading = false;
        _erroCarregamento = 'Erro ao carregar vendas: ${e.toString()}';
      });
      _mostrarSnackBar(_erroCarregamento);
    }
  }

  Future<void> _anexarFoto(Venda venda) async {
    final pickedFile = await _imageService.capturarFoto();

    if (pickedFile != null) {
      try {
        setState(() => isLoading = true);
        await _dbHelper.atualizarAnexo(venda.vendaId, pickedFile);
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
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Canhoto Digital'),
          content:
              arquivo.toLowerCase().endsWith('.jpg') ||
                  arquivo.toLowerCase().endsWith('.jpeg') ||
                  arquivo.toLowerCase().endsWith('.png')
              ? Image.network(
                  'http://192.168.100.245:5000/uploads/$arquivo',
                  errorBuilder: (context, error, stackTrace) {
                    return Text('Não foi possível carregar a imagem');
                  },
                )
              : Text('Anexo: $arquivo'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Fechar'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Vendas - Canhotos (${vendas.length})'),
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

    if (_erroCarregamento.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_erroCarregamento),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _carregarVendas,
              child: Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    if (vendas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Nenhuma venda encontrada no período'),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _carregarVendas,
              child: Text('Recarregar'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _carregarVendas,
      child: ListView.builder(
        itemCount: vendas.length,
        itemBuilder: (context, index) => _buildVendaItem(vendas[index]),
      ),
    );
  }

  Widget _buildVendaItem(Venda venda) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      elevation: 2,
      child: Slidable(
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
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'NF: ${venda.numNf}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    DateFormat('dd/MM/yyyy').format(venda.dataComp),
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                venda.razaoSocial,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vendedor: ${venda.nomeVendedor}',
                          style: TextStyle(fontSize: 12),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Valor: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(venda.totalVenda)}',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: venda.status == 'Sem Canhoto Assinado'
                          ? Colors.red[100]
                          : Colors.green[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      venda.status,
                      style: TextStyle(
                        color: venda.status == 'Sem Canhoto Assinado'
                            ? Colors.red[800]
                            : Colors.green[800],
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              if (venda.arquivo != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: Icon(Icons.photo_camera, color: Colors.blue),
                    onPressed: () => _visualizarAnexo(venda.arquivo),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
