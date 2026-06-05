package logger

import (
	"log"
	"os"
	"strings"
	"testing"
)

func TestDebugCommandOutputWritesToFile(t *testing.T) {
	const logFile = "ytop_debug_test.log"
	_ = os.Remove(logFile)

	debugEnabled = true
	f, err := os.OpenFile(logFile, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		t.Fatal(err)
	}
	debugLogger = log.New(f, "", log.LstdFlags)

	DebugCommandOutput("local-sql-script", "SID\tUSER\n1\troot\n", nil)
	_ = f.Close()

	data, err := os.ReadFile(logFile)
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	if !strings.Contains(text, "[local-sql-script] Output") {
		t.Fatalf("missing output header: %q", text)
	}
	if !strings.Contains(text, "SID\tUSER") {
		t.Fatalf("missing command output body: %q", text)
	}

	_ = os.Remove(logFile)
	debugEnabled = false
	debugLogger = nil
}
