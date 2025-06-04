import 'package:image_picker/image_picker.dart';

class ImageService {
  final ImagePicker _picker = ImagePicker();

  Future<String?> capturarFoto() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    return image?.path;
  }

  Future<String> uploadFoto(String filePath, int vendaId) async {
    // Implementação do upload
    return 'caminho/do/arquivo/$vendaId.jpg';
  }
}
