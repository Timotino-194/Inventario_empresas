# NOME OU IP DO TEU PC QUE RODA O VSCODE:
$ServerHost = "Servidor TI"

if ($env:COMPUTERNAME -eq $ServerHost) {
    $TargetHost = "127.0.0.1"
} else {
    $ResolvedIp = (Resolve-DnsName -Name $ServerHost -Type A -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
    $TargetHost = if ($ResolvedIp) { $ResolvedIp } else { $ServerHost }
}

$ServerUrl = "http://${TargetHost}:5000/api/specs"

Write-Host "Coletando especificacoes de hardware e todos os discos..." -ForegroundColor Cyan

# 1. Hostname, Sistema Operacional (limpo) e Uptime
$ComputerName = $env:COMPUTERNAME
$OSInfo = Get-CimInstance Win32_OperatingSystem
$OSArch = $OSInfo.OSArchitecture
$OSClean = ($OSInfo.Caption -replace "^Microsoft\s+", "").Trim()
$OS = "$OSClean ($OSArch)"

$UptimeSpan = (Get-Date) - $OSInfo.LastBootUpTime
$Uptime = "$($UptimeSpan.Days)d $($UptimeSpan.Hours)h $($UptimeSpan.Minutes)m"

# 2. IP Local da Rede
$LocalIp = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null }).IPv4Address.IPAddress | Select-Object -First 1
if (-not $LocalIp) { $LocalIp = "127.0.0.1" }

# 3. Processador e Placa-Mãe
$CPU = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim()
$Board = Get-CimInstance Win32_BaseBoard
$Motherboard = "$($Board.Manufacturer) $($Board.Product)".Trim()

# 4. Memória RAM + Quantidade de Pentes
$TotalRAM_GB = [Math]::Round($OSInfo.TotalVisibleMemorySize / 1MB, 1)
$FreeRAM_GB = [Math]::Round($OSInfo.FreePhysicalMemory / 1MB, 1)
$UsedRAM_GB = [Math]::Round($TotalRAM_GB - $FreeRAM_GB, 1)
$RAM_Percent = [Math]::Round(($UsedRAM_GB / $TotalRAM_GB) * 100, 0)
$RamSticks = @(Get-CimInstance Win32_PhysicalMemory).Count

# 5. Todos os Discos Fixos (C:, D:, E:...) + Tipo (SSD/HDD) + S.M.A.R.T.
$LogicalDisks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
$DiskStrings = @()
$MaxDiskPercent = 0

foreach ($ld in $LogicalDisks) {
    if ($ld.Size -gt 0) {
        $TotalGB = [Math]::Round($ld.Size / 1GB, 0)
        $FreeGB = [Math]::Round($ld.FreeSpace / 1GB, 0)
        $UsedGB = $TotalGB - $FreeGB
        $Pct = [Math]::Round(($UsedGB / $TotalGB) * 100, 0)
        if ($Pct -gt $MaxDiskPercent) { $MaxDiskPercent = $Pct }

        $MediaType = "Disco"
        $DriveLetter = $ld.DeviceID.TrimEnd(':')
        try {
            $DiskNum = (Get-Partition -DriveLetter $DriveLetter -ErrorAction Stop | Get-Disk -ErrorAction Stop).Number
            $Phys = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq $DiskNum } | Select-Object -First 1
            if ($Phys.MediaType -and $Phys.MediaType -ne "Unspecified") { $MediaType = $Phys.MediaType }
        } catch {}

        $DiskStrings += "$($ld.DeviceID) $MediaType $TotalGB GB ($FreeGB GB livres - $Pct%)"
    }
}

$DiscoDetalhe = if ($DiskStrings.Count -gt 0) { $DiskStrings -join " | " } else { "N/A" }
$Disk_Percent = $MaxDiskPercent

# Verifica S.M.A.R.T. de todos os discos físicos instalados
$SmartStatus = "Healthy"
try {
    $AllPhys = Get-PhysicalDisk
    $Unhealthy = $AllPhys | Where-Object { $_.HealthStatus -ne "Healthy" }
    if ($Unhealthy) {
        $SmartStatus = ($Unhealthy | ForEach-Object { "$($_.FriendlyName): $($_.HealthStatus)" }) -join ", "
    }
} catch {}

# 6. Impressora Padrão do Windows
$DefaultPrinter = "Nenhuma"
try {
    $PrinterObj = Get-CimInstance Win32_Printer | Where-Object { $_.Default -eq $true } | Select-Object -First 1
    if ($PrinterObj -and $PrinterObj.Name) { $DefaultPrinter = $PrinterObj.Name }
} catch {}

# 7. Diagnóstico Automático e Nível de Alerta
$NivelAlerta = "OK"
$Motivos = @()

if ($SmartStatus -ne "Healthy") {
    $NivelAlerta = "CRITICO"
    $Motivos += "Saude do disco comprometida ($SmartStatus)"
}
if ($Disk_Percent -ge 90) {
    $NivelAlerta = "CRITICO"
    $Motivos += "Armazenamento critico ($Disk_Percent% ocupado)"
} elseif ($Disk_Percent -ge 80 -and $NivelAlerta -ne "CRITICO") {
    $NivelAlerta = "AVISO"
    $Motivos += "Espaco em disco reduzido ($Disk_Percent% ocupado)"
}

if ($RAM_Percent -ge 90) {
    if ($NivelAlerta -ne "CRITICO") { $NivelAlerta = "AVISO" }
    $Motivos += "Uso elevado de RAM ($RAM_Percent%)"
}

if ($UptimeSpan.Days -ge 5) {
    if ($NivelAlerta -eq "OK") { $NivelAlerta = "AVISO" }
    $Motivos += "Ligado ha $($UptimeSpan.Days) dias sem reiniciar (Fadiga de sistema)"
}

$Diagnostico = if ($Motivos.Count -gt 0) { $Motivos -join " | " } else { "Operação normal" }

# Montando JSON em UTF-8
$Body = @{
    hostname          = $ComputerName
    ip_local          = $LocalIp
    sistema           = $OS
    placa_mae         = $Motherboard
    processador       = $CPU
    ram_detalhe       = "$TotalRAM_GB GB ($RamSticks pente(s)) - Uso: $UsedRAM_GB GB"
    ram_uso_pct       = $RAM_Percent
    disco_detalhe     = $DiscoDetalhe
    disco_uso_pct     = $Disk_Percent
    smart_status      = $SmartStatus
    impressora_padrao = $DefaultPrinter
    nivel_alerta      = $NivelAlerta
    diagnostico       = $Diagnostico
    uptime            = $Uptime
} | ConvertTo-Json

$BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)

try {
    Invoke-RestMethod -Uri $ServerUrl -Method Post -Body $BodyBytes -ContentType "application/json; charset=utf-8" -TimeoutSec 10 -ErrorAction Stop | Out-Null
    Write-Host "[OK] Sucesso! Dados de [$ComputerName] enviados para o painel!" -ForegroundColor Green
} catch {
    Write-Host "[ERRO] Falha ao conectar em $ServerUrl. Verifique se o servidor Flask esta aberto." -ForegroundColor Red
    Write-Host "Detalhe: $_" -ForegroundColor Yellow
}