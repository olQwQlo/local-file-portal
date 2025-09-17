<# 
  Local File Portal 用 filelist.txt 生成スクリプト（完全版）
  - GUIでルートフォルダを選択
  - 絶対パス or 相対パスを選択（相対パスは `/` 正規化）
  - 既存の推奨除外パターンを適用（上書き可能）
  - UTF-8（BOMなし）で filelist.txt を出力
  - 長いパス対策・シンボリックリンク回避・件数制限などの安全機能
#>

param(
  [switch]$Relative,                         # 相対パスで出力（index.html からの相対、`/` 正規化）
  [string]$OutputPath,                       # 明示保存先（未指定ならダイアログ→未選択時は既定）
  [switch]$IncludeHidden,                    # 隠しファイルも含める
  [switch]$Quiet,                            # 完了ダイアログを出さない
  [switch]$EnableLongPath,                   # 長いパス対策（絶対パス時に \\?\ 接頭辞）
  [string]$ExcludeFolderRegex = '\\node_modules\\|\.git\\|\\dist\\|\\build\\|\\out\\|\\target\\|\.venv\\|\.m2\\|\.gradle',
  [string]$ExcludeFileRegex   = '^(~\$.*|.*\.(tmp|bak|obj|class|pyc))$',
  [int]$MaxFiles = 0,                        # 出力件数上限（0=無制限）
  [switch]$NoSort                            # ソートしない
)

# --- スクリプトパスの安全な取得 ---
$ScriptPath = if ($PSScriptRoot) { 
  $PSScriptRoot 
} elseif ($MyInvocation.MyCommand.Path) { 
  Split-Path -Parent $MyInvocation.MyCommand.Path 
} else { 
  $PWD.Path 
}

# --- 必要なアセンブリの読み込み（STA再実行を含む） ---
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
  # STAで自分自身を再起動
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName  = (Get-Process -Id $PID).Path
  
  # スクリプトパスを正しく渡す
  $scriptFile = if ($MyInvocation.MyCommand.Path) {
    $MyInvocation.MyCommand.Path
  } else {
    Join-Path $PWD.Path $MyInvocation.MyCommand.Name
  }
  
  $psi.Arguments = @(
    '-NoProfile','-ExecutionPolicy','Bypass','-File',
    ('"{0}"' -f $scriptFile)
  ) + ($PSBoundParameters.GetEnumerator() | ForEach-Object {
        if ($_.Value -is [switch] -and $_.Value) { "-$($_.Key)" }
        elseif ($_.Value -is [switch]) { $null }
        else { "-$($_.Key)"; ('"{0}"' -f $_.Value) }
      })
  [Diagnostics.Process]::Start($psi) | Out-Null
  exit
}

# Windows Forms の読み込み（PS 7 フォールバック対応）
try {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  Add-Type -AssemblyName System.Drawing | Out-Null
} catch {
  Write-Warning 'GUI を使用するには Windows PowerShell 5.1 が必要です。PowerShell 7 で実行中なら Windows PowerShell 5.1 で再実行してください。'
  return
}

# --- 長いパス対策関数 ---
function Add-LongPathPrefix([string]$Path) {
  if ($Path -and $Path -match '^[a-zA-Z]:\\' -and $EnableLongPath) {
    return '\\\\?\\' + $Path
  }
  return $Path
}

# --- ルートフォルダ選択 ---
$dlg = New-Object System.Windows.Forms.FolderBrowserDialog
$dlg.Description = 'ファイルリストを作成するルートフォルダを選択してください'
$dlg.ShowNewFolderButton = $false
$root = if ($dlg.ShowDialog() -eq 'OK') { $dlg.SelectedPath } else { return }

# --- 既定の出力先（Downloads が無い環境も考慮） ---
function Get-DefaultOutputPath {
  param([string]$ScriptDirectory)
  
  # 一般的な既定: %USERPROFILE%\Downloads\filelist.txt
  $userProfile = $env:USERPROFILE
  if (-not $userProfile) { $userProfile = $env:HOME }
  if (-not $userProfile) { $userProfile = [Environment]::GetFolderPath('UserProfile') }
  if (-not $userProfile) { $userProfile = $PWD.Path }
  
  # Downloads フォルダのパス生成
  $dl = $null
  if ($userProfile) {
    $dl = Join-Path $userProfile 'Downloads'
    if (-not (Test-Path -LiteralPath $dl)) { $dl = $userProfile }
  } else {
    $dl = $PWD.Path
  }

  # index.html と同階層にあるなら、そこを優先
  if ($ScriptDirectory) {
    $indexPath = Join-Path $ScriptDirectory 'index.html'
    if (Test-Path -LiteralPath $indexPath) {
      return (Join-Path $ScriptDirectory 'filelist.txt')
    }
  }
  
  if ($dl) {
    return (Join-Path $dl 'filelist.txt')
  } else {
    return (Join-Path $PWD.Path 'filelist.txt')
  }
}

# --- 出力先決定（ダイアログ or 既定） ---
if (-not $OutputPath) {
  $sfd = New-Object System.Windows.Forms.SaveFileDialog
  $sfd.Title = 'filelist.txt の保存先を選択'
  $sfd.Filter = 'Text Files|*.txt|All Files|*.*'
  $sfd.FileName = 'filelist.txt'
  $defaultOutput = Get-DefaultOutputPath -ScriptDirectory $ScriptPath
  
  # InitialDirectoryの安全な設定
  if ($defaultOutput) {
    $parentDir = Split-Path $defaultOutput -Parent
    if ($parentDir -and (Test-Path -LiteralPath $parentDir)) {
      $sfd.InitialDirectory = $parentDir
    } else {
      $sfd.InitialDirectory = $PWD.Path
    }
  } else {
    $sfd.InitialDirectory = $PWD.Path
  }
  
  if ($sfd.ShowDialog() -eq 'OK') { $OutputPath = $sfd.FileName }
  if (-not $OutputPath) { $OutputPath = $defaultOutput }
}

# --- 進捗フォーム（キャンセル対応） ---
$script:cancel = $false
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Local File Portal - filelist 生成中'
$form.Width = 520; $form.Height = 150
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$label = New-Object System.Windows.Forms.Label
$label.Text = '検索中...（しばらくお待ちください）'
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(12,12)

$prog = New-Object System.Windows.Forms.ProgressBar
$prog.Style = 'Marquee'
$prog.Width = 480; $prog.Height = 20
$prog.Location = New-Object System.Drawing.Point(12,40)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = 'キャンセル'
$btnCancel.Width = 80; $btnCancel.Height = 25
$btnCancel.Location = New-Object System.Drawing.Point(407,70)
$btnCancel.Add_Click({ $script:cancel = $true; $form.Close() })

$form.Controls.AddRange(@($label, $prog, $btnCancel))
$form.Show() | Out-Null
$form.Refresh()

# --- ファイル列挙（安全機能付き） ---
$folderEx = $ExcludeFolderRegex
$fileEx   = $ExcludeFileRegex

$gciParams = @{
  LiteralPath = $root
  Recurse     = $true
  File        = $true
  ErrorAction = 'SilentlyContinue'
}
if ($IncludeHidden) { $gciParams['Force'] = $true }

try {
  if ($script:cancel) { return }
  
  # 変数の初期化
  $items = @()
  $lines = @()
  
  $items = Get-ChildItem @gciParams |
    Where-Object {
      # 再解析ポイント（シンボリックリンク等）を既定除外
      ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
      $_.FullName -notmatch $folderEx -and
      $_.Name     -notmatch $fileEx
    }

  if ($script:cancel) { $form.Close(); return }

  # 配列として確実に取得
  if ($items -isnot [array]) { $items = @($items) }

  # ソート処理
  if (-not $NoSort) {
    $label.Text = 'ソート中...'
    $form.Refresh()
    $items = $items | Sort-Object FullName
  }

  if ($script:cancel) { $form.Close(); return }

  # 件数制限チェック
  if ($MaxFiles -gt 0 -and $items.Count -gt $MaxFiles) {
    $form.Close()
    if (-not $Quiet) {
      [System.Windows.Forms.MessageBox]::Show(
        "対象が $($items.Count) 件あります。MaxFiles=$MaxFiles を超えています。`r`n" +
        "除外ルールを見直すか MaxFiles を引き上げて再実行してください。",
        '件数オーバー','OK','Warning'
      ) | Out-Null
    }
    return
  }

  $label.Text = 'パス変換中...'
  $form.Refresh()

  # --- パス変換（絶対 or 相対） ---
  $pathList = @()
  if ($Relative -and $ScriptPath) {
    $indexPath = Join-Path $ScriptPath 'index.html'
    if (Test-Path -LiteralPath $indexPath) {
      Push-Location $ScriptPath
      try {
        foreach ($item in $items) {
          if ($cancel) { break }
          # index.html からの相対パスを生成
          $relativePath = Resolve-Path -LiteralPath $item.FullName -Relative
          # PowerShell の Resolve-Path は ".\" で始まるので、それを削除
          if ($relativePath.StartsWith('.\')) {
            $relativePath = $relativePath.Substring(2)
          }
          # ブラウザ用に \ を / に正規化
          $pathList += ($relativePath -replace '\\','/')
        }
      } finally { Pop-Location }
    } else {
      # index.htmlが見つからない場合は絶対パス
      foreach ($item in $items) {
        if ($script:cancel) { break }
        $pathList += (Add-LongPathPrefix $item.FullName)
      }
    }
  } else {
    # 絶対パス（UNC/ローカル両対応、長いパス対策付き）
    foreach ($item in $items) {
      if ($script:cancel) { break }
      $pathList += (Add-LongPathPrefix $item.FullName)
    }
  }

  if ($script:cancel) { $form.Close(); return }
  
  $lines = $pathList

  $label.Text = '保存中...'
  $form.Refresh()

  # --- 保存（UTF-8 BOMなし） ---
  if (-not $OutputPath) {
    throw "出力パスが決定できませんでした。"
  }
  
  $outputDir = Split-Path -Parent $OutputPath
  if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
    $null = New-Item -ItemType Directory -Force -Path $outputDir
  }
  
  # UTF-8（BOMなし）で保存を試行
  if ($lines -and $lines.Count -gt 0) {
    try {
      # PS 7 では BOMなしを明示可能
      if ($PSVersionTable.PSVersion.Major -ge 7) {
        $lines | Out-File -LiteralPath $OutputPath -Encoding utf8NoBOM
      } else {
        # PS 5.1 では Set-Content を使用（BOMなし）
        $lines | Set-Content -LiteralPath $OutputPath -Encoding UTF8
      }
    } catch {
      # フォールバック: Out-File を使用
      $lines | Out-File -LiteralPath $OutputPath -Encoding utf8
    }
  } else {
    # 空のファイルを作成
    '' | Out-File -LiteralPath $OutputPath -Encoding utf8
  }

  $form.Close()
  
  if (-not $Quiet) {
    $pathType = if ($Relative) { "相対パス（/ 正規化済み）" } else { "絶対パス" }
    $longPathNote = if ($EnableLongPath -and -not $Relative) { "（長いパス対策適用）" } else { "" }
    $fileCount = if ($lines) { $lines.Count } else { 0 }
    
    $message = "filelist.txt を出力しました:`r`n{0}`r`n`r`n対象: {1}`r`n件数: {2}`r`n形式: {3}{4}" -f $OutputPath, $root, $fileCount, $pathType, $longPathNote
    
    [System.Windows.Forms.MessageBox]::Show($message, '完了', 'OK', 'Information') | Out-Null
  }

} catch {
  $form.Close()
  [System.Windows.Forms.MessageBox]::Show(
    "エラーが発生しました:`r`n$($_.Exception.Message)"
  , 'エラー', 'OK', 'Error') | Out-Null
  throw
} finally {
  if ($form -and -not $form.IsDisposed) {
    $form.Close()
  }
}