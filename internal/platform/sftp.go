package platform

import (
	"fmt"

	"github.com/pkg/sftp"
	"golang.org/x/crypto/ssh"
)

// UploadFileViaSFTP uploads content to remotePath on the SSH server using SFTP.
// Creates parent directories implicitly via the SFTP client (server must permit).
// The caller is responsible for ensuring the remote directory exists when needed.
func UploadFileViaSFTP(client *ssh.Client, content []byte, remotePath string) error {
	sc, err := sftp.NewClient(client)
	if err != nil {
		return fmt.Errorf("sftp: failed to open subsystem: %w", err)
	}
	defer sc.Close()

	f, err := sc.Create(remotePath)
	if err != nil {
		return fmt.Errorf("sftp: failed to create remote file %q: %w", remotePath, err)
	}
	defer f.Close()

	if _, err := f.Write(content); err != nil {
		return fmt.Errorf("sftp: failed to write remote file %q: %w", remotePath, err)
	}
	return nil
}

// DeleteFileViaSFTP removes a remote file via SFTP (best-effort cleanup).
func DeleteFileViaSFTP(client *ssh.Client, remotePath string) error {
	sc, err := sftp.NewClient(client)
	if err != nil {
		return fmt.Errorf("sftp: failed to open subsystem: %w", err)
	}
	defer sc.Close()

	if err := sc.Remove(remotePath); err != nil {
		return fmt.Errorf("sftp: failed to remove remote file %q: %w", remotePath, err)
	}
	return nil
}

// VerifyFileViaSFTP checks that remotePath exists and is non-empty after upload.
func VerifyFileViaSFTP(client *ssh.Client, remotePath string) error {
	sc, err := sftp.NewClient(client)
	if err != nil {
		return fmt.Errorf("sftp: failed to open subsystem: %w", err)
	}
	defer sc.Close()

	info, err := sc.Stat(remotePath)
	if err != nil {
		return fmt.Errorf("sftp: stat %q: %w", remotePath, err)
	}
	if info.IsDir() {
		return fmt.Errorf("sftp: %q is a directory", remotePath)
	}
	if info.Size() == 0 {
		return fmt.Errorf("sftp: %q is empty", remotePath)
	}
	return nil
}
