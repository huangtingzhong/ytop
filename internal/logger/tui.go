package logger

import "fmt"

// TUIKeyName maps raw key bytes (including arrow pseudo-keys) to readable names.
func TUIKeyName(key byte) string {
	switch key {
	case 27:
		return "ESC"
	case 200:
		return "UP"
	case 201:
		return "DOWN"
	case 202:
		return "RIGHT"
	case 203:
		return "LEFT"
	case 3:
		return "Ctrl+C"
	default:
		if key >= 32 && key < 127 {
			return fmt.Sprintf("'%c'", key)
		}
		return fmt.Sprintf("0x%02x", key)
	}
}

// DebugTUIKey logs an interactive mode key press.
func DebugTUIKey(key byte) {
	Debug("[tui] key=%s\n", TUIKeyName(key))
}

// DebugTUIAction logs a TUI user action with optional detail.
func DebugTUIAction(action, detail string) {
	if detail != "" {
		Debug("[tui] action=%s detail=%s\n", action, detail)
		return
	}
	Debug("[tui] action=%s\n", action)
}

// DebugTUIInput logs user text input for a TUI prompt.
func DebugTUIInput(action, input string) {
	if input == "" {
		Debug("[tui] action=%s input=(cancelled/empty)\n", action)
		return
	}
	Debug("[tui] action=%s input=%q\n", action, input)
}

// DebugTUIResult logs the outcome of a TUI-triggered operation.
func DebugTUIResult(action string, err error, outputLen int) {
	if err != nil {
		Debug("[tui] action=%s result=error err=%v\n", action, err)
		return
	}
	Debug("[tui] action=%s result=ok output_bytes=%d\n", action, outputLen)
}
