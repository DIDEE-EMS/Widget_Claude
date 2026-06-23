' Double-cliquez ce fichier pour afficher le widget flottant sur le bureau.
Set sh = CreateObject("WScript.Shell")
d = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & d & "\ClaudeUsageWidget.ps1""", 0, False
