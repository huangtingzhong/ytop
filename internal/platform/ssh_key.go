package platform

import (
	"encoding/base64"
	"fmt"
	"strings"
	"unicode/utf16"
)

// CopyPublicKeyRemoteCmd returns the remote shell command that installs pubKeyB64
// (standard base64 of the OpenSSH authorized_keys line) on the target OS.
func CopyPublicKeyRemoteCmd(targetOS, pubKeyB64 string) string {
	if targetOS == OSWindows {
		return wrapPowerShellEncoded(copyPublicKeyWindowsScript(pubKeyB64))
	}
	return copyPublicKeyUnixCmd(pubKeyB64)
}

// DeletePublicKeyRemoteCmd returns the remote shell command that removes pubKeyB64
// from authorized_keys on the target OS.
func DeletePublicKeyRemoteCmd(targetOS, pubKeyB64 string) string {
	if targetOS == OSWindows {
		return wrapPowerShellEncoded(deletePublicKeyWindowsScript(pubKeyB64))
	}
	return deletePublicKeyUnixCmd(pubKeyB64)
}

func copyPublicKeyUnixCmd(pubKeyB64 string) string {
	return fmt.Sprintf(
		"mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '%s' | base64 -d >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys",
		pubKeyB64,
	)
}

func deletePublicKeyUnixCmd(pubKeyB64 string) string {
	return fmt.Sprintf(
		"grep -vF \"$(echo '%s' | base64 -d)\" ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp || true; mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys",
		pubKeyB64,
	)
}

func copyPublicKeyWindowsScript(pubKeyB64 string) string {
	return fmt.Sprintf(`$k=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%s')).Trim();$isAdmin=(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);if($isAdmin){New-Item -ItemType Directory -Force -Path 'C:\ProgramData\ssh'|Out-Null;$f='C:\ProgramData\ssh\administrators_authorized_keys'}else{$d=Join-Path $env:USERPROFILE '.ssh';New-Item -ItemType Directory -Force -Path $d|Out-Null;$f=Join-Path $d 'authorized_keys'};$enc=New-Object Text.UTF8Encoding $false;if((Test-Path $f)-and(Select-String -Path $f -Pattern ([regex]::Escape($k)) -SimpleMatch -Quiet)){'KEY_EXISTS'}else{if(Test-Path $f){$lines=[IO.File]::ReadAllLines($f)|Where-Object{$_.Trim()-ne ''};if($lines -notcontains $k){$lines+=$k};[IO.File]::WriteAllLines($f,$lines,$enc)}else{[IO.File]::WriteAllText($f,$k+[Environment]::NewLine,$enc)};if($isAdmin){$acl=Get-Acl $f;$acl.SetAccessRuleProtection($true,$false);$acl.Access|ForEach-Object{$null=$acl.RemoveAccessRule($_)};$null=$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule('SYSTEM','FullControl','Allow')));$null=$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule('Administrators','FullControl','Allow')));Set-Acl $f $acl}else{$sshDir=Split-Path $f -Parent;$grant=$env:USERNAME+':(F)';icacls $sshDir /inheritance:r /grant:r $grant 'SYSTEM:(F)'|Out-Null;icacls $f /inheritance:r /grant:r $grant 'SYSTEM:(F)'|Out-Null};'KEY_ADDED'}`,
		pubKeyB64,
	)
}

func deletePublicKeyWindowsScript(pubKeyB64 string) string {
	return fmt.Sprintf(`$k=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%s')).Trim();$isAdmin=(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);if($isAdmin){$f='C:\ProgramData\ssh\administrators_authorized_keys'}else{$f=Join-Path (Join-Path $env:USERPROFILE '.ssh') 'authorized_keys'};if(-not(Test-Path $f)){'KEY_NOT_FOUND';return};$enc=New-Object Text.UTF8Encoding $false;$lines=@([IO.File]::ReadAllLines($f)|Where-Object{$_.Trim()-ne $k -and $_.Trim()-ne ''});[IO.File]::WriteAllLines($f,$lines,$enc);'KEY_REMOVED'`,
		pubKeyB64,
	)
}

func wrapPowerShellEncoded(script string) string {
	return "powershell -NoProfile -EncodedCommand " + encodePowerShellCommand(script)
}

func encodePowerShellCommand(script string) string {
	u16 := utf16.Encode([]rune(script))
	buf := make([]byte, len(u16)*2)
	for i, r := range u16 {
		buf[i*2] = byte(r)
		buf[i*2+1] = byte(r >> 8)
	}
	return base64.StdEncoding.EncodeToString(buf)
}

// IsWindowsTarget reports whether targetOS selects Windows remote commands.
func IsWindowsTarget(targetOS string) bool {
	return strings.EqualFold(targetOS, OSWindows)
}
