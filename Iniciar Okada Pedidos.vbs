Set fso = CreateObject("Scripting.FileSystemObject")
currentDir = fso.GetParentFolderName(WScript.ScriptFullName)
Set sh = CreateObject("WScript.Shell")

' Garante que atalhos duplicados/antigos sejam removidos da Area de Trabalho
On Error Resume Next
deskPath = sh.SpecialFolders("Desktop")
shortcutFile = deskPath & "\Okada Pedidos.lnk"

If deskPath <> "" And fso.FolderExists(deskPath) Then
    Set fFolder = fso.GetFolder(deskPath)
    For Each f In fFolder.Files
        fName = LCase(f.Name)
        If (InStr(fName, "okada") > 0) And (fName <> "okada pedidos.lnk") And (Right(fName, 4) = ".lnk" Or Right(fName, 4) = ".url") Then
            f.Delete True
        End If
    Next
End If

' Cria ou atualiza automaticamente o atalho oficial na Area de Trabalho com o icone
Set link = sh.CreateShortcut(shortcutFile)
link.TargetPath = "wscript.exe"
link.Arguments = """" & currentDir & "\Iniciar Okada Pedidos.vbs"""
link.WorkingDirectory = currentDir
link.IconLocation = currentDir & "\okada.ico,0"
link.Description = "Okada Pedidos"
link.Save
Set link = Nothing
On Error GoTo 0

' Inicia o servidor local e abre o app
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & currentDir & "\servidor.ps1""", 0, False
