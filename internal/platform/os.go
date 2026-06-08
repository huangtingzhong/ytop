package platform

import (
	"context"
	"runtime"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"
)

// OS type constants used throughout the codebase.
const (
	OSUnix    = "unix"
	OSWindows = "windows"
)

// LocalOS returns the OS of the machine where ytop is currently running.
func LocalOS() string {
	if runtime.GOOS == "windows" {
		return OSWindows
	}
	return OSUnix
}

// DetectRemoteOS probes the remote host OS via an existing SSH client.
// Returns OSWindows or OSUnix. Always falls back to OSUnix on any error or timeout.
// debugLog may be nil.
func DetectRemoteOS(ctx context.Context, client *ssh.Client, debugLog func(string, ...interface{})) string {
	if debugLog != nil {
		debugLog("[platform] detecting remote OS via SSH probe\n")
	}

	type probeResult struct {
		os  string
		err error
	}
	done := make(chan probeResult, 1)

	go func() {
		os, err := probeRemoteOS(client)
		done <- probeResult{os, err}
	}()

	probeCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	select {
	case <-probeCtx.Done():
		if debugLog != nil {
			debugLog("[platform] remote OS probe timed out (5s); defaulting to unix\n")
		}
		return OSUnix
	case r := <-done:
		if r.err != nil {
			if debugLog != nil {
				debugLog("[platform] remote OS probe error: %v; defaulting to unix\n", r.err)
			}
			return OSUnix
		}
		if debugLog != nil {
			debugLog("[platform] remote OS detected: %s\n", r.os)
		}
		return r.os
	}
}

// probeRemoteOS runs `cmd /C echo PROBE_WIN` over SSH.
// Windows OpenSSH runs this in cmd.exe and returns "PROBE_WIN" with exit 0.
// On Unix, `cmd` is not found and the session exits non-zero.
func probeRemoteOS(client *ssh.Client) (string, error) {
	session, err := client.NewSession()
	if err != nil {
		return OSUnix, err
	}
	defer session.Close()

	out, err := session.CombinedOutput(`cmd /C "echo PROBE_WIN"`)
	if err == nil && strings.Contains(string(out), "PROBE_WIN") {
		return OSWindows, nil
	}
	return OSUnix, nil
}
