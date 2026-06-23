package platform

import (
	"encoding/base64"
	"strings"
	"testing"
)

func TestCopyPublicKeyRemoteCmd_unix(t *testing.T) {
	got := CopyPublicKeyRemoteCmd(OSUnix, "dGVzdA==")
	if !strings.Contains(got, "mkdir -p ~/.ssh") {
		t.Fatalf("unix copy cmd = %q", got)
	}
	if !strings.Contains(got, "dGVzdA==") {
		t.Fatalf("unix copy cmd missing payload: %q", got)
	}
}

func TestCopyPublicKeyRemoteCmd_windows(t *testing.T) {
	got := CopyPublicKeyRemoteCmd(OSWindows, "dGVzdA==")
	if !strings.HasPrefix(got, "powershell -NoProfile -EncodedCommand ") {
		t.Fatalf("windows copy cmd = %q", got)
	}
	payload := strings.TrimPrefix(got, "powershell -NoProfile -EncodedCommand ")
	decoded, err := decodePowerShellCommand(payload)
	if err != nil {
		t.Fatalf("decode encoded command: %v", err)
	}
	for _, want := range []string{
		"administrators_authorized_keys",
		"authorized_keys",
		"FromBase64String('dGVzdA==')",
		"KEY_ADDED",
	} {
		if !strings.Contains(decoded, want) {
			t.Fatalf("decoded script missing %q: %q", want, decoded)
		}
	}
}

func TestDeletePublicKeyRemoteCmd_windows(t *testing.T) {
	got := DeletePublicKeyRemoteCmd(OSWindows, "dGVzdA==")
	payload := strings.TrimPrefix(got, "powershell -NoProfile -EncodedCommand ")
	decoded, err := decodePowerShellCommand(payload)
	if err != nil {
		t.Fatalf("decode encoded command: %v", err)
	}
	if !strings.Contains(decoded, "KEY_REMOVED") {
		t.Fatalf("decoded delete script = %q", decoded)
	}
}

func decodePowerShellCommand(encoded string) (string, error) {
	raw, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return "", err
	}
	if len(raw)%2 != 0 {
		return "", base64.CorruptInputError(0)
	}
	runes := make([]rune, len(raw)/2)
	for i := 0; i < len(runes); i++ {
		runes[i] = rune(raw[i*2]) | rune(raw[i*2+1])<<8
	}
	return string(runes), nil
}
