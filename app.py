from flask import Flask, render_template, request, jsonify
import sqlite3
import socket
from datetime import datetime
import os

app = Flask(__name__)
DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "inventario.db")

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    with get_db() as conn:
        c = conn.cursor()
        c.execute('''
            CREATE TABLE IF NOT EXISTS maquinas (
                hostname TEXT PRIMARY KEY,
                setor TEXT DEFAULT 'Não definido',
                ip_local TEXT,
                sistema TEXT DEFAULT 'Windows',
                processador TEXT,
                placa_mae TEXT,
                ram_detalhe TEXT,
                ram_uso_pct INTEGER,
                disco_detalhe TEXT,
                disco_uso_pct INTEGER,
                smart_status TEXT,
                uptime TEXT,
                impressora_padrao TEXT,
                nivel_alerta TEXT,
                diagnostico TEXT,
                ultima_atualizacao TEXT,
                patrimonio_obs TEXT DEFAULT '',
                proxima_manutencao TEXT DEFAULT ''
            )
        ''')
        
        c.execute('''
            CREATE TABLE IF NOT EXISTS manutencoes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                hostname TEXT,
                tipo TEXT,
                tecnico TEXT,
                descricao TEXT,
                data_hora TEXT
            )
        ''')

        c.execute('''
            CREATE TABLE IF NOT EXISTS impressoras (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                nome TEXT,
                ip TEXT,
                setor TEXT,
                status TEXT DEFAULT 'Não verificado',
                ultima_verificacao TEXT DEFAULT 'Nunca'
            )
        ''')

        colunas_extras = [
            ("sistema", "TEXT DEFAULT 'Windows'"),
            ("impressora_padrao", "TEXT DEFAULT 'Nenhuma'"),
            ("patrimonio_obs", "TEXT DEFAULT ''"),
            ("proxima_manutencao", "TEXT DEFAULT ''")
        ]
        for col, tipo in colunas_extras:
            try:
                c.execute(f"ALTER TABLE maquinas ADD COLUMN {col} {tipo}")
            except sqlite3.OperationalError:
                pass

        conn.commit()

def testar_porta_9100(ip):
    try:
        with socket.create_connection((ip, 9100), timeout=1.5):
            return "Online"
    except Exception:
        return "Offline"

@app.route('/')
def index():
    with get_db() as conn:
        c = conn.cursor()
        c.execute("SELECT * FROM maquinas ORDER BY setor ASC, hostname ASC")
        rows = c.fetchall()
        
        maquinas = []
        for r in rows:
            m = dict(r)
            c.execute("""
                SELECT data_hora, tipo, descricao 
                FROM manutencoes 
                WHERE hostname = ? 
                ORDER BY id DESC LIMIT 1
            """, (m['hostname'],))
            ult = c.fetchone()
            if ult:
                m['ultima_manutencao'] = f"{ult['data_hora']} ({ult['tipo']}): {ult['descricao']}"
            else:
                m['ultima_manutencao'] = None
            maquinas.append(m)

        c.execute("SELECT * FROM impressoras ORDER BY setor ASC, nome ASC")
        impressoras = [dict(imp) for imp in c.fetchall()]

    return render_template('index.html', maquinas=maquinas, impressoras=impressoras)

@app.route('/api/specs', methods=['POST'])
@app.route('/coletar', methods=['POST'])
def coletar():
    d = request.json or {}
    hostname = d.get('hostname', 'DESCONHECIDO').strip()
    agora = datetime.now().strftime('%d/%m/%Y %H:%M:%S')

    with get_db() as conn:
        c = conn.cursor()
        c.execute("SELECT setor, patrimonio_obs, proxima_manutencao FROM maquinas WHERE hostname = ?", (hostname,))
        atual = c.fetchone()

        setor = atual['setor'] if atual and atual['setor'] else d.get('setor', 'Não definido')
        patrimonio_obs = atual['patrimonio_obs'] if atual else ''
        proxima_manutencao = atual['proxima_manutencao'] if atual else ''

        c.execute('''
            INSERT OR REPLACE INTO maquinas (
                hostname, setor, ip_local, sistema, processador, placa_mae,
                ram_detalhe, ram_uso_pct, disco_detalhe, disco_uso_pct,
                smart_status, uptime, impressora_padrao, nivel_alerta,
                diagnostico, ultima_atualizacao, patrimonio_obs, proxima_manutencao
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            hostname,
            setor,
            d.get('ip_local', '0.0.0.0'),
            d.get('sistema', 'Windows'),
            d.get('processador', 'N/A'),
            d.get('placa_mae', 'N/A'),
            d.get('ram_detalhe', 'N/A'),
            int(d.get('ram_uso_pct', 0)),
            d.get('disco_detalhe', 'N/A'),
            int(d.get('disco_uso_pct', 0)),
            d.get('smart_status', 'Healthy'),
            d.get('uptime', 'N/A'),
            d.get('impressora_padrao', 'Nenhuma'),
            d.get('nivel_alerta', 'OK'),
            d.get('diagnostico', 'Operação normal'),
            agora,
            patrimonio_obs,
            proxima_manutencao
        ))
        conn.commit()

    return jsonify({"status": "sucesso"}), 200

@app.route('/setor/<hostname>', methods=['POST'])
def atualizar_setor(hostname):
    novo_setor = (request.json or {}).get('setor', 'Não definido').strip()
    with get_db() as conn:
        conn.execute("UPDATE maquinas SET setor = ? WHERE hostname = ?", (novo_setor, hostname))
        conn.commit()
    return jsonify({"status": "ok"})

@app.route('/meta/<hostname>', methods=['POST'])
def atualizar_meta(hostname):
    dados = request.json or {}
    patrimonio_obs = dados.get('patrimonio_obs', '').strip()
    proxima_manutencao = dados.get('proxima_manutencao', '').strip()
    with get_db() as conn:
        conn.execute("""
            UPDATE maquinas 
            SET patrimonio_obs = ?, proxima_manutencao = ?
            WHERE hostname = ?
        """, (patrimonio_obs, proxima_manutencao, hostname))
        conn.commit()
    return jsonify({"status": "ok"})

@app.route('/manutencao/<hostname>', methods=['GET', 'POST'])
def gerenciar_manutencao(hostname):
    with get_db() as conn:
        c = conn.cursor()
        if request.method == 'POST':
            d = request.json or {}
            agora = datetime.now().strftime('%d/%m/%Y %H:%M')
            c.execute('''
                INSERT INTO manutencoes (hostname, tipo, tecnico, descricao, data_hora)
                VALUES (?, ?, ?, ?, ?)
            ''', (
                hostname,
                d.get('tipo', 'Preventiva'),
                d.get('tecnico', 'José (TI)'),
                d.get('descricao', ''),
                agora
            ))
            conn.commit()
            return jsonify({"status": "ok"})
        else:
            c.execute("SELECT * FROM manutencoes WHERE hostname = ? ORDER BY id DESC", (hostname,))
            lista = [dict(row) for row in c.fetchall()]
            return jsonify(lista)

@app.route('/deletar/<hostname>', methods=['POST'])
def deletar_maquina(hostname):
    with get_db() as conn:
        conn.execute("DELETE FROM maquinas WHERE hostname = ?", (hostname,))
        conn.execute("DELETE FROM manutencoes WHERE hostname = ?", (hostname,))
        conn.commit()
    return jsonify({"status": "ok"})

@app.route('/impressora/adicionar', methods=['POST'])
def adicionar_impressora():
    d = request.json or {}
    nome = d.get('nome', '').strip()
    ip = d.get('ip', '').strip()
    setor = d.get('setor', 'Geral').strip()
    
    status = testar_porta_9100(ip)
    agora = datetime.now().strftime('%d/%m %H:%M')

    with get_db() as conn:
        conn.execute('''
            INSERT INTO impressoras (nome, ip, setor, status, ultima_verificacao)
            VALUES (?, ?, ?, ?, ?)
        ''', (nome, ip, setor, status, agora))
        conn.commit()
    return jsonify({"status": "ok"})

@app.route('/impressora/testar/<int:id>', methods=['POST'])
def testar_impressora(id):
    with get_db() as conn:
        c = conn.cursor()
        c.execute("SELECT ip FROM impressoras WHERE id = ?", (id,))
        row = c.fetchone()
        if row:
            status = testar_porta_9100(row['ip'])
            agora = datetime.now().strftime('%d/%m %H:%M')
            c.execute("""
                UPDATE impressoras 
                SET status = ?, ultima_verificacao = ? 
                WHERE id = ?
            """, (status, agora, id))
            conn.commit()
    return jsonify({"status": "ok"})

@app.route('/impressora/deletar/<int:id>', methods=['POST'])
def deletar_impressora(id):
    with get_db() as conn:
        conn.execute("DELETE FROM impressoras WHERE id = ?", (id,))
        conn.commit()
    return jsonify({"status": "ok"})

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000, debug=True)