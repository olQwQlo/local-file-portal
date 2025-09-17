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
  [switch]$NoSort,                           # ソートしない
  [int]$Depth = -1                           # 追加: 深さ制限（-1=無制限、PS7で有効／5.1は無視）
)

# --- スクリプトパスの安全な取得 ---
$ScriptPath = if ($PSScriptRoot) { 
  $PSScriptRoot 
} elseif ($MyInvocation.MyCommand.Path) { 
  Split-Path -Parent $MyInvocation.MyCommand.Path 
} else { 
  $PWD.Path 
}

# --- 追加: PS7 実行時は Windows PowerShell 5.1 へ自動フォールバック（GUI目的） ---
#     ※ 5.1 が見つからない場合は継続実行
try {
  if ($PSVersionTable.PSEdition -eq 'Core') {
    $pwsh51 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path -LiteralPath $pwsh51) {
      $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $MyInvocation.MyCommand.Path)
      foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
          if ($kv.Value) { $argList += "-$($kv.Key)" }
        } else {
          $argList += "-$($kv.Key)"; $argList += [string]$kv.Value
        }
      }
      Start-Process -FilePath $pwsh51 -ArgumentList $argList -Wait | Out-Null
      exit
    }
  }
} catch { }

# --- 必要なアセンブリの読み込み（STA再実行を含む） ---
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
  # STAで自分自身を再起動（※ 引数は素の配列を渡す：手動の二重引用符は付けない）
  $exe = (Get-Process -Id $PID).Path
  $scriptFile = if ($MyInvocation.MyCommand.Path) {
    $MyInvocation.MyCommand.Path
  } else {
    Join-Path $PWD.Path $MyInvocation.MyCommand.Name
  }
  $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $scriptFile)
  foreach ($kv in $PSBoundParameters.GetEnumerator()) {
    if ($kv.Value -is [switch]) {
      if ($kv.Value) { $argList += "-$($kv.Key)" }
    } else {
      $argList += "-$($kv.Key)"; $argList += [string]$kv.Value
    }
  }
  Start-Process -FilePath $exe -ArgumentList $argList -Wait | Out-Null
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

# --- 長いパス対策関数（改善: UNC 対応を強化） ---
function Add-LongPathPrefix([string]$Path) {
  if (-not $Path) { return $Path }
  if ($EnableLongPath) {
    if ($Path -match '^[a-zA-Z]:\\') { return '\\?\'+$Path }
    if ($Path -match '^\\\\[^\\]')   { return '\\?\UNC\' + $Path.TrimStart('\') }
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
$form.Width = 520; $form.Height = 170
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

# --- ファイル列挙パラメータ（Depth は PS7 で有効／5.1 は無視想定） ---
$folderEx = $ExcludeFolderRegex
$fileEx   = $ExcludeFileRegex

$gciParams = @{
  LiteralPath = $root
  Recurse     = $true
  File        = $true
  ErrorAction = 'SilentlyContinue'
}
if ($IncludeHidden) { $gciParams['Force'] = $true }

# 追加: Depth サポート（PS 7 以降）
try {
  if ($Depth -ge 0 -and $PSVersionTable.PSVersion.Major -ge 7) {
    $gciParams['Depth'] = $Depth
  }
} catch { }

# --- 相対パスの前提チェック ---
$hasIndexBesideScript = $false
if ($Relative -and $ScriptPath) {
  $indexPath = Join-Path $ScriptPath 'index.html'
  if (Test-Path -LiteralPath $indexPath) { $hasIndexBesideScript = $true }
}

# --- 保存（UTF-8 BOMなし）をストリーミング化（メモリ一定・高速） ---
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$sw = $null

try {
  if ($script:cancel) { return }

  # 出力ディレクトリ作成
  if (-not $OutputPath) { throw "出力パスが決定できませんでした。" }
  $outputDir = Split-Path -Parent $OutputPath
  if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
    $null = New-Item -ItemType Directory -Force -Path $outputDir
  }

  # ライタを開く
  $sw = [System.IO.StreamWriter]::new($OutputPath, $false, $utf8NoBom)

  # 追加: ヘッダー行（再現性のためのメタ情報）
  $sw.WriteLine("# Local File Portal filelist")
  $sw.WriteLine("# generated=$(Get-Date -Format o)")
  $sw.WriteLine("# root=$root")
  $sw.WriteLine("# mode=" + ($(if($Relative){"relative"}else{"absolute"})))
  if ($IncludeHidden) { $sw.WriteLine("# includeHidden=true") }
  if ($EnableLongPath) { $sw.WriteLine("# longPathPrefix=true") }
  if ($Depth -ge 0) { $sw.WriteLine("# depth=$Depth") }
  if ($ExcludeFolderRegex) { $sw.WriteLine("# excludeFolderRegex=$ExcludeFolderRegex") }
  if ($ExcludeFileRegex)   { $sw.WriteLine("# excludeFileRegex=$ExcludeFileRegex") }

  $label.Text = '列挙中...'
  $form.Refresh()

  $writeCount = 0

  # --- 2パス: ソートあり/なしで分岐 ---
  if ($NoSort) {
    # ソートなし: 列挙をフィルタして即書き出し（最小メモリ）
    $enum = Get-ChildItem @gciParams | Where-Object {
      ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
      $_.FullName -notmatch $folderEx -and
      $_.Name     -notmatch $fileEx
    }

    foreach ($item in $enum) {
      if ($script:cancel) { break }

      if ($Relative -and $hasIndexBesideScript) {
        Push-Location $ScriptPath
        try {
          $rel = Resolve-Path -LiteralPath $item.FullName -Relative
          if ($rel.StartsWith('.\')) { $rel = $rel.Substring(2) }
          $line = ($rel -replace '\\','/')
        } finally { Pop-Location }
      } else {
        $line = Add-LongPathPrefix $item.FullName
      }

      $sw.WriteLine($line)
      $writeCount++

      if ($MaxFiles -gt 0 -and $writeCount -ge $MaxFiles) { break }
    }

  } else {
    # ソートあり: 一度配列化→ソート→書き出し
    $label.Text = '列挙中...(ソートあり)'
    $form.Refresh()

    $items = Get-ChildItem @gciParams | Where-Object {
      ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
      $_.FullName -notmatch $folderEx -and
      $_.Name     -notmatch $fileEx
    }

    if ($script:cancel) { $form.Close(); return }

    if ($items -isnot [array]) { $items = @($items) }

    $label.Text = 'ソート中...'
    $form.Refresh()
    $items = $items | Sort-Object FullName

    $label.Text = '保存中...'
    $form.Refresh()

    foreach ($item in $items) {
      if ($script:cancel) { break }

      if ($Relative -and $hasIndexBesideScript) {
        Push-Location $ScriptPath
        try {
          $rel = Resolve-Path -LiteralPath $item.FullName -Relative
          if ($rel.StartsWith('.\')) { $rel = $rel.Substring(2) }
          $line = ($rel -replace '\\','/')
        } finally { Pop-Location }
      } else {
        $line = Add-LongPathPrefix $item.FullName
      }

      $sw.WriteLine($line)
      $writeCount++

      if ($MaxFiles -gt 0 -and $writeCount -ge $MaxFiles) { break }
    }
  }

  $form.Close()

  if (-not $Quiet) {
    $pathType = if ($Relative) { "相対パス（/ 正規化済み）" } else { "絶対パス" }
    $longPathNote = if ($EnableLongPath -and -not $Relative) { "（長いパス対策適用）" } else { "" }
    $message = "filelist.txt を出力しました:`r`n{0}`r`n`r`n対象: {1}`r`n件数: {2}`r`n形式: {3}{4}" -f $OutputPath, $root, $writeCount, $pathType, $longPathNote
    [System.Windows.Forms.MessageBox]::Show($message, '完了', 'OK', 'Information') | Out-Null
  }

} catch {
  try { if ($form -and -not $form.IsDisposed) { $form.Close() } } catch {}
  [System.Windows.Forms.MessageBox]::Show(
    "エラーが発生しました:`r`n$($_.Exception.Message)"
  , 'エラー', 'OK', 'Error') | Out-Null
  throw
} finally {
  if ($sw) { $sw.Dispose() }
  try { if ($form -and -not $form.IsDisposed) { $form.Close() } } catch {}
}
