package connector

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"

	"github.com/yihan/ytop/internal/config"
	"github.com/yihan/ytop/internal/logger"
)

// FindLocalKey returns the path to an existing default SSH private key,
// or an empty string if none is found.
func FindLocalKey() string {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		logger.Debug("[ssh-init] cannot determine home directory: %v\n", err)
		return ""
	}
	defaultKey := filepath.Join(homeDir, ".ssh", "id_rsa")
	if _, err := os.Stat(defaultKey); err == nil {
		logger.Debug("[ssh-init] found existing key: %s\n", defaultKey)
		return defaultKey
	}
	logger.Debug("[ssh-init] no default key at %s\n", defaultKey)
	return ""
}

// EnsureLocalKey checks for an existing SSH key pair or generates one.
// Returns the path to the private key file.
func EnsureLocalKey(keyFile string) (string, error) {
	// If a specific key file is given, check it exists
	if keyFile != "" {
		if _, err := os.Stat(keyFile); err != nil {
			return "", fmt.Errorf("specified key file not found: %s", keyFile)
		}
		logger.Debug("[ssh-init] using specified key file: %s\n", keyFile)
		return keyFile, nil
	}

	// Try default key path
	if k := FindLocalKey(); k != "" {
		return k, nil
	}

	// No key found — generate one
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("cannot determine home directory: %w", err)
	}
	defaultKey := filepath.Join(homeDir, ".ssh", "id_rsa")

	fmt.Printf("No SSH key found at %s\n", defaultKey)
	fmt.Print("Generate a new RSA 2048 key pair? [Y/n] ")

	var answer string
	fmt.Scanln(&answer)
	answer = strings.TrimSpace(strings.ToLower(answer))
	if answer != "" && answer != "y" && answer != "yes" {
		logger.Debug("[ssh-init] key generation cancelled by user\n")
		return "", fmt.Errorf("SSH key generation cancelled")
	}

	// Ensure ~/.ssh directory exists
	sshDir := filepath.Join(homeDir, ".ssh")
	if err := os.MkdirAll(sshDir, 0700); err != nil {
		return "", fmt.Errorf("failed to create %s: %w", sshDir, err)
	}
	logger.Debug("[ssh-init] created directory: %s\n", sshDir)

	// Generate RSA 2048 key pair using pure Go (no dependency on ssh-keygen command)
	if err := generateRSAKeyPair(defaultKey); err != nil {
		return "", fmt.Errorf("failed to generate SSH key: %w", err)
	}

	logger.Debug("[ssh-init] generated new RSA 2048 key pair: %s\n", defaultKey)
	fmt.Printf("SSH key pair generated: %s\n", defaultKey)
	return defaultKey, nil
}

// ReadPublicKey reads the .pub file corresponding to the given private key
func ReadPublicKey(keyFile string) (string, error) {
	pubFile := keyFile + ".pub"
	logger.Debug("[ssh-init] reading public key from: %s\n", pubFile)

	data, err := os.ReadFile(pubFile)
	if err != nil {
		return "", fmt.Errorf("failed to read public key %s: %w", pubFile, err)
	}

	pubKey := strings.TrimSpace(string(data))
	logger.Debug("[ssh-init] public key loaded (%d bytes): %s...%s\n", len(pubKey), pubKey[:20], pubKey[len(pubKey)-20:])
	return pubKey, nil
}

// generateRSAKeyPair creates a 2048-bit RSA key pair in pure Go.
// Writes <basePath> (private) and <basePath>.pub (public in OpenSSH format).
func generateRSAKeyPair(basePath string) error {
	logger.Debug("[ssh-init] generating RSA 2048 key pair at %s\n", basePath)

	privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return fmt.Errorf("RSA key generation failed: %w", err)
	}

	// Write private key (PEM format, 0600)
	privFile, err := os.OpenFile(basePath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return fmt.Errorf("failed to create private key file: %w", err)
	}
	defer privFile.Close()

	if err := pem.Encode(privFile, &pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(privateKey),
	}); err != nil {
		return fmt.Errorf("failed to write private key: %w", err)
	}
	logger.Debug("[ssh-init] private key written: %s (0600)\n", basePath)

	// Write public key (OpenSSH authorized_keys format)
	pubKey, err := ssh.NewPublicKey(&privateKey.PublicKey)
	if err != nil {
		return fmt.Errorf("failed to derive SSH public key: %w", err)
	}

	pubFile, err := os.OpenFile(basePath+".pub", os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0644)
	if err != nil {
		return fmt.Errorf("failed to create public key file: %w", err)
	}
	defer pubFile.Close()

	if _, err := pubFile.Write(ssh.MarshalAuthorizedKey(pubKey)); err != nil {
		return fmt.Errorf("failed to write public key: %w", err)
	}
	logger.Debug("[ssh-init] public key written: %s.pub (0644)\n", basePath)

	return nil
}

// CopyPublicKeyToHost connects to the remote host using password authentication
// and appends the public key to ~/.ssh/authorized_keys.
func CopyPublicKeyToHost(cfg *config.Config, pubKey string) error {
	sshConfig := &ssh.ClientConfig{
		User:            cfg.SSHUser,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         time.Duration(cfg.SSHTimeout) * time.Second,
		Auth: []ssh.AuthMethod{
			ssh.Password(cfg.SSHPassword),
			ssh.KeyboardInteractive(func(user, instruction string, questions []string, echos []bool) ([]string, error) {
				answers := make([]string, len(questions))
				for i := range answers {
					answers[i] = cfg.SSHPassword
				}
				return answers, nil
			}),
		},
	}

	addr := fmt.Sprintf("%s:%d", cfg.SSHHost, cfg.SSHPort)
	logger.Debug("[ssh-init] connecting to %s (user=%s, auth=password)\n", addr, cfg.SSHUser)

	client, err := ssh.Dial("tcp", addr, sshConfig)
	if err != nil {
		logger.Debug("[ssh-init] connection failed: %v\n", err)
		return fmt.Errorf("SSH connection to %s failed: %w", addr, err)
	}
	defer client.Close()
	logger.Debug("[ssh-init] connected to %s\n", addr)

	session, err := client.NewSession()
	if err != nil {
		return fmt.Errorf("failed to create SSH session: %w", err)
	}
	defer session.Close()

	// Build remote command: ensure ~/.ssh dir, append key, deduplicate, set permissions.
	// Use base64 to safely transfer the public key (avoids shell injection from key comments).
	encoded := base64.StdEncoding.EncodeToString([]byte(pubKey))
	remoteCmd := fmt.Sprintf(
		"mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '%s' | base64 -d >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys",
		encoded,
	)

	logger.Debug("[ssh-init] remote command: %s\n", remoteCmd)

	output, err := session.CombinedOutput(remoteCmd)
	if err != nil {
		logger.Debug("[ssh-init] remote command failed: %v, output: %s\n", err, string(output))
		return fmt.Errorf("failed to write public key to remote host: %w\n%s", err, string(output))
	}

	logger.Debug("[ssh-init] public key written successfully, output: %s\n", strings.TrimSpace(string(output)))
	return nil
}

// DeletePublicKeyFromHost connects to the remote host using key authentication
// and removes the matching public key line from ~/.ssh/authorized_keys.
func DeletePublicKeyFromHost(cfg *config.Config, keyFile string, pubKey string) error {
	logger.Debug("[ssh-init] reading private key: %s\n", keyFile)

	key, err := readSSHKey(keyFile)
	if err != nil {
		logger.Debug("[ssh-init] failed to read key file: %v\n", err)
		return fmt.Errorf("failed to read SSH key file: %w", err)
	}

	signer, err := ssh.ParsePrivateKey(key)
	if err != nil {
		logger.Debug("[ssh-init] failed to parse key: %v\n", err)
		return fmt.Errorf("failed to parse SSH key file: %w", err)
	}

	sshConfig := &ssh.ClientConfig{
		User:            cfg.SSHUser,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         time.Duration(cfg.SSHTimeout) * time.Second,
		Auth:            []ssh.AuthMethod{ssh.PublicKeys(signer)},
	}

	addr := fmt.Sprintf("%s:%d", cfg.SSHHost, cfg.SSHPort)
	logger.Debug("[ssh-init] connecting to %s (user=%s, auth=key)\n", addr, cfg.SSHUser)

	client, err := ssh.Dial("tcp", addr, sshConfig)
	if err != nil {
		logger.Debug("[ssh-init] connection failed: %v\n", err)
		return fmt.Errorf("SSH key auth to %s failed (passwordless login not configured?): %w", addr, err)
	}
	defer client.Close()
	logger.Debug("[ssh-init] connected to %s\n", addr)

	session, err := client.NewSession()
	if err != nil {
		return fmt.Errorf("failed to create SSH session: %w", err)
	}
	defer session.Close()

	// Remove the matching line from authorized_keys.
	// Use base64 + grep -vF to safely match the key (avoids shell injection).
	// Append "|| true" so grep exit 1 (no remaining lines) does not abort the chain.
	encoded := base64.StdEncoding.EncodeToString([]byte(pubKey))
	remoteCmd := fmt.Sprintf(
		"grep -vF \"$(echo '%s' | base64 -d)\" ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp || true; mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys",
		encoded,
	)

	logger.Debug("[ssh-init] remote command: %s\n", remoteCmd)

	output, err := session.CombinedOutput(remoteCmd)
	if err != nil {
		logger.Debug("[ssh-init] remote command failed: %v, output: %s\n", err, string(output))
		return fmt.Errorf("failed to remove public key from remote host: %w\n%s", err, string(output))
	}

	logger.Debug("[ssh-init] public key removed successfully, output: %s\n", strings.TrimSpace(string(output)))
	return nil
}

// TestKeyAuth tests that key-based authentication works by connecting with the private key.
func TestKeyAuth(cfg *config.Config, keyFile string) error {
	logger.Debug("[ssh-init] reading private key: %s\n", keyFile)

	key, err := readSSHKey(keyFile)
	if err != nil {
		logger.Debug("[ssh-init] failed to read key file: %v\n", err)
		return fmt.Errorf("failed to read key file: %w", err)
	}

	signer, err := ssh.ParsePrivateKey(key)
	if err != nil {
		logger.Debug("[ssh-init] failed to parse key: %v\n", err)
		return fmt.Errorf("failed to parse private key: %w", err)
	}

	sshConfig := &ssh.ClientConfig{
		User:            cfg.SSHUser,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         time.Duration(cfg.SSHTimeout) * time.Second,
		Auth:            []ssh.AuthMethod{ssh.PublicKeys(signer)},
	}

	addr := fmt.Sprintf("%s:%d", cfg.SSHHost, cfg.SSHPort)
	logger.Debug("[ssh-init] testing key auth to %s (user=%s)\n", addr, cfg.SSHUser)

	client, err := ssh.Dial("tcp", addr, sshConfig)
	if err != nil {
		logger.Debug("[ssh-init] key auth test failed: %v\n", err)
		return fmt.Errorf("key-based authentication failed: %w", err)
	}
	client.Close()

	logger.Debug("[ssh-init] key auth test passed\n")
	return nil
}
