class Venda {
  final int vendaId;
  final String numNf;
  final DateTime dataComp;
  final String parceiro;
  final String razaoSocial;
  final String nomeVendedor;
  final double totalVenda;
  final String status;
  final int? anexoId;
  final String? descricao;
  final String? arquivo;
  final int filial;

  Venda({
    required this.vendaId,
    required this.numNf,
    required this.dataComp,
    required this.parceiro,
    required this.razaoSocial,
    required this.nomeVendedor,
    required this.totalVenda,
    required this.status,
    this.anexoId,
    this.descricao,
    this.arquivo,
    required this.filial,
  });

  factory Venda.fromMap(Map<String, dynamic> map) {
    return Venda(
      vendaId: map['VENDA_ID'],
      numNf: map['NUM_NF'],
      dataComp: DateTime.parse(map['DTACOMP']),
      parceiro: map['PARCEIRO'],
      razaoSocial: map['RAZAO_SOCIAL'],
      nomeVendedor: map['NOME_VENDEDOR'],
      totalVenda: map['TOTAL_VENDA'].toDouble(),
      status: map['STATUS'],
      anexoId: map['ANEXO_ID'],
      descricao: map['DESCRICAO'],
      arquivo: map['ARQUIVO'],
      filial: map['FILIAL'],
    );
  }
}
