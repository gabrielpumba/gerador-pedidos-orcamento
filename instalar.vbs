' Caracteres acentuados universais (evita problemas de codificacao no Windows)
Dim a_agudo, a_til, i_agudo, o_til, c_cedilha, A_agudo_maiusc
a_agudo        = ChrW(225) ' a com agudo
a_til          = ChrW(227) ' a com til
i_agudo        = ChrW(237) ' i com agudo
o_til          = ChrW(245) ' o com til
c_cedilha      = ChrW(231) ' c cedilha
A_agudo_maiusc = ChrW(193) ' A maiusculo com agudo

Set fso = CreateObject("Scripting.FileSystemObject")
currentDir = fso.GetParentFolderName(WScript.ScriptFullName)
Set sh = CreateObject("WScript.Shell")

Sub FecharInstanciasAnteriores()
    On Error Resume Next
    Dim http, p
    Set http = CreateObject("MSXML2.ServerXMLHTTP")
    For p = 8085 To 8090
        http.open "GET", "http://127.0.0.1:" & p & "/sair", False
        http.send
    Next
    Set http = Nothing
    On Error GoTo 0
End Sub

Sub LimparAtalhosAntigos()
    On Error Resume Next
    Dim pastas, p, fFolder, f, fName
    pastas = Array(sh.SpecialFolders("Desktop"), sh.SpecialFolders("AllUsersDesktop"), sh.SpecialFolders("Programs"))
    For Each p In pastas
        If p <> "" And fso.FolderExists(p) Then
            Set fFolder = fso.GetFolder(p)
            For Each f In fFolder.Files
                fName = LCase(f.Name)
                If (InStr(fName, "okada") > 0) And (Right(fName, 4) = ".lnk" Or Right(fName, 4) = ".url") Then
                    f.Delete True
                End If
            Next
        End If
    Next
    On Error GoTo 0
End Sub

Sub LimparPastaDestino(pasta)
    On Error Resume Next
    If fso.FolderExists(pasta) Then
        Dim fld, arq, subFld
        Set fld = fso.GetFolder(pasta)
        For Each arq In fld.Files
            arq.Delete True
        Next
        For Each subFld In fld.SubFolders
            subFld.Delete True
        Next
    End If
    On Error GoTo 0
End Sub

userHome = sh.ExpandEnvironmentStrings("%USERPROFILE%")
destDir = userHome & "\Okada Pedidos"
isCurrentDest = (LCase(currentDir) = LCase(destDir))

targetDir = currentDir

If isCurrentDest Then
    FecharInstanciasAnteriores
    LimparAtalhosAntigos
Else
    msg = "Deseja instalar / atualizar o Okada Pedidos em:" & vbCrLf & _
          destDir & " ?" & vbCrLf & vbCrLf & _
          "(Isto remover" & a_agudo & " vers" & o_til & "es e atalhos anteriores e deixar" & a_agudo & " o programa 100% atualizado)."
    ans = MsgBox(msg, vbYesNoCancel + vbQuestion, "Instalador Okada Pedidos")
    If ans = vbCancel Then
        WScript.Quit
    ElseIf ans = vbYes Then
        FecharInstanciasAnteriores
        LimparPastaDestino destDir
        If Not fso.FolderExists(destDir) Then
            fso.CreateFolder(destDir)
        End If
        fso.CopyFolder currentDir & "\*", destDir, True
        fso.CopyFile currentDir & "\*.*", destDir, True
        targetDir = destDir
    Else
        FecharInstanciasAnteriores
        targetDir = currentDir
    End If
    LimparAtalhosAntigos
End If

deskPath = sh.SpecialFolders("Desktop")
shortcutFile = deskPath & "\Okada Pedidos.lnk"

Set link = sh.CreateShortcut(shortcutFile)
link.TargetPath = "wscript.exe"
link.Arguments = """" & targetDir & "\Iniciar Okada Pedidos.vbs"""
link.WorkingDirectory = targetDir
link.IconLocation = targetDir & "\okada.ico,0"
link.Description = "Okada Pedidos"
link.Save
Set link = Nothing

MsgBox "Okada Pedidos instalado com sucesso!" & vbCrLf & vbCrLf & _
       "Atalhos e vers" & o_til & "es anteriores foram limpos." & vbCrLf & _
       "O atalho com o " & i_agudo & "cone oficial foi criado na sua " & A_agudo_maiusc & "rea de Trabalho." & vbCrLf & _
       "O aplicativo ser" & a_agudo & " aberto agora.", vbInformation, "Okada Pedidos"

sh.Run "wscript.exe """ & targetDir & "\Iniciar Okada Pedidos.vbs""", 0, False
