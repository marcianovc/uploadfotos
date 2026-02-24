import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uploadfotos/screens/api_config_screen.dart';
import 'package:uploadfotos/services/auth_service.dart';
import 'package:url_launcher/url_launcher.dart';
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
  int _codFilialTrabalho = 0;
  int _codVendedor = 0;

  Future<void> _logout() async {
    try {
      setState(() => isLoading = true);
      final authService = AuthService();
      await authService.logout();

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      if (mounted) {
        _mostrarSnackBar('Erro ao fazer logout: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _dbHelper = DatabaseHelper();
    _carregarDadosUsuario();
  }

  Future<void> _carregarDadosUsuario() async {
    try {
      final authService = AuthService();
      _codFilialTrabalho = await authService.getCodFilialTrabalho();
      _codVendedor = await authService.getCodVendedor();

      debugPrint('Filial de trabalho: $_codFilialTrabalho');
      debugPrint('Código do vendedor: $_codVendedor');

      // Após carregar os dados do usuário, carrega as vendas
      _carregarVendas();
    } catch (e) {
      debugPrint('Erro ao carregar dados do usuário: $e');
      setState(() {
        isLoading = false;
        _erroCarregamento = 'Erro ao carregar dados do usuário';
      });
    }
  }

  Future<void> _carregarVendas() async {
    setState(() {
      isLoading = true;
      _erroCarregamento = '';
    });

    try {
      debugPrint('Iniciando consulta de vendas...');
      debugPrint('Filial: $_codFilialTrabalho, Vendedor: $_codVendedor');

      DateTime now = DateTime.now();

      // Primeiro dia do mês atual
      DateTime firstDayOfMonth = DateTime(now.year, now.month, 1);

      // Último dia do mês atual
      DateTime lastDayOfMonth = DateTime(now.year, now.month + 1, 0);

      debugPrint('Primeiro dia do mês: $firstDayOfMonth');
      debugPrint('Último dia do mês: $lastDayOfMonth');

      // A função agora retorna diretamente a lista de dados (campo 'data' da API)
      final listaDados = await _dbHelper.consultarVendasCanhotos(
        codFilial: _codFilialTrabalho,
        codVendedor: _codVendedor,
        dataInicio: DateFormat('dd.MM.yyyy').format(firstDayOfMonth),
        dataFim: DateFormat('dd.MM.yyyy').format(lastDayOfMonth),
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
          filial: item['FILIAL'] as int,
          forma: item['DSCFORMA'].toString(),
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
    final descricao = await _mostrarDialogoDescricao();
    if (descricao == null) return; // Usuário cancelou

    final pickedFile = await _imageService.capturarFoto();

    if (pickedFile != null) {
      try {
        setState(() => isLoading = true);
        await _dbHelper.atualizarAnexo(venda.vendaId, pickedFile, descricao);
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

  void _visualizarAnexo(int? anexoId, String? nomeArquivo) async {
    if (anexoId == null || nomeArquivo == null) {
      _mostrarSnackBar('Nenhum anexo disponível para visualização');
      return;
    }

    try {
      setState(() => isLoading = true);

      final isImagem =
          nomeArquivo.toLowerCase().endsWith('.jpg') ||
          nomeArquivo.toLowerCase().endsWith('.jpeg') ||
          nomeArquivo.toLowerCase().endsWith('.png');

      if (isImagem) {
        // Para imagens, baixa e mostra em memória
        final bytes = await _dbHelper.visualizarAnexo(anexoId: anexoId);

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Canhoto Digital'),
            content: InteractiveViewer(
              child: Image.memory(
                bytes,
                errorBuilder: (context, error, stackTrace) {
                  return Text('Não foi possível carregar a imagem');
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Fechar'),
              ),
              TextButton(
                onPressed: () => _downloadAnexo(anexoId, nomeArquivo),
                child: Text('Download'),
              ),
            ],
          ),
        );
      } else {
        // Para outros tipos de arquivo, oferece download
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Anexo Digital'),
            content: Text('Deseja fazer download do arquivo $nomeArquivo?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancelar'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _downloadAnexo(anexoId, nomeArquivo);
                },
                child: Text('Download'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao visualizar anexo: $e');
      _mostrarSnackBar('Erro ao visualizar anexo: ${e.toString()}');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _downloadAnexo(int anexoId, String nomeArquivo) async {
    try {
      setState(() => isLoading = true);

      final bytes = await _dbHelper.visualizarAnexo(
        anexoId: anexoId,
        download: true,
      );

      // Obter o diretório de downloads
      final directory = await getDownloadsDirectory();
      if (directory == null) {
        throw Exception('Não foi possível acessar a pasta de downloads');
      }

      // Cria o arquivo local
      final filePath = '${directory.path}/$nomeArquivo';
      final file = File(filePath);

      // Escreve os bytes no arquivo
      await file.writeAsBytes(bytes);

      _mostrarSnackBar('Download concluído: $filePath');

      // Opcional: abrir o arquivo após download
      if (await canLaunch(filePath)) {
        await launch(filePath);
      }
    } catch (e) {
      debugPrint('Erro no download: $e');
      _mostrarSnackBar('Erro ao fazer download: ${e.toString()}');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _mostrarDialogoBusca() {
    final numNfController = TextEditingController();
    final roteiroController = TextEditingController();
    int tipoBuscaSelecionado = 0; // 0 = Nota Fiscal, 1 = Roteiro

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Consultar'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Radio<int>(
                      value: 0,
                      groupValue: tipoBuscaSelecionado,
                      onChanged: (value) {
                        setState(() {
                          tipoBuscaSelecionado = value!;
                        });
                      },
                    ),
                    const Text('Nota Fiscal'),
                    Radio<int>(
                      value: 1,
                      groupValue: tipoBuscaSelecionado,
                      onChanged: (value) {
                        setState(() {
                          tipoBuscaSelecionado = value!;
                        });
                      },
                    ),
                    const Text('Roteiro'),
                  ],
                ),
                const SizedBox(height: 16),
                if (tipoBuscaSelecionado == 0) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: numNfController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Número da Nota Fiscal',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: roteiroController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Número do Roteiro',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (tipoBuscaSelecionado == 0) {
                    final numNf = int.tryParse(numNfController.text);

                    if (numNf != null) {
                      Navigator.pop(context);
                      _consultarPorNotaFiscal(numNf);
                    } else {
                      _mostrarSnackBar(
                        'Preencha ambos os campos corretamente!',
                      );
                    }
                  } else {
                    final roteiro = int.tryParse(roteiroController.text);
                    if (roteiro != null) {
                      Navigator.pop(context);
                      _consultarPorRoteiro(roteiro);
                    } else {
                      _mostrarSnackBar('Informe o número do roteiro!');
                    }
                  }
                },
                child: const Text('Buscar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<String?> _mostrarDialogoDescricao() async {
    final TextEditingController descricaoController = TextEditingController();
    String? resultado;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descrição da Foto'),
        content: TextField(
          controller: descricaoController,
          decoration: const InputDecoration(
            hintText: 'Digite uma descrição para a foto...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              resultado = descricaoController.text.trim();
              Navigator.pop(context);
            },
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    return resultado;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Vendas - Canhotos (${vendas.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Sair',
          ),
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () async {
              final configUpdated = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => const ApiConfigScreen(),
                ),
              );

              if (configUpdated == true) {
                // Recarregar dados se as configurações foram atualizadas
                _carregarVendas();
              }
            },
          ),
          if (_codVendedor == 0)
            IconButton(
              icon: Icon(Icons.search),
              onPressed: () => _mostrarDialogoBusca(),
            ),
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
                    'Filial: ${venda.filial}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
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
                          'Valor: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(venda.totalVenda)} - Forma: ${venda.forma}',
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
                    onPressed: () =>
                        _visualizarAnexo(venda.anexoId, venda.arquivo),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _consultarPorNotaFiscal(int numNf) async {
    setState(() {
      isLoading = true;
      _erroCarregamento = '';
    });

    try {
      debugPrint('Iniciando consulta por nota fiscal: $numNf');

      // Adicione este método no seu DatabaseHelper
      final listaDados = await _dbHelper.consultaNota(numNf: numNf);

      debugPrint('Resultado da consulta por nota: ${listaDados.length} itens');
      if (listaDados.isNotEmpty) {
        debugPrint('Primeiro item: ${listaDados.first}');
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
          filial: item['FILIAL'] as int,
          forma: item['DSCFORMA'].toString(),
        );
      }).toList();

      setState(() {
        vendas = listaVendas;
        isLoading = false;
      });

      if (listaVendas.isEmpty) {
        _mostrarSnackBar('Nenhuma venda encontrada para a nota fiscal $numNf');
      }
    } catch (e) {
      debugPrint('Erro ao consultar por nota fiscal: $e');
      setState(() {
        isLoading = false;
        _erroCarregamento = 'Erro ao consultar nota fiscal: ${e.toString()}';
      });
      _mostrarSnackBar(_erroCarregamento);
    }
  }

  Future<void> _consultarPorRoteiro(int roteiro) async {
    setState(() {
      isLoading = true;
      _erroCarregamento = '';
    });

    try {
      debugPrint('Iniciando consulta por roteiro: $roteiro');

      // Implemente aqui a chamada para sua API de roteiro
      final listaDados = await _dbHelper.consultarPorRoteiro(roteiro: roteiro);

      debugPrint(
        'Resultado da consulta por roteiro: ${listaDados.length} itens',
      );

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
          filial: item['FILIAL'] as int,
          forma: item['DSCFORMA'].toString(),
        );
      }).toList();

      setState(() {
        vendas = listaVendas;
        isLoading = false;
      });

      if (listaVendas.isEmpty) {
        _mostrarSnackBar('Nenhuma venda encontrada para o roteiro $roteiro');
      }
    } catch (e) {
      debugPrint('Erro ao consultar por roteiro: $e');
      setState(() {
        isLoading = false;
        _erroCarregamento = 'Erro ao consultar roteiro: ${e.toString()}';
      });
      _mostrarSnackBar(_erroCarregamento);
    }
  }
}
