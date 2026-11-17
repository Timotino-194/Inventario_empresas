🖥️ Sistema de Inventário e Monitoramento de TI
Aplicação web desenvolvida em Python (Flask) com agente de coleta nativo em PowerShell, projetada para monitoramento de estações de trabalho Windows, diagnóstico preventivo de hardware e gestão de impressoras de rede.

🚀 Funcionalidades
Coleta Automatizada via Agente (coleta/): Leitura via WMI/CIM de Hostname, IP local, Sistema Operacional, Processador, Placa-Mãe, Memória RAM, Uptime, Impressora Padrão e todas as partições de armazenamento fixo com status S.M.A.R.T.

Diagnóstico Inteligente: Classificação automática (OK, AVISO, CRÍTICO) baseada em saúde de disco, ocupação de armazenamento, uso de RAM e tempo de atividade sem reinicialização (fadiga de sistema).

Dashboard Analítico: Visão consolidada com distribuição de Sistemas Operacionais, saúde geral do parque, ranking de consumo de RAM/Disco e divisão por setores.

Gestão de Manutenções e Ativos: Histórico completo de preventivas/corretivas por máquina, agendamento de próximas manutenções e controle de etiquetas de patrimônio/responsável.

Monitoramento de Impressoras de Rede: Verificação ativa de disponibilidade via socket TCP na porta 9100 e acesso rápido ao painel web de insumos.

Exportação e Interface: Suporte nativo a Modo Claro/Escuro, filtros em tempo real, exportação para CSV (Excel) e impressão formatada em PDF.

📂 Estrutura do Projeto
app.py: Servidor Flask e API REST (/api/specs)

requirements.txt: Dependências Python

coleta/1_Coletar_Agora.bat: Executável rápido para estações Windows

coleta/collector.ps1: Script PowerShell de coleta de hardware (WMI/CIM)

static/app.js: Lógica de interface, modais e exportação CSV

static/style.css: Estilização e temas Claro/Escuro

templates/index.html: Interface principal (Inventário e Dashboard)

🛠️ Tecnologias Utilizadas
Backend: Python 3, Flask, SQLite3

Frontend: HTML5, CSS3 (Variáveis CSS / Tema Dark & Light), JavaScript Vanilla, Ícones SVG

Agente Cliente: PowerShell (Get-CimInstance, Invoke-RestMethod) & Batch Script (.bat)

⚙️ Como Executar
1. Subir o Servidor Web (Máquina Central)
Clone o repositório: git clone [https://github.com/timotino-194/NOME-DO-REPOSITORIO.git](https://github.com/timotino-194/NOME-DO-REPOSITORIO.git)

Entre na pasta: cd NOME-DO-REPOSITORIO

Instale as dependências: pip install -r requirements.txt

Inicie o servidor: python app.py

Acesse no navegador: [http://127.0.0.1:5000](http://127.0.0.1:5000)

2. Executar a Coleta nas Estações Windows
Abra o arquivo coleta/collector.ps1 e altere a variável $ServerHost na linha 2 informando o Hostname ou IP da máquina onde o servidor Flask está rodando (ex: $ServerHost = "IP-OU-NOME-DO-SERVIDOR").

Copie a pasta coleta/ para a máquina cliente (ou execute via rede) e dê um duplo clique em 1_Coletar_Agora.bat.

Os dados de hardware aparecerão automaticamente no painel web.

Depois de salvar (Ctrl + S), rode os 3 comandos no terminal do VS Code para enviar ao GitHub:

Bash
git add README.md
git commit -m "docs: adiciona README do projeto"
git push
