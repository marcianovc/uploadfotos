import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import '../models/venda_model.dart';

class VendaItemWidget extends StatelessWidget {
  final Venda venda;
  final Function() onAnexarFoto;

  const VendaItemWidget({
    required this.venda,
    required this.onAnexarFoto,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Slidable(
      endActionPane: venda.status == 'Sem Canhoto Assinado'
          ? ActionPane(
              motion: const ScrollMotion(),
              children: [
                SlidableAction(
                  onPressed: (_) => onAnexarFoto(),
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
                onPressed: () {
                  // Mostrar foto anexada
                },
              )
            : null,
      ),
    );
  }
}
