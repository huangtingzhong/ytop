package logger

import (
	"fmt"
	"log"
	"os"
	"sync"
)

var (
	debugEnabled bool
	debugFile    *os.File
	debugLogger  *log.Logger
	mu           sync.Mutex
)

// Init initializes the logger
func Init(debug bool) error {
	mu.Lock()
	defer mu.Unlock()

	debugEnabled = debug

	if debug {
		// Create debug log file
		var err error
		debugFile, err = os.OpenFile("ytop_debug.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			return fmt.Errorf("failed to create debug log file: %w", err)
		}

		debugLogger = log.New(debugFile, "", log.LstdFlags)
	}

	return nil
}

// Close closes the logger
func Close() {
	mu.Lock()
	defer mu.Unlock()

	if debugFile != nil {
		debugFile.Close()
		debugFile = nil
	}
}

// DebugCommandOutput logs captured command stdout/stderr to ytop_debug.log.
func DebugCommandOutput(scope, output string, execErr error) {
	if !debugEnabled {
		return
	}

	mu.Lock()
	defer mu.Unlock()

	if debugLogger == nil {
		return
	}
	if execErr != nil {
		debugLogger.Printf("[DEBUG] [%s] execution error: %v\n", scope, execErr)
	}
	debugLogger.Printf("[DEBUG] [%s] Output (%d bytes):\n%s\n", scope, len(output), output)
}

// Debug logs a debug message
func Debug(format string, args ...interface{}) {
	if !debugEnabled {
		return
	}

	mu.Lock()
	defer mu.Unlock()

	if debugLogger != nil {
		debugLogger.Printf("[DEBUG] "+format, args...)
	}
}

// Debugf is an alias for Debug.
func Debugf(format string, args ...interface{}) {
	Debug(format, args...)
}

// DebugStep logs a major named step with optional detail to ytop_debug.log (-D).
func DebugStep(step, detail string) {
	var line string
	if detail != "" {
		line = fmt.Sprintf("=== [STEP] %s: %s ===", step, detail)
	} else {
		line = fmt.Sprintf("=== [STEP] %s ===", step)
	}
	Debug("%s\n", line)
}

// DebugSection prints a lightweight section separator to ytop_debug.log (-D).
func DebugSection(name string) {
	line := fmt.Sprintf("--- [%s] ---", name)
	Debug("%s\n", line)
}

// DebugKeyVal logs a single key=value pair indented under the current step to ytop_debug.log (-D).
func DebugKeyVal(key, val string) {
	Debug("  %s=%s\n", key, val)
}
