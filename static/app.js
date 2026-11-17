const svgMoon = '<svg class="icon" viewBox="0 0 24 24"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>';
const svgSun = '<svg class="icon" viewBox="0 0 24 24"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>';

document.addEventListener("DOMContentLoaded", function() {
    const temaSalvo = localStorage.getItem("theme") || "dark";
    document.documentElement.setAttribute("data-theme", temaSalvo);
    atualizarBotaoTema(temaSalvo);

    document.querySelectorAll(".progress-fill").forEach(function(bar) {
        const w = bar.getAttribute("data-width") || 0;
        bar.style.width = w + "%";
    });

    const abaSalva = localStorage.getItem("abaAtiva") || "inventario";
    mudarAba(abaSalva);
});

function mudarAba(aba) {
    const viewInv = document.getElementById("view-inventario");
    const viewDash = document.getElementById("view-dashboard");
    const btnInv = document.getElementById("tabBtnInv");
    const btnDash = document.getElementById("tabBtnDash");
    const wrapperBusca = document.getElementById("wrapperBusca");

    if (aba === "dashboard") {
        viewInv.style.display = "none";
        viewDash.style.display = "block";
        btnInv.classList.remove("active");
        btnDash.classList.add("active");
        wrapperBusca.style.display = "none";
    } else {
        viewInv.style.display = "block";
        viewDash.style.display = "none";
        btnDash.classList.remove("active");
        btnInv.classList.add("active");
        wrapperBusca.style.display = "flex";
    }
    localStorage.setItem("abaAtiva", aba);
}

function alternarTema() {
    const temaAtual = document.documentElement.getAttribute("data-theme");
    const novoTema = temaAtual === "dark" ? "light" : "dark";
    document.documentElement.setAttribute("data-theme", novoTema);
    localStorage.setItem("theme", novoTema);
    atualizarBotaoTema(novoTema);
}

function atualizarBotaoTema(tema) {
    const btn = document.getElementById("btnTheme");
    if (tema === "dark") {
        btn.innerHTML = svgSun;
        btn.title = "Mudar para Modo Claro";
    } else {
        btn.innerHTML = svgMoon;
        btn.title = "Mudar para Modo Escuro";
    }
}

let hostSelecionado = "";

function abrirModalMeta(el) {
    hostSelecionado = el.dataset.host;
    document.getElementById('metaHost').innerText = hostSelecionado;
    document.getElementById('inputPatrimonio').value = el.dataset.pat || "";
    document.getElementById('inputProximaManut').value = el.dataset.prox || "";
    document.getElementById('modalMeta').style.display = 'flex';
}

function salvarMeta() {
    const patrimonio_obs = document.getElementById('inputPatrimonio').value;
    const proxima_manutencao = document.getElementById('inputProximaManut').value;

    fetch('/meta/' + hostSelecionado, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ patrimonio_obs, proxima_manutencao })
    }).then(function(r) {
        if (r.ok) {
            fecharModais();
            window.location.reload();
        } else {
            alert("Erro ao salvar metadados.");
        }
    });
}

function exportarCSV() {
    const linhas = document.querySelectorAll("#tabela-maquinas tr");
    let csv = [];
    linhas.forEach(function(linha) {
        if (linha.style.display === "none") return;
        const cols = linha.querySelectorAll("th:not(.col-acoes), td:not(.col-acoes)");
        let dadosLinha = [];
        cols.forEach(function(col) {
            let texto = col.innerText.replace(/(\r\n|\n|\r)/gm, " | ").replace(/\s+/g, " ").trim();
            texto = '"' + texto.replace(/"/g, '""') + '"';
            dadosLinha.push(texto);
        });
        if (dadosLinha.length > 0) csv.push(dadosLinha.join(";"));
    });

    const csvContent = "\uFEFF" + csv.join("\n");
    const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    const hoje = new Date().toISOString().slice(0, 10);
    link.download = "inventario_ti_clinica_" + hoje + ".csv";
    link.click();
}

function abrirModalImpressoras() {
    document.getElementById('modalImpressoras').style.display = 'flex';
}

function adicionarImpressora() {
    const nome = document.getElementById('impNome').value.trim();
    const ip = document.getElementById('impIp').value.trim();
    const setor = document.getElementById('impSetor').value.trim() || 'Geral';
    if (!nome || !ip) { alert("Preencha Nome e IP."); return; }

    fetch('/impressora/adicionar', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ nome, ip, setor })
    }).then(function(r) { if (r.ok) window.location.reload(); });
}

function testarImpressora(id) {
    fetch('/impressora/testar/' + id, { method: 'POST' })
    .then(function(r) { if (r.ok) window.location.reload(); });
}

function removerImpressora(id) {
    if (confirm("Remover esta impressora?")) {
        fetch('/impressora/deletar/' + id, { method: 'POST' })
        .then(function(r) { if (r.ok) window.location.reload(); });
    }
}

function editarSetor(hostname, setorAtual) {
    const novoSetor = prompt("Setor para " + hostname + ":", setorAtual);
    if (novoSetor !== null && novoSetor.trim() !== "") {
        fetch('/setor/' + hostname, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ setor: novoSetor.trim() })
        }).then(function(r) { if (r.ok) window.location.reload(); });
    }
}

function abrirModalManutencao(hostname) {
    hostSelecionado = hostname;
    document.getElementById('manutHost').innerText = hostname;
    document.getElementById('manutDesc').value = "";
    document.getElementById('modalManutencao').style.display = 'flex';
}

function salvarManutencao() {
    const tipo = document.getElementById('manutTipo').value;
    const tecnico = document.getElementById('manutTecnico').value;
    const descricao = document.getElementById('manutDesc').value;
    if (!descricao.trim()) { alert("Digite a descrição."); return; }

    fetch('/manutencao/' + hostSelecionado, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tipo, tecnico, descricao })
    }).then(function(r) { if (r.ok) { fecharModais(); window.location.reload(); } });
}

function verHistoricoManutencao(hostname) {
    document.getElementById('histHost').innerText = hostname;
    const container = document.getElementById('listaHistorico');
    container.innerHTML = "Carregando histórico...";
    document.getElementById('modalHistorico').style.display = 'flex';

    fetch('/manutencao/' + hostname).then(function(r) { return r.json(); }).then(function(lista) {
        if (!lista.length) { 
            container.innerHTML = "<p style='color:var(--text-muted); text-align:center; padding: 15px;'>Nenhum histórico registrado para esta máquina.</p>"; 
            return; 
        }
        var html = "";
        for (var i = 0; i < lista.length; i++) {
            var item = lista[i];
            var badgeClass = item.tipo === 'Corretiva' ? 'vermelho' : 'verde';
            html += '<div class="hist-item"><div style="display:flex; justify-content:space-between; margin-bottom:4px;"><strong>' + item.data_hora + '</strong><span class="badge ' + badgeClass + '">' + item.tipo + '</span></div><div style="color:var(--text-color);">' + item.descricao + '</div><div style="font-size:11px; color:var(--text-muted); margin-top:4px;">Técnico: ' + item.tecnico + '</div></div>';
        }
        container.innerHTML = html;
    });
}

function fecharModais() {
    document.getElementById('modalImpressoras').style.display = 'none';
    document.getElementById('modalManutencao').style.display = 'none';
    document.getElementById('modalHistorico').style.display = 'none';
    document.getElementById('modalMeta').style.display = 'none';
}

function removerMaquina(hostname) {
    if (confirm('Deseja realmente remover a máquina "' + hostname + '" do inventário?')) {
        fetch('/deletar/' + hostname, { method: 'POST' }).then(function(r) { if (r.ok) window.location.reload(); });
    }
}

function filtrarTabela() {
    const termo = document.getElementById("filtro").value.toLowerCase();
    document.querySelectorAll("#tabela-maquinas tbody tr").forEach(function(linha) {
        linha.style.display = linha.innerText.toLowerCase().includes(termo) ? "" : "none";
    });
}