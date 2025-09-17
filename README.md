# Local File Portal

**単一HTMLファイルで完結するローカルファイルポータル**  
UNC・絶対・相対パス対応、ツリービュー・検索・選択機能付き

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Version: 1.0](https://img.shields.io/badge/Version-1.0-green.svg)
![No Dependencies](https://img.shields.io/badge/Dependencies-None-orange.svg)

## 🚀 特徴

- ✅ **単一HTMLファイル** - サーバー不要、ポータブル
- ✅ **多様なパス形式対応**
  - UNC パス: `\\server\share` → `file:////server/share/...`
  - Windows絶対パス: `C:\path` → `file:///C:/path/...`
  - 相対パス: プロジェクト配布に最適
- ✅ **直感的なツリービュー** - フォルダ展開・折りたたみ
- ✅ **高速検索** - ファイル名の部分一致検索
- ✅ **選択機能** - チェックボックスでファイル選択・管理
- ✅ **状態保持** - ローカルストレージで設定自動保存
- ✅ **PowerShell連携** - ファイル一覧生成スクリプト内蔵

## 📦 クイックスタート

### 1. セットアップ
```bash
# プロジェクトルートに index.html を配置
your-project/
├── index.html          # ← このファイル
├── src/
├── docs/
└── ...
```

### 2. ファイルリスト生成
プロジェクトルートでPowerShellを開いて実行：

```powershell
# 基本版（すべてのファイルを対象）
Get-ChildItem -Recurse -File `
| Select-Object -ExpandProperty FullName `
| Out-File "$env:USERPROFILE\Downloads\filelist.txt" -Encoding utf8

# 推奨版（不要なファイル・フォルダを除外）
Get-ChildItem -Recurse -File `
| Where-Object {
    $_.FullName -notmatch '\\node_modules\\|\\.git\\|dist\\|build\\|out\\|target\\|\\.venv\\|\\.m2\\|\\.gradle' -and
    $_.Name -notmatch '^(~\$.*|.*\.(tmp|bak|obj|class|pyc))$'
} `
| Select-Object -ExpandProperty FullName `
| Out-File "$env:USERPROFILE\Downloads\filelist.txt" -Encoding utf8
```

### 3. 使用開始
1. ブラウザで `index.html` を開く
2. **「filelist.txt を選択」** から生成した `.txt` ファイルを選択
3. ツリー表示でファイルをブラウズ

## 🎯 主要機能

### ファイルナビゲーション
- **ツリー表示**: フォルダクリックで展開・折りたたみ
- **リンク**: ファイルクリックでローカルファイルを開く
- **共通ルート表示**: 重複するパス部分を自動省略

### 検索・フィルタリング
- **リアルタイム検索**: ファイル名での部分一致
- **自動展開**: 検索時に関連フォルダを自動展開
- **件数表示**: 表示中/総ファイル数を表示

### ツリー操作
- **すべて展開**: 全フォルダを一括展開
- **すべて折りたたみ**: 全フォルダを一括折りたたみ  
- **初期表示に戻す**: 検索クリア・適切な階層まで展開

### 選択・管理機能
- **チェックボックス**: 重要ファイルを選択
- **選択の保存**: ローカルストレージに自動保存
- **書き出し**: 選択ファイル一覧をテキストファイルで出力
- **読み込み**: 外部ファイルから選択状態を復元
- **全解除**: 選択状態を一括クリア

### データ管理
- **自動保存**: ファイルリストを自動的にローカルストレージに保存
- **履歴機能**: 過去に読み込んだリストを再利用
- **メタ情報**: 保存日時・ファイル数を表示

## 🔧 高度な使用法

### 相対パス版（ポータブル配布用）
```powershell
# プロジェクト配布時に便利
Get-ChildItem -Recurse -File `
| Resolve-Path -Relative `
| Out-File "filelist.txt" -Encoding utf8
```

### UNCパス版（ネットワーク共有用）
```powershell
# ネットワークドライブで作業時
Get-ChildItem -Recurse -File \\server\share\project `
| Select-Object -ExpandProperty FullName `
| Out-File "filelist.txt" -Encoding utf8
```

### カスタムフィルター
PowerShellでファイル種別を限定：
```powershell
# 特定の拡張子のみ
Get-ChildItem -Recurse -File -Include *.js,*.ts,*.html,*.css `
| Select-Object -ExpandProperty FullName `
| Out-File "filelist.txt" -Encoding utf8

# 特定フォルダのみ対象
Get-ChildItem -Recurse -File -Path src,docs `
| Select-Object -ExpandProperty FullName `
| Out-File "filelist.txt" -Encoding utf8
```

## 💡 使用例・ユースケース

### 開発プロジェクトの管理
```
project-docs/
├── index.html          # ポータル
├── filelist.txt       # ファイル一覧
└── README.md          # この文書
```
チーム内でプロジェクト構造を共有、重要ファイルをマーク

### ドキュメント配布
レポート・資料集をHTML形式で配布、受け手が簡単にナビゲート

### アーカイブ管理  
過去プロジェクトのファイル構造を保持、必要時に素早くアクセス

## ⚠️ 注意事項・制限事項

### ブラウザ制限
- **file://プロトコル**: セキュリティ制限によりブラウザで開けない場合あり
- **推奨環境**: Chrome、Firefox、Edge（最新版）
- **企業環境**: IT部門のセキュリティポリシーに要確認

### パス制限
- **日本語・特殊文字**: 環境によっては正常に動作しない場合あり
- **長いパス**: Windows 260文字制限の影響を受ける可能性

### パフォーマンス
- **大容量リスト**: 10,000ファイル以上では動作が重くなる可能性
- **メモリ使用量**: ファイル数に比例してメモリ消費が増加

## 🛠️ トラブルシューティング

### ファイルが開けない
1. **ブラウザ設定**: file://プロトコルを許可
2. **パス確認**: ファイル存在・アクセス権限を確認
3. **エンコーディング**: filelist.txtがUTF-8で保存されているか確認

### 日本語が文字化け
PowerShellでの文字エンコーディング指定を確認：
```powershell
# UTF-8明示指定
Out-File "filelist.txt" -Encoding utf8
```

### パフォーマンス改善
```powershell
# 不要ファイルを事前除外
Get-ChildItem -Recurse -File `
| Where-Object { 
    $_.Length -lt 100MB -and
    $_.Name -notmatch '\.(log|tmp)$'
} `
| Select-Object -ExpandProperty FullName `
| Out-File "filelist.txt" -Encoding utf8
```

## 🏗️ カスタマイズ

### CSS変数でテーマ変更
```css
:root {
    --primary-bg: #1a1a1a;      /* ダークテーマ */
    --primary-text: #ffffff;
    --muted-color: #888888;
    --border-color: #444444;
}
```

### 除外パターン変更
JavaScriptの `buildTreeFromLines` メソッド内でフィルター条件をカスタマイズ可能

## 📄 ライセンス

MIT License - 自由に使用・改変・配布可能

## 🤝 貢献

バグ報告・機能要望・プルリクエストを歓迎します。

---

**Local File Portal** - シンプル・高機能・ポータブルなファイル管理ツール