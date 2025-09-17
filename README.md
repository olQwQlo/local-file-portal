# Local File Portal

A **single-file HTML** file-tree portal with search. Supports **UNC paths**, **Windows absolute paths**, and **relative paths**.  
No server, no build — just open `index.html`.

## Features
- ✅ Single HTML file (portable)
- ✅ UNC `\\server\share` → `file:////server/share/...`
- ✅ `C:\...` → `file:///C:/...`
- ✅ Relative paths for easy folder hand-off
- ✅ Expand/collapse all, partial search filter
- ✅ PowerShell snippet to generate `filelist.txt`

## Quick Start
1. Put `index.html` at repository root (or any folder you want to index).
2. Generate a path list (`filelist.txt`) **with relative paths**:
   ```powershell
   Get-ChildItem -Recurse -File `
   | Resolve-Path -Relative `
   | Out-File "$env:USERPROFILE\Downloads\filelist.txt" -Encoding utf8

   # Exclude noisy paths (optional)
   # Get-ChildItem -Recurse -File `
   # | Where-Object { $_.FullName -notmatch '\\node_modules\\|\.git\\|\\~\$' } `
   # | Resolve-Path -Relative `
   # | Out-File "$env:USERPROFILE\Downloads\filelist.txt" -Encoding utf8
   ```
3. Open `index.html` in your browser, select the generated `filelist.txt`, and browse.

## Tips
- Relative paths make the folder **fully portable**.
- `file://` links may be restricted by some browsers/IT policies.
- Use UNC paths for shared folders to avoid drive-letter differences.

## License
MIT
