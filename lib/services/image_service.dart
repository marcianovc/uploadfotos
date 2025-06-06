import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';

class ImageService {
  final ImagePicker _picker = ImagePicker();

  Future<String?> capturarFoto() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    return image?.path;
  }

  Future<Map<String, dynamic>> uploadFoto({
    required String filePath,
    required int vendaId,
    required String apiBaseUrl,
    String descricao = '',
  }) async {
    try {
      // Verifica se o arquivo existe
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Arquivo não encontrado');
      }

      // Obtém o tipo MIME do arquivo
      final mimeType = lookupMimeType(filePath);
      if (mimeType == null || !mimeType.startsWith('image/')) {
        throw Exception('Tipo de arquivo não suportado');
      }

      // Cria a requisição multipart
      final uri = Uri.parse('$apiBaseUrl/anexos/upload');
      final request = http.MultipartRequest('POST', uri);

      // Adiciona o arquivo
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          contentType: MediaType.parse(mimeType),
        ),
      );

      // Adiciona os campos adicionais
      request.fields['venda_id'] = vendaId.toString();
      if (descricao.isNotEmpty) {
        request.fields['descricao'] = descricao;
      }

      // Envia a requisição
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final jsonResponse = json.decode(responseData);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'anexo_id': jsonResponse['anexo_id'],
          'filename': jsonResponse['filename'],
          'path': jsonResponse['path'],
        };
      } else {
        throw Exception(jsonResponse['error'] ?? 'Erro no upload');
      }
    } catch (e) {
      print('Erro no upload: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}
