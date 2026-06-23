' Ajoute le widget au demarrage de Windows (sur CE PC).
' A lancer apres avoir copie le dossier sur le disque dur du PC.
Set sh = CreateObject("WScript.Shell")
d = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & d & "\Installer-Demarrage.ps1""", 0, True
MsgBox "Le widget Claude a ete ajoute au demarrage de Windows." & vbCrLf & vbCrLf & "Il s'affichera automatiquement a chaque ouverture de session.", 64, "Widget Claude"
