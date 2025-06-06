import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uploadfotos/services/image_service.dart';

class DatabaseHelper {
  String _apiBaseUrl = '';

  DatabaseHelper() {
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('api_host') ?? '192.168.100.82';
    final port = prefs.getString('api_port') ?? '5000';
    _apiBaseUrl = 'http://$host:$port';
    debugPrint('Configuração da API carregada: $_apiBaseUrl');
  }

  Future<List<Map<String, dynamic>>> executarConsulta(
    Map<String, dynamic> params,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/execute'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'sql': '''
            SELECT DISTINCT
              v.venda_id, v.num_nf, v.dtacomp, v.parceiro, 
              pa.razao_social, 
              COALESCE(pv.razao_social, 'Sem Vendedor') AS nome_vendedor, 
              v.total_venda,
              CASE 
                WHEN av.anexo_id IS NULL AND afr.anexo_id IS NULL THEN 'Sem Canhoto Assinado'
                WHEN afr.faturas_receber_id IS NOT NULL THEN 'Canhoto Boleto Assinado'
                WHEN av.anexo_id IS NOT NULL THEN 'Canhoto Nota Assinado'
              END AS status,
              a.anexo_id, a.descricao, a.arquivo
            FROM vendas v
            LEFT JOIN anexos_vendas av ON av.venda_id = v.venda_id
            LEFT JOIN faturas_receber fr ON fr.venda_id = v.venda_id
            LEFT JOIN boletos_faturas bf ON bf.faturas_receber_id = fr.faturas_receber_id
            LEFT JOIN anexos_faturas_receber afr ON afr.faturas_receber_id = fr.faturas_receber_id
            LEFT JOIN anexos a ON a.anexo_id = COALESCE(av.anexo_id, afr.anexo_id)
            LEFT JOIN parceiros pa ON pa.parceiro = v.parceiro
            LEFT JOIN parceiros pv ON pv.parceiro = v.vendedor
            WHERE v.idn_cancelada = 'N'
              AND v.codoper IN (110,100)
              AND (v.codfilial = ?)
              AND v.num_nf IS NOT NULL
              AND (v.vendedor = ?)
              AND v.dtacomp BETWEEN ? AND ?
              AND (IIF(a.anexo_id IS NULL, 'Sem Canhotos', 'Com Canhotos') = ? OR (CAST(? AS VARCHAR(12)) = 'Todas')
            ORDER BY v.vendedor, anexo_id ASC
          ''',
          'params': [
            params['filial'],
            params['distribuidor'],
            params['data_inicial'],
            params['data_final'],
            params['status'],
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['results']);
      } else {
        final error = json.decode(response.body);
        debugPrint(
          'helper - Erro na API: ${error['error']} - ${error['details']}',
        );
        throw Exception(
          'helper - Erro na API: ${error['error']} - ${error['details']}',
        );
      }
    } catch (e) {
      debugPrint('helper - Erro ao executar consulta: $e');
      throw Exception('helper - Erro ao executar consulta: $e');
    }
  }

  Future<void> atualizarAnexo(int vendaId, String caminhoArquivo) async {
    try {
      final imageService = ImageService();
      final uploadResult = await imageService.uploadFoto(
        filePath: caminhoArquivo,
        vendaId: vendaId,
        apiBaseUrl: _apiBaseUrl,
        descricao: 'Canhoto assinado',
      );

      if (!uploadResult['success']) {
        throw Exception(uploadResult['error'] ?? 'Erro desconhecido no upload');
      }

      debugPrint('Upload realizado com sucesso: ${uploadResult['filename']}');
    } catch (e) {
      debugPrint('Erro ao atualizar anexo: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> consultarVendasCanhotos({
    required int codFilial,
    required int codVendedor,
    required String dataInicio,
    required String dataFim,
    required String filtroCanhotos,
  }) async {
    try {
      final url = Uri.parse('$_apiBaseUrl/vendas/canhotos');
      debugPrint('Enviando requisição para: $url');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'codfilial': codFilial,
          'vendedor': codVendedor,
          'data_inicio': dataInicio,
          'data_fim': dataFim,
          'filtro_canhotos': filtroCanhotos,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['data']);
        } else {
          throw Exception('API retornou erro: ${data['error']}');
        }
      } else {
        final error = json.decode(response.body);
        throw Exception(
          'Erro na API: ${error['error']} (Código: ${error['error_code']})',
        );
      }
    } catch (e) {
      debugPrint('Erro ao consultar vendas: $e');
      throw Exception('Erro ao consultar vendas: $e');
    }
  }

  Future<List<Map<String, dynamic>>> consultaNota({required int numNf}) async {
    try {
      final url = Uri.parse('$_apiBaseUrl/vendas/nota');
      debugPrint('Enviando requisição para: $url');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'numnf': numNf}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['data']);
        } else {
          throw Exception('API retornou erro: ${data['error']}');
        }
      } else {
        final error = json.decode(response.body);
        throw Exception(
          'Erro na API: ${error['error']} (Código: ${error['error_code']})',
        );
      }
    } catch (e) {
      debugPrint('Erro ao consultar vendas: $e');
      throw Exception('Erro ao consultar vendas: $e');
    }
  }

  Future<Uint8List> visualizarAnexo({
    required int anexoId,
    bool download = false,
  }) async {
    try {
      final url = Uri.parse(
        '$_apiBaseUrl/anexos/$anexoId${download ? '?download=true' : ''}',
      );
      debugPrint('Solicitando anexo: $url');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        final error = json.decode(response.body);
        throw Exception(
          'Erro ao obter anexo: ${error['error']} (Código: ${error['error_code']})',
        );
      }
    } catch (e) {
      debugPrint('Erro na requisição do anexo: $e');
      throw Exception('Erro ao acessar anexo: $e');
    }
  }
}
