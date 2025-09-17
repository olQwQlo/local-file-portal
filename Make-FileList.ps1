<# 
  Local File Portal 用 filelist.txt 生成スクリプト
  - GUIでルートフォルダを選択
  - 絶対パス or 相対パスを選択
  - 既存の推奨除外パターンを適用
  - UTF-8 で filelist.txt を出力（デフォルトは ダウンロード or index.html と同階層）
#>

param(
  [switch]$Relative,                         # 相対パスで出力（index.html からの相対）
  [string]$OutputPath,                       # 明示保存先（未指定ならダイアログ→未選択時は既定）
  [switch]$IncludeHidden,                    # 隠しファイルも含める
  [switch]$Quiet                             # 完了ダイアログを出さない
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

Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null

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

# --- 進捗フォーム（簡易） ---
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Local File Portal - filelist 生成中'
$form.Width = 520; $form.Height = 120
$form.StartPosition = 'CenterScreen'
$label = New-Object System.Windows.Forms.Label
$label.Text = '検索中...（閉じないでください）'
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(12,12)
$prog = New-Object System.Windows.Forms.ProgressBar
$prog.Style = 'Marquee'
$prog.Width = 480; $prog.Height = 20
$prog.Location = New-Object System.Drawing.Point(12,40)
$form.Controls.Add($label)
$form.Controls.Add($prog)
$form.Show() | Out-Null
$form.Refresh()

# --- 既存の推奨除外ルールを適用 ---
#   ・フォルダ: \node_modules\, \.git\, dist, build, out, target, \.venv\, \.m2\, \.gradle
#   ・名前: ~$ で始まる一時/Officeロック、.tmp/.bak/.obj/.class/.pyc 等

$folderEx = '\\node_modules\\|\.git\\|\\dist\\|\\build\\|\\out\\|\\target\\|\.venv\\|\.m2\\|\.gradle'
$fileEx   = '^(~\$.*|.*\.(tmp|bak|obj|class|pyc))$'

# --- 列挙（隠しファイルの扱い切替） ---
$gciParams = @{
  LiteralPath = $root
  Recurse     = $true
  File        = $true
  ErrorAction = 'SilentlyContinue'
}
if ($IncludeHidden) { $gciParams['Force'] = $true }

try {
  $items =
    Get-ChildItem @gciParams |
    Where-Object {
      $_.FullName -notmatch $folderEx -and
      $_.Name     -notmatch $fileEx
    }

  # --- パス変換（絶対 or 相対） ---
  $lines = if ($Relative -and $ScriptPath) {
    $indexPath = Join-Path $ScriptPath 'index.html'
    if (Test-Path -LiteralPath $indexPath) {
      Push-Location $ScriptPath
      try {
        $items | ForEach-Object {
          # index.html からの相対パスを生成
          $relativePath = Resolve-Path -LiteralPath $_.FullName -Relative
          # PowerShell の Resolve-Path は ".\" で始まるので、それを削除
          if ($relativePath.StartsWith('.\')) {
            $relativePath.Substring(2)
          } else {
            $relativePath
          }
        }
      } finally { Pop-Location }
    } else {
      # index.htmlが見つからない場合は絶対パス
      $items | Select-Object -ExpandProperty FullName
    }
  } else {
    # 絶対パス（UNC/ローカル両対応）
    $items | Select-Object -ExpandProperty FullName
  }

  # --- 保存（UTF-8） ---
  if (-not $OutputPath) {
    throw "出力パスが決定できませんでした。"
  }
  
  $outputDir = Split-Path -Parent $OutputPath
  if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
    $null = New-Item -ItemType Directory -Force -Path $outputDir
  }
  
  $encoding = 'utf8'
  $lines | Out-File -LiteralPath $OutputPath -Encoding $encoding

  $form.Close()
  if (-not $Quiet) {
    [System.Windows.Forms.MessageBox]::Show(
      "filelist.txt を出力しました:`r`n$OutputPath`r`n`r`n" +
      "対象: $root`r`n" +
      "件数: {0}" -f ($lines.Count)
    , '完了', 'OK', 'Information') | Out-Null
  }
} catch {
  $form.Close()
  [System.Windows.Forms.MessageBox]::Show(
    "エラーが発生しました:`r`n$($_.Exception.Message)"
  , 'エラー', 'OK', 'Error') | Out-Null
  throw
}