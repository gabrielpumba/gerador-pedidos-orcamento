param(
    [switch]$NoOpen,
    [switch]$ConfigurarNuvem
)

# Servidor local leve, seguro e com Sincronizacao em Nuvem (GitHub) para o aplicativo Okada Pedidos
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$port = 8085
$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $baseDir) { $baseDir = (Get-Location).Path }
$parentDir = Split-Path $baseDir -Parent
$bigSolutionDir = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Gabriel\big solution'
$configFile = if (Test-Path $bigSolutionDir) {
    Join-Path $bigSolutionDir 'github_sync_config.json'
} else {
    Join-Path $parentDir 'github_sync_config.json'
}
$repoSyncFile = Join-Path $baseDir 'repo_sync.txt'

function Obter-GitBlobSha([byte[]]$bytes) {
    $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
    $combined = New-Object byte[] ($header.Length + $bytes.Length)
    [System.Array]::Copy($header, 0, $combined, 0, $header.Length)
    [System.Array]::Copy($bytes, 0, $combined, $header.Length, $bytes.Length)
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    $hash = $sha1.ComputeHash($combined)
    return ($hash | ForEach-Object { $_.ToString("x2") }) -join ""
}

function Obter-Versao-Sw([string]$conteudoSw) {
    if ($conteudoSw -match "okada-v(\d+)") {
        return [int]$matches[1]
    }
    return 0
}

function Sincronizar-Pasta-Beta {
    $raizRef = if (Test-Path $bigSolutionDir) { $bigSolutionDir } else { $parentDir }
    $betaDir = Join-Path $raizRef 'Okada Pedidos - Versao Beta'
    $projDir = Join-Path $raizRef 'prorgrama pedido'
    $instDir = Join-Path $env:USERPROFILE 'Okada Pedidos'

    $arquivosCopiar = @(
        'index.html', 'sw.js', 'dados.enc', 'dados.js', 'distribuidoras.js',
        'tabelas_padrao.json', 'tabelas_padrao.js', 'manifest.webmanifest',
        'icon-192.png', 'icon-512.png', 'logo-okada.webp', 'logo-okada-pdf.webp',
        'okada.ico', 'robots.txt', '_headers', 'COMO ABRIR O APLICATIVO.txt',
        'Fechar Okada Pedidos.bat', 'Iniciar Okada Pedidos.bat',
        'Iniciar Okada Pedidos.vbs', 'Instalar Okada Pedidos.bat', 'instalar.vbs',
        'servidor.ps1', 'repo_sync.txt', 'README.md'
    )

    foreach ($destDir in @($betaDir, $projDir, $instDir)) {
        if ((Test-Path $destDir) -and ($destDir.TrimEnd('\') -ne $baseDir.TrimEnd('\'))) {
            foreach ($arq in $arquivosCopiar) {
                $orig = Join-Path $baseDir $arq
                if (Test-Path $orig) {
                    Copy-Item -Path $orig -Destination $destDir -Force -ErrorAction SilentlyContinue
                }
            }
            foreach ($pasta in @('fonts', 'logos', 'pdfjs')) {
                $origP = Join-Path $baseDir $pasta
                if (Test-Path $origP) {
                    Copy-Item -Path $origP -Destination $destDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    try {
        $zipDest = Join-Path $raizRef 'Okada Pedidos - Versao Beta.zip'
        $pastaOrigZip = if (Test-Path $betaDir) { $betaDir } else { $baseDir }
        Compress-Archive -Path "$pastaOrigZip\*" -DestinationPath $zipDest -Force -ErrorAction SilentlyContinue
    } catch { }
}

function Configurar-GitHub-Interativo {
    Add-Type -AssemblyName Microsoft.VisualBasic
    Add-Type -AssemblyName System.Windows.Forms

    $urlToken = "https://github.com/settings/tokens/new?description=Okada+Pedidos+Sync&scopes=repo"
    $resp = [System.Windows.Forms.MessageBox]::Show(
        "Para ativar a atualizacao automatica via GitHub, voce precisa gerar um Token de Acesso (leva 20 segundos).`r`n`r`n1. Vamos abrir a pagina do GitHub ja preenchida para voce.`r`n2. Role ate o final da pagina e clique no botao verde 'Generate token'.`r`n3. Copie o codigo gerado (comeca com ghp_...) e cole na proxima janela.`r`n`r`nDeseja abrir a pagina do GitHub agora?",
        "Configurar Sincronizacao Automatica (GitHub)",
        [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    if ($resp -eq [System.Windows.Forms.DialogResult]::Cancel) { return $null }
    if ($resp -eq [System.Windows.Forms.DialogResult]::Yes) {
        Start-Process $urlToken
    }

    $token = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Cole abaixo o Token gerado no GitHub (ex: ghp_xxxxxxxxxxxxxxxxxxxx):",
        "Chave de Sincronizacao GitHub",
        ""
    ).Trim()

    if ([string]::IsNullOrEmpty($token)) { return $null }

    try {
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept"        = "application/vnd.github+json"
            "User-Agent"    = "OkadaPedidos-Sync"
        }
        $user = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -Method Get -TimeoutSec 15
        $owner = $user.login
        $sugestaoRepo = "okada-pedidos-sync"
        try {
            $ultimosRepos = Invoke-RestMethod -Uri "https://api.github.com/user/repos?sort=created&per_page=5" -Headers $headers -Method Get -TimeoutSec 10
            if ($ultimosRepos -and $ultimosRepos.Count -gt 0) {
                $sugestaoRepo = $ultimosRepos[0].name
            }
        } catch { }

        $repoInput = [Microsoft.VisualBasic.Interaction]::InputBox(
            "Confirme o nome do repositorio no seu GitHub ($owner):",
            "Repositorio GitHub",
            $sugestaoRepo
        ).Trim()
        if ([string]::IsNullOrEmpty($repoInput)) { return $null }
        if ($repoInput -match "/([^/]+)$") { $repoInput = $matches[1] }
        $repoName = $repoInput.Replace(".git", "")
        $repoSlug = "$owner/$repoName"

        # Verifica se o repositorio ja existe; se nao, cria automaticamente
        $repoExists = $false
        try {
            $null = Invoke-RestMethod -Uri "https://api.github.com/repos/$repoSlug" -Headers $headers -Method Get -TimeoutSec 10
            $repoExists = $true
        } catch {
            $repoExists = $false
        }

        if (-not $repoExists) {
            $createBody = @{
                name        = $repoName
                description = "Sincronizacao automatica Okada Pedidos"
                private     = $false
                auto_init   = $true
            } | ConvertTo-Json
            $null = Invoke-RestMethod -Uri "https://api.github.com/user/repos" -Headers $headers -Method Post -Body $createBody -ContentType "application/json" -TimeoutSec 20
            Start-Sleep -Seconds 2
        }

        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        $cfgObj = @{
            owner = $owner
            repo  = $repoName
            token = $token
        } | ConvertTo-Json
        [System.IO.File]::WriteAllText($configFile, $cfgObj, $utf8NoBom)
        [System.IO.File]::WriteAllText($repoSyncFile, $repoSlug, $utf8NoBom)

        return @{ owner = $owner; repo = $repoName; token = $token }
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Nao foi possivel conectar ao GitHub com este Token.`r`nDetalhe: $($_.Exception.Message)",
            "Erro na Configuracao",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return $null
    }
}

function Publicar-No-GitHub([switch]$PermitirInterativo) {
    $cfg = $null
    if (Test-Path $configFile) {
        try {
            $cfg = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch { $cfg = $null }
    }
    if ((-not $cfg -or -not $cfg.token) -and $PermitirInterativo) {
        $cfg = Configurar-GitHub-Interativo
    }
    if (-not $cfg -or -not $cfg.token) {
        return @{ ok = $false; erro = "GitHub nao configurado" }
    }

    try {
        $repoSlug = "$($cfg.owner)/$($cfg.repo)"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($repoSyncFile, $repoSlug, $utf8NoBom)

        $headers = @{
            "Authorization" = "Bearer $($cfg.token)"
            "Accept"        = "application/vnd.github+json"
            "User-Agent"    = "OkadaPedidos-Sync"
        }

        # Se o repositorio foi criado vazio no GitHub (sem nenhum commit inicial), inicializa com o README.md
        $headSha = $null
        try {
            $refResp = Invoke-RestMethod -Uri "https://api.github.com/repos/$repoSlug/git/ref/heads/main" -Headers $headers -Method Get -TimeoutSec 10
            $headSha = $refResp.object.sha
        } catch {
            $readmePath = Join-Path $baseDir 'README.md'
            $readmeBytes = if (Test-Path $readmePath) { [System.IO.File]::ReadAllBytes($readmePath) } else { [System.Text.Encoding]::UTF8.GetBytes("# Okada Pedidos`n") }
            $initBody = @{
                message = "Inicializacao do repositorio Okada Pedidos"
                content = [Convert]::ToBase64String($readmeBytes)
                branch  = "main"
            } | ConvertTo-Json -Compress
            $null = Invoke-RestMethod -Uri "https://api.github.com/repos/$repoSlug/contents/README.md" -Headers $headers -Method Put -Body $initBody -ContentType "application/json" -TimeoutSec 30
            Start-Sleep -Seconds 1
            $refResp = Invoke-RestMethod -Uri "https://api.github.com/repos/$repoSlug/git/ref/heads/main" -Headers $headers -Method Get -TimeoutSec 10
            $headSha = $refResp.object.sha
        }

        $commitResp = Invoke-RestMethod -Uri "https://api.github.com/repos/$repoSlug/git/commits/$headSha" -Headers $headers -Method Get -TimeoutSec 10
        $baseTreeSha = $commitResp.tree.sha

        # Busca SHAs atuais no repositorio (incluindo subpastas) para enviar apenas os arquivos novos ou alterados
        $remoteShas = @{}
        try {
            $treeResp = Invoke-RestMethod -Uri "https://api.github.com/repos/$repoSlug/git/trees/$($baseTreeSha)?recursive=1" -Headers $headers -Method Get -TimeoutSec 15
            foreach ($item in $treeResp.tree) {
                if ($item.type -eq 'blob') {
                    $remoteShas[$item.path] = $item.sha
                }
            }
        } catch { }

        $arquivosRaiz = @(
            'README.md', 'index.html', 'tabelas_padrao.json', 'tabelas_padrao.js',
            'dados.js', 'dados.enc', 'distribuidoras.js', 'manifest.webmanifest',
            'icon-192.png', 'icon-512.png', 'logo-okada.webp', 'logo-okada-pdf.webp',
            'okada.ico', 'robots.txt', '_headers', 'COMO ABRIR O APLICATIVO.txt',
            'Fechar Okada Pedidos.bat', 'Iniciar Okada Pedidos.bat',
            'Iniciar Okada Pedidos.vbs', 'Instalar Okada Pedidos.bat', 'instalar.vbs',
            'servidor.ps1', 'repo_sync.txt', 'sw.js'
        )

        $listaCompleta = New-Object System.Collections.Generic.List[string]
        foreach ($a in $arquivosRaiz) {
            if (Test-Path (Join-Path $baseDir $a)) {
                $listaCompleta.Add($a)
            }
        }
        foreach ($pasta in @('fonts', 'logos', 'pdfjs')) {
            $dirP = Join-Path $baseDir $pasta
            if (Test-Path $dirP) {
                Get-ChildItem -Path $dirP -File | ForEach-Object {
                    $listaCompleta.Add("$pasta/$($_.Name)")
                }
            }
        }

        $novosItensTree = @()
        foreach ($relPath in $listaCompleta) {
            $caminhoLocal = Join-Path $baseDir ($relPath -replace '/', '\')
            if (-not (Test-Path $caminhoLocal)) { continue }
            $bytes = [System.IO.File]::ReadAllBytes($caminhoLocal)
            $localSha = Obter-GitBlobSha $bytes
            $remSha = $remoteShas[$relPath]

            if ($remSha -and ($remSha -eq $localSha)) {
                continue
            }

            $blobBody = @{
                content  = [Convert]::ToBase64String($bytes)
                encoding = "base64"
            } | ConvertTo-Json -Compress
            $blobResp = Invoke-RestMethod -Uri "https://api.github.com/repos/$repoSlug/git/blobs" -Headers $headers -Method Post -Body $blobBody -ContentType "application/json" -TimeoutSec 60

            $novosItensTree += @{
                path = $relPath
                mode = "100644"
                type = "blob"
                sha  = $blobResp.sha
            }
        }

        if ($novosItensTree.Count -gt 0) {
            $newTreeBody = @{
                base_tree = $baseTreeSha
                tree      = $novosItensTree
            } | ConvertTo-Json -Depth 5 -Compress
            $newTreeResp = Invoke-RestMethod -Uri "https://api.github.com/repos/$repoSlug/git/trees" -Headers $headers -Method Post -Body $newTreeBody -ContentType "application/json" -TimeoutSec 30

            $newCommitBody = @{
                message = "Atualizacao automatica Okada Pedidos"
                tree    = $newTreeResp.sha
                parents = @($headSha)
            } | ConvertTo-Json -Compress
            $newCommitResp = Invoke-RestMethod -Uri "https://api.github.com/repos/$repoSlug/git/commits" -Headers $headers -Method Post -Body $newCommitBody -ContentType "application/json" -TimeoutSec 30

            $patchRefBody = @{
                sha   = $newCommitResp.sha
                force = $true
            } | ConvertTo-Json -Compress
            $null = Invoke-RestMethod -Uri "https://api.github.com/repos/$repoSlug/git/refs/heads/main" -Headers $headers -Method Patch -Body $patchRefBody -ContentType "application/json" -TimeoutSec 20
        }

        return @{ ok = $true; repo = $repoSlug; enviados = $novosItensTree.Count }
    } catch {
        return @{ ok = $false; erro = $_.Exception.Message }
    }
}

function Verificar-Atualizacao-Nuvem {
    $swLocalPath = Join-Path $baseDir 'sw.js'
    $verLocal = 0
    if (Test-Path $swLocalPath) {
        $verLocal = Obter-Versao-Sw ([System.IO.File]::ReadAllText($swLocalPath, [System.Text.Encoding]::UTF8))
    }
    $strVerLocal = if ($verLocal -gt 0) { "okada-v$verLocal" } else { "v1" }

    # Se este for o PC Principal (tem github_sync_config.json), nao sobrescreve os arquivos de desenvolvimento
    if (Test-Path $configFile) {
        return @{ atualizado = $false; motivo = "pc_principal"; versao = $strVerLocal }
    }
    if (-not (Test-Path $repoSyncFile)) {
        return @{ atualizado = $false; motivo = "sem_repo"; versao = $strVerLocal }
    }

    try {
        $repoSlug = (Get-Content $repoSyncFile -Raw -Encoding UTF8).Trim()
        if ([string]::IsNullOrEmpty($repoSlug)) {
            return @{ atualizado = $false; motivo = "repo_vazio"; versao = $strVerLocal }
        }

        # Busca o sw.js remoto sem cache
        $swRemotoTxt = $null
        try {
            $headersRaw = @{
                "Accept"     = "application/vnd.github.v3.raw"
                "User-Agent" = "OkadaPedidos-Updater"
            }
            $swRemotoTxt = Invoke-RestMethod -Uri "https://api.github.com/repos/$repoSlug/contents/sw.js" -Headers $headersRaw -Method Get -TimeoutSec 10
        } catch {
            $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            $swRemotoTxt = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/$repoSlug/main/sw.js?t=$ts" -Method Get -TimeoutSec 10
        }

        if (-not $swRemotoTxt) {
            return @{ atualizado = $false; versao = $strVerLocal; erro = "Sem resposta do GitHub" }
        }

        $verRemota = Obter-Versao-Sw ([string]$swRemotoTxt)
        if ($verRemota -le $verLocal) {
            return @{ atualizado = $false; versao = "okada-v$verLocal" }
        }

        Write-Host "[ATUALIZACAO] Nova versao encontrada na nuvem (okada-v$verRemota). Baixando..." -ForegroundColor Yellow

        # Obtem arvore remota para baixar apenas os arquivos que realmente mudaram
        $remoteShas = @{}
        try {
            $headersJson = @{ "Accept" = "application/vnd.github+json"; "User-Agent" = "OkadaPedidos-Updater" }
            $treeResp = Invoke-RestMethod -Uri "https://api.github.com/repos/$repoSlug/git/trees/main" -Headers $headersJson -Method Get -TimeoutSec 10
            foreach ($item in $treeResp.tree) {
                if ($item.type -eq 'blob') {
                    $remoteShas[$item.path] = $item.sha
                }
            }
        } catch { }

        $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $arquivosBaixar = @('index.html', 'tabelas_padrao.json', 'tabelas_padrao.js', 'dados.js', 'dados.enc', 'sw.js', 'servidor.ps1')
        foreach ($arq in $arquivosBaixar) {
            $destArq = Join-Path $baseDir $arq
            if ($remoteShas.ContainsKey($arq) -and (Test-Path $destArq)) {
                $bytesLocais = [System.IO.File]::ReadAllBytes($destArq)
                $shaLocal = Obter-GitBlobSha $bytesLocais
                if ($shaLocal -eq $remoteShas[$arq]) {
                    continue
                }
            }

            $tmpArq = "$destArq.tmp"
            $baixou = $false
            $wc = New-Object System.Net.WebClient
            try {
                $wc.Headers.Add("User-Agent", "OkadaPedidos-Updater")
                $wc.Headers.Add("Accept", "application/vnd.github.v3.raw")
                $wc.Headers.Add("Cache-Control", "no-cache")
                $wc.DownloadFile("https://api.github.com/repos/$repoSlug/contents/$arq", $tmpArq)
                $baixou = $true
            } catch {
                try {
                    $wc2 = New-Object System.Net.WebClient
                    $wc2.Headers.Add("User-Agent", "OkadaPedidos-Updater")
                    $wc2.Headers.Add("Cache-Control", "no-cache")
                    $wc2.DownloadFile("https://raw.githubusercontent.com/$repoSlug/main/$arq?t=$ts", $tmpArq)
                    $baixou = $true
                    $wc2.Dispose()
                } catch { }
            } finally {
                $wc.Dispose()
            }
            if ($baixou -and (Test-Path $tmpArq) -and ((Get-Item $tmpArq).Length -gt 0)) {
                Move-Item -Path $tmpArq -Destination $destArq -Force
            }
        }

        Write-Host "[OK] Aplicativo atualizado automaticamente para okada-v$verRemota!" -ForegroundColor Green
        return @{ atualizado = $true; versao = "okada-v$verRemota" }
    } catch {
        return @{ atualizado = $false; versao = $strVerLocal; erro = $_.Exception.Message }
    }
}

function Obter-Caminho-EmailConfig {
    $dir = Join-Path $env:LOCALAPPDATA 'OkadaPedidos'
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return (Join-Path $dir 'email_config.json')
}

function Proteger-Texto-Local([string]$texto) {
    if ([string]::IsNullOrEmpty($texto)) { return '' }
    try {
        $sec = ConvertTo-SecureString $texto -AsPlainText -Force
        return (ConvertFrom-SecureString $sec)
    } catch {
        return ''
    }
}

function Desproteger-Texto-Local([string]$cifrado) {
    if ([string]::IsNullOrEmpty($cifrado)) { return '' }
    try {
        $sec = ConvertTo-SecureString $cifrado
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try {
            return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    } catch {
        return ''
    }
}

function Ler-EmailConfig {
    $path = Obter-Caminho-EmailConfig
    if (-not (Test-Path $path)) { return $null }
    try {
        $obj = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $obj -or [string]::IsNullOrWhiteSpace($obj.email)) { return $null }
        return $obj
    } catch {
        return $null
    }
}

function Salvar-EmailConfig($dados) {
    $path = Obter-Caminho-EmailConfig
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $existente = Ler-EmailConfig
    $senhaEnc = ''
    if (-not [string]::IsNullOrEmpty($dados.senha)) {
        $senhaEnc = Proteger-Texto-Local ([string]$dados.senha)
    } elseif ($existente -and $existente.email -eq $dados.email -and $existente.senhaEnc) {
        $senhaEnc = [string]$existente.senhaEnc
    }
    $obj = @{
        email    = ([string]$dados.email).Trim()
        nome     = ([string]$dados.nome).Trim()
        smtpHost = ([string]$dados.smtpHost).Trim()
        smtpPort = if ($dados.smtpPort) { [int]$dados.smtpPort } else { 587 }
        smtpSsl  = if ($null -ne $dados.smtpSsl) { [bool]$dados.smtpSsl } else { $true }
        senhaEnc = $senhaEnc
    } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($path, $obj, $utf8NoBom)
}

function Enviar-Email-Smtp($payload) {
    $cfgSalva = Ler-EmailConfig
    $remetenteEmail = if ($payload.remetenteEmail) { ([string]$payload.remetenteEmail).Trim() } elseif ($cfgSalva) { [string]$cfgSalva.email } else { '' }
    $remetenteNome = if ($null -ne $payload.remetenteNome) { ([string]$payload.remetenteNome).Trim() } elseif ($cfgSalva) { [string]$cfgSalva.nome } else { 'Okada Representacoes' }
    $smtpHost = if ($payload.smtpHost) { ([string]$payload.smtpHost).Trim() } elseif ($cfgSalva) { [string]$cfgSalva.smtpHost } else { '' }
    $smtpPort = if ($payload.smtpPort) { [int]$payload.smtpPort } elseif ($cfgSalva -and $cfgSalva.smtpPort) { [int]$cfgSalva.smtpPort } else { 587 }
    $smtpSsl = if ($null -ne $payload.smtpSsl) { [bool]$payload.smtpSsl } elseif ($cfgSalva -and ($null -ne $cfgSalva.smtpSsl)) { [bool]$cfgSalva.smtpSsl } else { $true }

    $senha = ''
    if (-not [string]::IsNullOrEmpty($payload.senha)) {
        $senha = [string]$payload.senha
    } elseif ($cfgSalva -and $cfgSalva.senhaEnc -and ($cfgSalva.email -eq $remetenteEmail)) {
        $senha = Desproteger-Texto-Local ([string]$cfgSalva.senhaEnc)
    }

    if ([string]::IsNullOrWhiteSpace($remetenteEmail)) {
        return @{ ok = $false; erro = 'Informe o seu e-mail remetente para enviar.' }
    }
    if ([string]::IsNullOrWhiteSpace($senha)) {
        return @{ ok = $false; erro = 'Informe a senha do seu e-mail (ou senha de aplicativo).' }
    }
    if ([string]::IsNullOrWhiteSpace($smtpHost)) {
        return @{ ok = $false; erro = 'Informe o servidor SMTP do seu provedor de e-mail.' }
    }

    $paraLista = @()
    foreach ($p in (([string]$payload.para) -split '[,;]+')) {
        $t = $p.Trim()
        if (-not [string]::IsNullOrWhiteSpace($t)) { $paraLista += $t }
    }
    if ($paraLista.Count -eq 0) {
        return @{ ok = $false; erro = 'Informe pelo menos um e-mail de destinatario.' }
    }

    if ($payload.salvarConfig) {
        Salvar-EmailConfig @{
            email    = $remetenteEmail
            nome     = $remetenteNome
            smtpHost = $smtpHost
            smtpPort = $smtpPort
            smtpSsl  = $smtpSsl
            senha    = $senha
        }
    }

    $mail = $null
    $client = $null
    $ms = $null
    $att = $null
    try {
        $mail = New-Object System.Net.Mail.MailMessage
        if ([string]::IsNullOrWhiteSpace($remetenteNome)) {
            $mail.From = New-Object System.Net.Mail.MailAddress($remetenteEmail)
        } else {
            $mail.From = New-Object System.Net.Mail.MailAddress($remetenteEmail, $remetenteNome, [System.Text.Encoding]::UTF8)
        }
        foreach ($dest in $paraLista) {
            $mail.To.Add($dest)
        }
        if ($payload.ccSelf) {
            $mail.CC.Add($remetenteEmail)
        }
        $mail.Subject = if ($payload.assunto) { [string]$payload.assunto } else { 'Pedido Okada Representacoes' }
        $mail.SubjectEncoding = [System.Text.Encoding]::UTF8
        $mail.Body = if ($payload.mensagem) { [string]$payload.mensagem } else { '' }
        $mail.BodyEncoding = [System.Text.Encoding]::UTF8
        $mail.IsBodyHtml = $false

        if (-not [string]::IsNullOrWhiteSpace($payload.pdfBase64)) {
            $pdfBytes = [Convert]::FromBase64String([string]$payload.pdfBase64)
            $ms = New-Object System.IO.MemoryStream(, $pdfBytes)
            $pdfNome = if ($payload.pdfNome) { [string]$payload.pdfNome } else { 'Pedido.pdf' }
            $att = New-Object System.Net.Mail.Attachment($ms, $pdfNome, 'application/pdf')
            $mail.Attachments.Add($att)
        }

        $client = New-Object System.Net.Mail.SmtpClient($smtpHost, $smtpPort)
        $client.EnableSsl = $smtpSsl
        $client.UseDefaultCredentials = $false
        $client.Credentials = New-Object System.Net.NetworkCredential($remetenteEmail, $senha)
        $client.Timeout = 25000
        $client.Send($mail)

        return @{ ok = $true }
    } catch {
        $msg = $_.Exception.Message
        if ($_.Exception.InnerException) {
            $msg = "$msg ($($_.Exception.InnerException.Message))"
        }
        if ($msg -match '5\.7\.|535|Authentication|autentic|credentials|Username and Password') {
            $msg = "Falha de login no e-mail ($remetenteEmail). Verifique a senha ou se o provedor exige 'Senha de Aplicativo'. Detalhe: $msg"
        } elseif ($msg -match 'Failure sending mail|Unable to connect|timed out|No such host') {
            $msg = "Nao foi possivel conectar ao servidor $smtpHost`:$smtpPort. Verifique sua internet ou as configuracoes SMTP. Detalhe: $msg"
        }
        return @{ ok = $false; erro = $msg }
    } finally {
        if ($att) { try { $att.Dispose() } catch { } }
        if ($ms) { try { $ms.Dispose() } catch { } }
        if ($mail) { try { $mail.Dispose() } catch { } }
        if ($client) { try { $client.Dispose() } catch { } }
    }
}

# Modo de configuracao direta da nuvem
if ($ConfigurarNuvem) {
    Add-Type -AssemblyName System.Windows.Forms
    $res = Publicar-No-GitHub -PermitirInterativo
    if ($res.ok) {
        Sincronizar-Pasta-Beta
        [System.Windows.Forms.MessageBox]::Show(
            "Sincronizacao Automatica em Nuvem configurada com sucesso!`r`n`r`nRepositorio: $($res.repo)`r`n`r`n1. A pasta 'Okada Pedidos - Versao Beta' e o arquivo '.zip' foram atualizados.`r`n2. Envie este '.zip' apenas mais esta vez para a outra pessoa instalar.`r`n3. A partir de agora, sempre que voce clicar em 'GERAR COMPILACAO' no seu PC, o computador da outra pessoa vai atualizar sozinho ao abrir o app!",
            "Okada Pedidos - Nuvem Ativada",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    exit
}

$testUrl = "http://127.0.0.1:$port/"

function Abrir-App {
    $browsers = @(
        "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
        "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe",
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    foreach ($b in $browsers) {
        if ($b -and (Test-Path $b)) {
            Start-Process $b -ArgumentList "--app=$testUrl"
            return $b
        }
    }
    Start-Process $testUrl
    return "Navegador padrao"
}

# 0. Antes de abrir, verifica se ha atualizacao na nuvem (nos dispositivos Beta Tester)
Verificar-Atualizacao-Nuvem | Out-Null

# 1. Se o servidor ja estiver rodando, apenas abre a janela do app (se permitido)
try {
    $req = [System.Net.WebRequest]::Create($testUrl)
    $req.Timeout = 800
    $resp = $req.GetResponse()
    $resp.Close()
    Write-Host "[OK] O aplicativo ja estava ativo." -ForegroundColor Cyan
    if (-not $NoOpen) { Abrir-App | Out-Null }
    Start-Sleep -Seconds 1
    exit
} catch { }

# 2. Inicia o listener HTTP com tolerancia a portas ocupadas
$listener = $null
foreach ($p in 8085..8090) {
    try {
        $l = New-Object System.Net.HttpListener
        $l.Prefixes.Add("http://127.0.0.1:$p/")
        $l.Start()
        $port = $p
        $testUrl = "http://127.0.0.1:$port/"
        $listener = $l
        break
    } catch { }
}

if (-not $listener) {
    Write-Host "[AVISO] Nao foi possivel iniciar porta local, abrindo modo direto..." -ForegroundColor Yellow
    if (-not $NoOpen) {
        $htmlPath = Join-Path $baseDir 'index.html'
        Start-Process $htmlPath
    }
    exit
}

Write-Host "[OK] Servidor local ativo em: $testUrl" -ForegroundColor Green
if (-not $NoOpen) {
    $nav = Abrir-App
    Write-Host "[OK] Janela do Okada Pedidos iniciada!" -ForegroundColor Green
}
Write-Host ""
Write-Host "Aplicativo rodando 100% offline." -ForegroundColor Gray
Write-Host "Para fechar o programa, feche a janela do aplicativo ou esta janela." -ForegroundColor Gray

# 3. Loop de atendimento das requisicoes
while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
    } catch {
        break
    }
    
    $reqPath = $context.Request.Url.LocalPath.TrimStart('/')
    if ([string]::IsNullOrEmpty($reqPath)) { $reqPath = 'index.html' }
    
    if ($reqPath -eq 'sair') {
        $msg = [System.Text.Encoding]::UTF8.GetBytes("Servidor encerrado.")
        $context.Response.OutputStream.Write($msg, 0, $msg.Length)
        $context.Response.OutputStream.Close()
        break
    }

    if ($reqPath -eq 'api/checar_atualizacao' -and $context.Request.HttpMethod -eq 'GET') {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        $statusUpd = Verificar-Atualizacao-Nuvem
        $jsonResp = $statusUpd | ConvertTo-Json -Compress
        $respBytes = $utf8NoBom.GetBytes($jsonResp)
        $context.Response.ContentType = 'application/json; charset=utf-8'
        $context.Response.ContentLength64 = $respBytes.Length
        $context.Response.AddHeader('Cache-Control', 'no-cache, no-store')
        try { $context.Response.OutputStream.Write($respBytes, 0, $respBytes.Length) } catch { }
        try { $context.Response.OutputStream.Close() } catch { }
        continue
    }

    if ($reqPath -eq 'api/email_config' -and $context.Request.HttpMethod -eq 'GET') {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        $cfgEmail = Ler-EmailConfig
        $respObj = if ($cfgEmail) {
            @{
                configurado = $true
                email       = [string]$cfgEmail.email
                nome        = [string]$cfgEmail.nome
                smtpHost    = [string]$cfgEmail.smtpHost
                smtpPort    = if ($cfgEmail.smtpPort) { [int]$cfgEmail.smtpPort } else { 587 }
                smtpSsl     = if ($null -ne $cfgEmail.smtpSsl) { [bool]$cfgEmail.smtpSsl } else { $true }
                temSenha    = (-not [string]::IsNullOrEmpty($cfgEmail.senhaEnc))
            }
        } else {
            @{ configurado = $false }
        }
        $respBytes = $utf8NoBom.GetBytes(($respObj | ConvertTo-Json -Compress))
        $context.Response.ContentType = 'application/json; charset=utf-8'
        $context.Response.ContentLength64 = $respBytes.Length
        $context.Response.AddHeader('Cache-Control', 'no-cache, no-store')
        try { $context.Response.OutputStream.Write($respBytes, 0, $respBytes.Length) } catch { }
        try { $context.Response.OutputStream.Close() } catch { }
        continue
    }

    if ($reqPath -eq 'api/email_config' -and $context.Request.HttpMethod -eq 'POST') {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        try {
            $reader = New-Object System.IO.StreamReader($context.Request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $dados = $body | ConvertFrom-Json
            if ($dados.limpar) {
                $pCfg = Obter-Caminho-EmailConfig
                if (Test-Path $pCfg) { Remove-Item $pCfg -Force }
                $respBytes = $utf8NoBom.GetBytes((@{ ok = $true; configurado = $false } | ConvertTo-Json -Compress))
            } else {
                Salvar-EmailConfig $dados
                $respBytes = $utf8NoBom.GetBytes((@{ ok = $true; configurado = $true } | ConvertTo-Json -Compress))
            }
            $context.Response.ContentType = 'application/json; charset=utf-8'
            $context.Response.ContentLength64 = $respBytes.Length
            $context.Response.OutputStream.Write($respBytes, 0, $respBytes.Length)
        } catch {
            $respBytes = $utf8NoBom.GetBytes((@{ ok = $false; erro = $_.Exception.Message } | ConvertTo-Json -Compress))
            $context.Response.StatusCode = 400
            $context.Response.ContentType = 'application/json; charset=utf-8'
            $context.Response.ContentLength64 = $respBytes.Length
            try { $context.Response.OutputStream.Write($respBytes, 0, $respBytes.Length) } catch { }
        }
        try { $context.Response.OutputStream.Close() } catch { }
        continue
    }

    if ($reqPath -eq 'api/enviar_email' -and $context.Request.HttpMethod -eq 'POST') {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        try {
            $reader = New-Object System.IO.StreamReader($context.Request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $payload = $body | ConvertFrom-Json
            $resEmail = Enviar-Email-Smtp $payload
            $respBytes = $utf8NoBom.GetBytes(($resEmail | ConvertTo-Json -Compress))
            $context.Response.ContentType = 'application/json; charset=utf-8'
            $context.Response.ContentLength64 = $respBytes.Length
            $context.Response.AddHeader('Cache-Control', 'no-cache, no-store')
            $context.Response.OutputStream.Write($respBytes, 0, $respBytes.Length)
        } catch {
            $respBytes = $utf8NoBom.GetBytes((@{ ok = $false; erro = $_.Exception.Message } | ConvertTo-Json -Compress))
            $context.Response.StatusCode = 500
            $context.Response.ContentType = 'application/json; charset=utf-8'
            $context.Response.ContentLength64 = $respBytes.Length
            try { $context.Response.OutputStream.Write($respBytes, 0, $respBytes.Length) } catch { }
        }
        try { $context.Response.OutputStream.Close() } catch { }
        continue
    }

    if ($reqPath -eq 'api/salvar_padrao' -and $context.Request.HttpMethod -eq 'POST') {
        try {
            $reader = New-Object System.IO.StreamReader($context.Request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

            # 1. Salva tabelas_padrao.json e tabelas_padrao.js no projeto
            $destPath = Join-Path $baseDir 'tabelas_padrao.json'
            [System.IO.File]::WriteAllText($destPath, $body, $utf8NoBom)
            $jsPath = Join-Path $baseDir 'tabelas_padrao.js'
            [System.IO.File]::WriteAllText($jsPath, "window.TABELAS_PADRAO = $body;", $utf8NoBom)

            # 2. Incrementa a versao do Service Worker em sw.js e index.html
            $novaVer = 0
            $swPath = Join-Path $baseDir 'sw.js'
            if (Test-Path $swPath) {
                $swContent = [System.IO.File]::ReadAllText($swPath, [System.Text.Encoding]::UTF8)
                if ($swContent -match "okada-v(\d+)") {
                    $novaVer = [int]$matches[1] + 1
                    $swContent = $swContent -replace "okada-v\d+", "okada-v$novaVer"
                    [System.IO.File]::WriteAllText($swPath, $swContent, $utf8NoBom)
                }
            }
            $idxPath = Join-Path $baseDir 'index.html'
            if (($novaVer -gt 0) -and (Test-Path $idxPath)) {
                $idxContent = [System.IO.File]::ReadAllText($idxPath, [System.Text.Encoding]::UTF8)
                $idxContent = $idxContent -replace "Versão okada-v\d+", "Versão okada-v$novaVer"
                [System.IO.File]::WriteAllText($idxPath, $idxContent, $utf8NoBom)
            }

            # 3. Publica no GitHub (se configurado ou abre assistente na primeira vez)
            $resGit = Publicar-No-GitHub -PermitirInterativo

            # 4. Atualiza a pasta 'Okada Pedidos - Versao Beta' e gera o .zip
            Sincronizar-Pasta-Beta

            $respObj = @{
                sucesso   = $true
                versao    = "okada-v$novaVer"
                nuvem     = [bool]$resGit.ok
                erroNuvem = if ($resGit.ok) { $null } else { $resGit.erro }
            } | ConvertTo-Json -Compress

            $respBytes = $utf8NoBom.GetBytes($respObj)
            $context.Response.ContentType = 'application/json; charset=utf-8'
            $context.Response.ContentLength64 = $respBytes.Length
            $context.Response.AddHeader('Cache-Control', 'no-cache')
            $context.Response.OutputStream.Write($respBytes, 0, $respBytes.Length)
        } catch {
            $context.Response.StatusCode = 500
        }
        try { $context.Response.OutputStream.Close() } catch { }
        continue
    }
    
    $filePath = Join-Path $baseDir ($reqPath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))

    if (Test-Path $filePath -PathType Leaf) {
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
        $mime = switch ($ext) {
            '.html' { 'text/html; charset=utf-8' }
            '.js'   { 'application/javascript; charset=utf-8' }
            '.css'  { 'text/css; charset=utf-8' }
            '.json' { 'application/json; charset=utf-8' }
            '.webp' { 'image/webp' }
            '.png'  { 'image/png' }
            '.jpg'  { 'image/jpeg' }
            '.jpeg' { 'image/jpeg' }
            '.woff2'{ 'font/woff2' }
            '.enc'  { 'application/octet-stream' }
            default { 'application/octet-stream' }
        }
        $context.Response.ContentType = $mime
        $context.Response.ContentLength64 = $bytes.Length
        $context.Response.AddHeader('Cache-Control', 'no-cache, no-store, must-revalidate')
        $context.Response.AddHeader('Pragma', 'no-cache')
        $context.Response.AddHeader('Expires', '0')
        try {
            $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } catch { }
    } else {
        $context.Response.StatusCode = 404
    }
    
    try {
        $context.Response.OutputStream.Close()
    } catch { }
}

try {
    $listener.Stop()
} catch { }
