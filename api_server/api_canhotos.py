from flask import Flask, request, jsonify, send_file, abort
import fdb
import traceback
from datetime import date, datetime
import os
from werkzeug.utils import secure_filename
import uuid
import hashlib

app = Flask(__name__)

# Defina uma chave forte e complexa. 
# Dica de segurança: em produção, o ideal é ler isso de uma variável de ambiente usando os.environ.get('MINHA_API_KEY') 
API_KEY = "OGQX3A1t8N3nV8LlTP8DVskpzUu1lCVKWrmShj27cs3C1hkxFuJGcgQM8iqbdrf7"

def require_apikey(view_function):
    @wraps(view_function)
    def decorated_function(*args, **kwargs):
        # Verifica se o Flutter enviou o cabeçalho 'X-API-Key' com o valor correto
        chave_recebida = request.headers.get('X-API-Key')
        if chave_recebida and chave_recebida == API_KEY:
            return view_function(*args, **kwargs)
        else:
            # Se não tiver a chave, ou estiver errada, derruba a conexão com erro 401 (Não Autorizado)
            abort(401, description="Acesso negado: Chave de API inválida ou ausente")
    return decorated_function

# Configurações do banco de dados - ajuste conforme necessário
DB_CONFIG = {
    'host': '192.168.100.67',
    'database': '/var/banco/GESTAO.FDB',
    'user': 'api_canhotos',
    'password': 'Q27ppTz8M',
    'charset': 'UTF8'
}

# Configuração do caminho base dos anexos
BASE_ANEXOS_PATH = r"\\192.168.100.64\Arquivos Ultra\Anexos"
UPLOAD_FOLDER = r"\\192.168.100.64\Arquivos Ultra\Anexos"
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'}

def safe_path_join(base_path, *paths):
    """Junta caminhos de forma segura para evitar directory traversal"""
    full_path = os.path.abspath(os.path.join(base_path, *paths))
    base_path = os.path.abspath(base_path)
    
    # Verifica se o caminho final está dentro do diretório base
    if not full_path.startswith(base_path):
        abort(403, description="Acesso ao arquivo não permitido")
    
    return full_path

def allowed_file(filename):
    """Verifica se a extensão do arquivo é permitida"""
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def generate_unique_filename(original_filename, max_length=150):
    """
    Gera um nome de arquivo único com hash, limitando o tamanho total
    
    Args:
        original_filename: Nome original do arquivo (ex: "foto.jpg")
        max_length: Tamanho máximo permitido (incluindo extensão)
    
    Returns:
        Nome do arquivo no formato: "HASH_TIMESTAMP.EXT"
    """
    # Obtém a extensão do arquivo em maiúsculas
    file_extension = os.path.splitext(original_filename)[1][1:].upper()
    
    # Gera um hash SHA256 do timestamp atual + nome original
    timestamp = datetime.now().strftime('%Y%m%d%H%M%S%f')
    hash_input = f"{timestamp}{original_filename}".encode('utf-8')
    file_hash = hashlib.sha256(hash_input).hexdigest()
    
    # Calcula o tamanho disponível para o hash (descontando timestamp, pontos e extensão)
    # Formato final: "HASH_TIMESTAMP.EXT"
    timestamp_length = len(timestamp) + 1  # +1 para o underscore
    extension_length = len(file_extension) + 1  # +1 para o ponto
    max_hash_length = max_length - timestamp_length - extension_length
    
    # Garante que o hash não ultrapasse o tamanho máximo
    truncated_hash = file_hash[:max_hash_length]
    
    # Monta o nome final do arquivo
    unique_filename = f"{truncated_hash}_{timestamp}.{file_extension}"
    
    return unique_filename

@app.route('/anexos/xupload', methods=['POST'])
@require_apikey
def xupload_imagem():
    try:
        if 'file' not in request.files:
            return jsonify({'success': False, 'error': 'Nenhum arquivo enviado'}), 400

        file = request.files['file']
        
        if file.filename == '':
            return jsonify({'success': False, 'error': 'Nome de arquivo vazio'}), 400

        # Obtém a extensão original
        original_extension = os.path.splitext(file.filename)[1].lower()
        
        if not allowed_file(file.filename):
            return jsonify({
                'success': False,
                'error': 'Tipo de arquivo não permitido',
                'received_extension': original_extension,
                'allowed_extensions': list(ALLOWED_EXTENSIONS)
            }), 400

        filename = secure_filename(file.filename)
        unique_filename = f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}_{filename}"
        
        # Extrai a extensão do nome seguro do arquivo
        file_extension = os.path.splitext(filename)[1].lower()
        file_extension = file_extension[1:]  # Remove o ponto

        save_path = os.path.join(UPLOAD_FOLDER, unique_filename)
        file.save(save_path)

        # Obtém parâmetros adicionais
        venda_id = request.form.get('venda_id')
        descricao = request.form.get('descricao', '')

        # Registra no banco de dados
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Insere na tabela anexos
        cursor.execute(
            "INSERT INTO anexos (descricao, arquivo, data_cadastro) VALUES (?, ?, CURRENT_TIMESTAMP) RETURNING anexo_id",
            [descricao, unique_filename]
        )
        anexo_id = cursor.fetchone()[0]
        
        # Se tiver venda_id, relaciona com a venda e com a nota fiscal da venda
        if venda_id:
            cursor.execute(
                "INSERT INTO anexos_vendas (anexo_id, venda_id) VALUES (?, ?)",
                [anexo_id, venda_id]
            )
            cursor.execute(
                "INSERT INTO anexos_notas_emitidas (anexo_id, venda_id) VALUES (?, ?)",
                [anexo_id, venda_id]
            )
        
        conn.commit()

        return jsonify({
            'success': True,
            'anexo_id': anexo_id,
            'original_filename': file.filename,
            'saved_filename': unique_filename,
            'file_extension': file_extension,
            'file_type': file.content_type,
            'file_size': os.path.getsize(save_path),
            'path': save_path
        })

    except Exception as e:
        # Remove o arquivo se houve erro no banco de dados
        if 'save_path' in locals() and os.path.exists(save_path):
            os.remove(save_path)
            
        return jsonify({
            'success': False,
            'error': str(e),
            'error_code': 'UPLOAD_ERROR'
        }), 500
    finally:
        try:
            cursor.close()
            conn.close()
        except:
            pass

@app.route('/anexos/<int:anexo_id>', methods=['GET'])
@require_apikey
def visualizar_anexo(anexo_id):
    """
    Endpoint para visualizar/download de anexos
    Parâmetros:
    - anexo_id: ID do anexo (obtido na consulta de vendas)
    - download: query param (opcional) - se true, força download ao invés de visualização
    """
    try:
        # Primeiro consultamos o banco para obter o nome do arquivo
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute("SELECT arquivo FROM anexos WHERE anexo_id = ?", [anexo_id])
        result = cursor.fetchone()
        
        if not result:
            abort(404, description="Anexo não encontrado no banco de dados")
        
        #nome_arquivo = secure_filename(result[0])  # Sanitiza o nome do arquivo
        nome_arquivo = result[0].strip() # Apenas remove os espaços do Firebird
        caminho_completo = safe_path_join(BASE_ANEXOS_PATH, nome_arquivo)
        
        # Verifica se o arquivo existe
        if not os.path.exists(caminho_completo):
            abort(404, description="Arquivo não encontrado no servidor")
        
        # Determina se é para download ou visualização
        download = request.args.get('download', 'false').lower() == 'true'
        
        # Envia o arquivo
        return send_file(
            caminho_completo,
            as_attachment=download,
            download_name=nome_arquivo if download else None,
            mimetype=None,  # O Flask irá inferir o tipo MIME automaticamente
            conditional=True  # Suporte a requisições condicionais (cache)
        )
        
    except fdb.Error as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'error_code': 'FIREBIRD_ERROR'
        }), 500
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'error_code': 'INTERNAL_ERROR'
        }), 500
    finally:
        try:
            cursor.close()
            conn.close()
        except:
            pass

def get_db_connection():
    """Cria e retorna uma conexão com o banco de dados Firebird"""
    return fdb.connect(
        host=DB_CONFIG['host'],
        database=DB_CONFIG['database'],
        user=DB_CONFIG['user'],
        password=DB_CONFIG['password'],
        charset=DB_CONFIG['charset']
    )

@app.route('/execute', methods=['POST'])
@require_apikey
def execute_query():
    try:
        data = request.get_json()
        if not data or 'sql' not in data:
            return jsonify({
                'success': False,
                'error': 'Consulta SQL não fornecida',
                'error_code': 'MISSING_SQL'
            }), 400

        sql = data['sql'].strip()
        params = data.get('params', [])
        print(f"\n[DEBUG] SQL: {sql}")
        print(f"[DEBUG] Parâmetros: {params}\n")
        debug_mode = data.get('debug', False)

        # Preparar a resposta base
        response = {
            'success': True,
            'query': {
                'sql': sql,
                'params': params
            }
            if debug_mode else None
        }

        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(sql, params)

        if sql.strip().upper().startswith('SELECT'):
            # Obter metadados das colunas
            columns = [desc[0] for desc in cursor.description]
            
            # Converter resultados para JSON
            results = []
            for row in cursor.fetchall():
                row_data = {}
                for i, col in enumerate(columns):
                    value = row[i]
                    
                    # Conversão segura de tipos para JSON
                    if value is None:
                        row_data[col] = None
                    elif isinstance(value, (bytes, bytearray)):
                        row_data[col] = value.hex()  # Converter BLOB para hexadecimal
                    elif hasattr(value, 'isoformat'):  # Para tipos de data/hora
                        row_data[col] = value.isoformat()
                    else:
                        try:
                            # Tentar serialização direta
                            json.dumps(value)
                            row_data[col] = value
                        except TypeError:
                            # Fallback para string se não for serializável
                            row_data[col] = str(value)
                
                results.append(row_data)
            
            # Estrutura completa da resposta
            response.update({
                'type': 'query',
                'results': results,
                'metadata': {
                    'columns': columns,
                    'count': len(results),
                    'rowcount': cursor.rowcount
                }
            })
        else:
            # Para comandos DML (INSERT, UPDATE, DELETE)
            conn.commit()
            response.update({
                'type': 'command',
                'rowcount': cursor.rowcount,
                'message': 'Comando executado com sucesso'
            })

        return jsonify(response)

    except fdb.Error as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'error_code': 'FIREBIRD_ERROR',
            'sqlcode': e.sqlcode,
            'sql': sql if debug_mode else None,
            'params': params if debug_mode else None
        }), 400
    except Exception as e:
        return jsonify({
            'success': False,
            'error': 'Erro interno no servidor',
            'error_code': 'INTERNAL_ERROR',
            'details': str(e),
            'traceback': traceback.format_exc() if debug_mode else None
        }), 500
    finally:
        try:
            cursor.close()
        except:
            pass
        try:
            conn.close()
        except:
            pass

@app.route('/anexos/upload', methods=['POST'])
@require_apikey
def upload_imagem():
    try:
        if 'file' not in request.files:
            return jsonify({'success': False, 'error': 'Nenhum arquivo enviado'}), 400

        file = request.files['file']
        
        if file.filename == '':
            return jsonify({'success': False, 'error': 'Nome de arquivo vazio'}), 400
        
        venda_id = request.form.get('venda_id')
        
        if not venda_id:
            return jsonify({
                'success': False,
                'error': 'ID da venda não informado',
                'error_code': 'MISSING_SALE_ID'
            }), 400
            
        # Obtém a extensão original
        original_extension = os.path.splitext(file.filename)[1].lower()
        
        if not allowed_file(file.filename):
            return jsonify({
                'success': False,
                'error': 'Tipo de arquivo não permitido',
                'received_extension': original_extension,
                'allowed_extensions': list(ALLOWED_EXTENSIONS)
            }), 400
            
        filename = secure_filename(file.filename)
        unique_filename = f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}_{filename}"
        
        # Extrai a extensão do nome seguro do arquivo
        file_extension = os.path.splitext(filename)[1].upper()
        file_extension = file_extension[1:]  # Remove o ponto

        save_path = os.path.join(UPLOAD_FOLDER, unique_filename)
        file.save(save_path)

        # Obtém parâmetros adicionais
        venda_id = request.form.get('venda_id')
        descricao = request.form.get('descricao', '')

        # 1. Primeiro inserimos o anexo
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute("""
            INSERT INTO anexos 
            (anexo_id, anexo_tipo_id, arquivo, arquivo_tipo, datahora, operador, classificacao, data_criacao_alteracao, descricao) 
            VALUES (gen_id(gen_anexos, 1),3, ?, ?, CURRENT_TIMESTAMP, 177, 'IMAGEM', CURRENT_TIMESTAMP, ?) 
            RETURNING anexo_id
        """, [unique_filename, file_extension, descricao])
        
        anexo_id = cursor.fetchone()[0]

        # 2. Buscamos o nota_id relacionada à venda
        cursor.execute("""
            SELECT ne.nota_id 
            FROM vendas v 
            INNER JOIN notas_emitidas ne ON (ne.num_nota = v.num_nf AND ne.codfilial = v.codfilial) 
            WHERE v.venda_id = ?
        """, [venda_id])
        
        nota_result = cursor.fetchone()
        
        if not nota_result:
            conn.rollback()
            return jsonify({
                'success': False,
                'error': 'Nota fiscal não encontrada para esta venda',
                'error_code': 'INVOICE_NOT_FOUND'
            }), 404

        nota_id = nota_result[0]

        # 3. Vinculamos o anexo à nota emitida
        cursor.execute(
            "INSERT INTO anexos_notas_emitidas (anexo_id, nota_id) VALUES (?, ?)",
            [anexo_id, nota_id]
        )

        # 4. Se necessário, vinculamos também à venda diretamente
        if request.form.get('venda_id'):
            cursor.execute(
                "INSERT INTO anexos_vendas (anexo_id, venda_id) VALUES (?, ?)",
                [anexo_id, venda_id]
            )

        conn.commit()

        return jsonify({
            'success': True,
            'anexo_id': anexo_id,
            'nota_id': nota_id,
            'venda_id': venda_id,
            'filename': unique_filename
        })

    except Exception as e:
        conn.rollback()
        return jsonify({
            'success': False,
            'error': str(e),
            'error_code': 'UPLOAD_ERROR'
        }), 500
    finally:
        try:
            cursor.close()
            conn.close()
        except:
            pass

@app.route('/auth/login', methods=['POST'])
@require_apikey
def autenticar_usuario():
    """
    Endpoint para autenticação de usuário com senha em texto puro
    Parâmetros esperados (JSON):
    {
        "login": "CPF ou CNPJ do usuário",
        "senha": "Senha em texto puro"
    }
    """
    try:
        data = request.get_json()
        
        # Validação dos campos obrigatórios
        if not data or 'login' not in data or 'senha' not in data:
            return jsonify({
                'success': False,
                'error': 'CPF/CNPJ e senha são obrigatórios',
                'error_code': 'MISSING_CREDENTIALS'
            }), 400

        login = data['login'].strip()
        senha = data['senha'].strip()  # Remove espaços em branco

        # Remove caracteres não numéricos do CPF/CNPJ
        login_limpo = ''.join(filter(str.isdigit, login))
        print(f"\n[DEBUG] LOGIN: {data['login']}")
        print(f"[DEBUG] SENHA: {data['senha']}\n")
        #print(f"[DEBUG] login_limpo: {login_limpo}\n")

        # Consulta no banco de dados
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT p.ativo, p.cpf, p.cnpj, p.senha, p.codfilial_cadastro AS codfilial_trabalho ,
            CASE WHEN p.parceiro IN (75277, 13290, 18335, 32199, 14336, 19876, 75208) THEN 0 ELSE p.parceiro END AS codvendedor
            FROM parceiros p
            WHERE (p.cpf = ? OR p.cnpj = ?)
              AND p.senha IS NOT NULL
              AND p.ativo = 'S'
        """, [data['login'], data['login']])

        parceiro = cursor.fetchone()

        if not parceiro:
            return jsonify({
                'success': False,
                'error': 'CPF/CNPJ não encontrado ou usuário inativo',
                'error_code': 'USER_NOT_FOUND'
            }), 404

        # Obtém a senha do banco (em texto puro)
        senha_db = parceiro[3].strip() if parceiro[3] else None  # Remove espaços da senha no BD

        # Comparação direta (sem hash)
        if senha != senha_db:
            return jsonify({
                'success': False,
                'error': 'Senha incorreta',
                'error_code': 'INVALID_PASSWORD'
            }), 401

        # Autenticação bem-sucedida
        return jsonify({
            'success': True,
            'message': 'Autenticação bem-sucedida',
            'user_data': {
                'cpf': parceiro[1],
                'cnpj': parceiro[2],
                'codfilial_trabalho': parceiro[4],
                'codvendedor': parceiro[5]
            }
        })

    except fdb.Error as e:
        return jsonify({
            'success': False,
            'error': 'Erro no banco de dados',
            'details': str(e),
            'error_code': 'DATABASE_ERROR'
        }), 500
    except Exception as e:
        return jsonify({
            'success': False,
            'error': 'Erro interno no servidor',
            'details': str(e),
            'error_code': 'INTERNAL_ERROR'
        }), 500
    finally:
        try:
            cursor.close()
            conn.close()
        except:
            pass            

@app.route('/vendas/canhotos', methods=['POST'])
@require_apikey
def consulta_vendas_canhotos():
    """
    Endpoint específico para consulta de vendas com status de canhotos
    Parâmetros esperados:
    {
        "codfilial": int,
        "vendedor": int,  # 0 para todos os vendedores
        "data_inicio": "DD.MM.YYYY" ou "YYYY-MM-DD",
        "data_fim": "DD.MM.YYYY" ou "YYYY-MM-DD",
        "filtro_canhotos": "Todas" | "Com Canhotos" | "Sem Canhotos"
    }
    """
    try:
        data = request.get_json()
        
        # Validação dos parâmetros
        required_fields = ['codfilial', 'vendedor', 'data_inicio', 'data_fim', 'filtro_canhotos']
        for field in required_fields:
            if field not in data:
                return jsonify({
                    'success': False,
                    'error': f'Parâmetro obrigatório faltando: {field}',
                    'error_code': 'MISSING_PARAM'
                }), 400

        # Função para converter formatos de data
        def parse_date(date_str):
            try:
                if '.' in date_str:  # Formato DD.MM.YYYY
                    day, month, year = map(int, date_str.split('.'))
                    return date(year, month, day).strftime('%Y-%m-%d')
                else:  # Assume formato YYYY-MM-DD
                    return date_str
            except Exception as e:
                raise ValueError(f"Formato de data inválido: {date_str}. Use DD.MM.YYYY ou YYYY-MM-DD")

        # Converter datas para o formato YYYY-MM-DD
        data_inicio = parse_date(data['data_inicio'])
        data_fim = parse_date(data['data_fim'])

        # Consulta SQL fixa
        sql = """
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
            a.anexo_id,
            CASE WHEN a.descricao IS NULL THEN ' ' ELSE a.descricao END AS descricao,
            a.arquivo, v.codfilial as filial, fpr.dscforma, afr.anexo_id as afr_anexoid , ane.anexo_id as ane_anexoid
        FROM vendas v
        LEFT JOIN anexos_vendas av ON av.venda_id = v.venda_id
        LEFT JOIN faturas_receber fr ON fr.venda_id = v.venda_id
        LEFT JOIN boletos_faturas bf ON bf.faturas_receber_id = fr.faturas_receber_id
        LEFT JOIN notas_emitidas ne ON ne.num_nota = v.num_nf
        LEFT JOIN anexos_faturas_receber afr ON afr.faturas_receber_id = fr.faturas_receber_id
        LEFT JOIN anexos_notas_emitidas ane ON ane.nota_id = ne.nota_id
        --LEFT JOIN anexos a ON a.anexo_id = COALESCE(av.anexo_id, afr.anexo_id)
        LEFT JOIN anexos a ON a.anexo_id = COALESCE(ane.anexo_id, afr.anexo_id, av.anexo_id)
        LEFT JOIN parceiros pa ON pa.parceiro = v.parceiro
        LEFT JOIN parceiros pv ON pv.parceiro = v.vendedor
        LEFT JOIN formas_pagar_receber fpr on fpr.forma = v.forma
        WHERE v.idn_cancelada = 'N'
            AND v.codoper IN (110,100,137,138)
            AND (v.codfilial = ?)
            AND v.num_nf IS NOT NULL
            --AND (afr.anexo_id IS NOT NULL or ane.anexo_id IS NOT NULL)
            AND (v.vendedor = ? OR (? = 0))
            AND v.dtacomp BETWEEN ? AND ?
            AND (IIF(a.anexo_id IS NULL, 'Sem Canhotos', 'Com Canhotos') = ? OR (? = 'Todas'))
        ORDER BY v.num_nf, v.vendedor, anexo_id ASC
        """

        # Parâmetros na ordem correta
        params = [
            data['codfilial'],
            data['vendedor'],
            data['vendedor'],  # Repetido para a condição OR
            data_inicio,
            data_fim,
            data['filtro_canhotos'],
            data['filtro_canhotos']  # Repetido para a condição OR
        ]

        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(sql, params)

        # Processar resultados
        columns = [desc[0] for desc in cursor.description]
        results = []
        for row in cursor.fetchall():
            row_data = {}
            for i, col in enumerate(columns):
                value = row[i]
                if isinstance(value, (bytes, bytearray)):
                    value = value.hex()
                elif isinstance(value, (date, datetime)):
                    value = value.isoformat()
                row_data[col] = value
            results.append(row_data)

        return jsonify({
            'success': True,
            'data': results,
            'count': len(results),
            'params_used': {
                'codfilial': data['codfilial'],
                'vendedor': data['vendedor'],
                'data_inicio': data_inicio,
                'data_fim': data_fim,
                'filtro_canhotos': data['filtro_canhotos']
            }
        })

    except ValueError as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'error_code': 'INVALID_DATE_FORMAT'
        }), 400
    except fdb.Error as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'sqlcode': e.sqlcode,
            'error_code': 'FIREBIRD_ERROR'
        }), 400
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'error_code': 'INTERNAL_ERROR'
        }), 500
    finally:
        try:
            cursor.close()
        except:
            pass
        try:
            conn.close()
        except:
            pass

@app.route('/vendas/nota', methods=['POST'])
@require_apikey
def consulta_nota():
    """
    Endpoint específico para consulta de notas com status de canhotos
    Parâmetros esperados:
    {
        "codfilial": int,
        "numnf": int
    }
    """
    try:
        data = request.get_json()
        
        # Validação dos parâmetros
        #required_fields = ['codfilial', 'numnf']
        required_fields = ['numnf']
        for field in required_fields:
            if field not in data:
                return jsonify({
                    'success': False,
                    'error': f'Parâmetro obrigatório faltando: {field}',
                    'error_code': 'MISSING_PARAM'
                }), 400

        # Consulta SQL fixa
        sql = """
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
            a.anexo_id,
            CASE WHEN a.descricao IS NULL THEN ' ' ELSE a.descricao END AS descricao,
            a.arquivo, v.codfilial as filial, fpr.dscforma, afr.anexo_id as afr_anexoid , ane.anexo_id as ane_anexoid
        FROM vendas v
        LEFT JOIN anexos_vendas av ON av.venda_id = v.venda_id
        LEFT JOIN faturas_receber fr ON fr.venda_id = v.venda_id
        LEFT JOIN boletos_faturas bf ON bf.faturas_receber_id = fr.faturas_receber_id
        LEFT JOIN notas_emitidas ne ON ne.num_nota = v.num_nf
        LEFT JOIN anexos_faturas_receber afr ON afr.faturas_receber_id = fr.faturas_receber_id
        LEFT JOIN anexos_notas_emitidas ane ON ane.nota_id = ne.nota_id
        --LEFT JOIN anexos a ON a.anexo_id = COALESCE(av.anexo_id, afr.anexo_id)
        LEFT JOIN anexos a ON a.anexo_id = COALESCE(ane.anexo_id, afr.anexo_id, av.anexo_id)
        LEFT JOIN parceiros pa ON pa.parceiro = v.parceiro
        LEFT JOIN parceiros pv ON pv.parceiro = v.vendedor
        LEFT JOIN formas_pagar_receber fpr on fpr.forma = v.forma
        WHERE v.idn_cancelada = 'N'
            AND v.codoper IN (110,100,137,138)
            --AND (v.codfilial = ?)
            AND v.num_nf IS NOT NULL
            --AND (afr.anexo_id IS NOT NULL or ane.anexo_id IS NOT NULL)
            AND v.num_nf = ?
            AND v.dtacomp BETWEEN '01.01.2024' AND '31.12.2040'
            AND (IIF(a.anexo_id IS NULL, 'Sem Canhotos', 'Com Canhotos') = 'Todas' OR ('Todas' = 'Todas'))
        ORDER BY v.num_nf, v.vendedor, anexo_id ASC
        """

        # Parâmetros na ordem correta
        params = [
            #data['codfilial'],
            data['numnf']
        ]

        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(sql, params)

        # Processar resultados
        columns = [desc[0] for desc in cursor.description]
        results = []
        for row in cursor.fetchall():
            row_data = {}
            for i, col in enumerate(columns):
                value = row[i]
                if isinstance(value, (bytes, bytearray)):
                    value = value.hex()
                elif isinstance(value, (date, datetime)):
                    value = value.isoformat()
                row_data[col] = value
            results.append(row_data)

        return jsonify({
            'success': True,
            'data': results,
            'count': len(results),
            'params': data  # Retorna os parâmetros usados para referência
        })

    except fdb.Error as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'sqlcode': e.sqlcode,
            'error_code': 'FIREBIRD_ERROR'
        }), 400
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'error_code': 'INTERNAL_ERROR'
        }), 500
    finally:
        try:
            cursor.close()
            conn.close()
        except:
            pass

@app.route('/vendas/nnota', methods=['POST'])
@require_apikey
def consulta_vendas_nota():
    """
    Endpoint específico para consulta de vendas com status de canhotos
    Parâmetros esperados:
    {
        "numnf": int
    }
    """
    try:
        data = request.get_json()
        
        # Validação dos parâmetros
        required_fields = ['numnf']
        for field in required_fields:
            if field not in data:
                return jsonify({
                    'success': False,
                    'error': f'Parâmetro obrigatório faltando: {field}',
                    'error_code': 'MISSING_PARAM'
                }), 400

        # Função para converter formatos de data
        def parse_date(date_str):
            try:
                if '.' in date_str:  # Formato DD.MM.YYYY
                    day, month, year = map(int, date_str.split('.'))
                    return date(year, month, day).strftime('%Y-%m-%d')
                else:  # Assume formato YYYY-MM-DD
                    return date_str
            except Exception as e:
                raise ValueError(f"Formato de data inválido: {date_str}. Use DD.MM.YYYY ou YYYY-MM-DD")

        # Consulta SQL fixa
        sql = """
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
            a.anexo_id,
            CASE WHEN a.descricao IS NULL THEN ' ' ELSE a.descricao END AS descricao,
            a.arquivo, v.codfilial as filial, fpr.dscforma
        FROM vendas v
        LEFT JOIN anexos_vendas av ON av.venda_id = v.venda_id
        LEFT JOIN faturas_receber fr ON fr.venda_id = v.venda_id
        LEFT JOIN boletos_faturas bf ON bf.faturas_receber_id = fr.faturas_receber_id
        LEFT JOIN anexos_faturas_receber afr ON afr.faturas_receber_id = fr.faturas_receber_id
        LEFT JOIN anexos a ON a.anexo_id = COALESCE(av.anexo_id, afr.anexo_id)
        --LEFT JOIN anexos a ON a.anexo_id = COALESCE(ane.anexo_id, afr.anexo_id, av.anexo_id)
        LEFT JOIN parceiros pa ON pa.parceiro = v.parceiro
        LEFT JOIN parceiros pv ON pv.parceiro = v.vendedor
        LEFT JOIN formas_pagar_receber fpr on fpr.forma = v.forma
        WHERE v.idn_cancelada = 'N'
            AND v.codoper IN (110,100,137,138)
            AND v.num_nf IS NOT NULL
            AND v.num_nf = ?
        ORDER BY v.num_nf, v.vendedor, anexo_id ASC
        """

        # Parâmetros na ordem correta
        params = [
            data['numnf']
        ]

        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(sql, params)

        # Processar resultados
        columns = [desc[0] for desc in cursor.description]
        results = []
        for row in cursor.fetchall():
            row_data = {}
            for i, col in enumerate(columns):
                value = row[i]
                if isinstance(value, (bytes, bytearray)):
                    value = value.hex()
                elif isinstance(value, (date, datetime)):
                    value = value.isoformat()
                row_data[col] = value
            results.append(row_data)

        return jsonify({
            'success': True,
            'data': results,
            'count': len(results),
            'params_used': {
                'numnf': data['numnf']
            }
        })

    except ValueError as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'error_code': 'INVALID_DATE_FORMAT'
        }), 400
    except fdb.Error as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'sqlcode': e.sqlcode,
            'error_code': 'FIREBIRD_ERROR'
        }), 400
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'error_code': 'INTERNAL_ERROR'
        }), 500
    finally:
        try:
            cursor.close()
        except:
            pass
        try:
            conn.close()
        except:
            pass

if __name__ == '__main__':
    #app.run(debug=True, host='0.0.0.0', port=5000)
    app.run(debug=False, host='0.0.0.0', port=5000)