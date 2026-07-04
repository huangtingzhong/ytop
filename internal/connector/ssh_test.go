package connector

import (
	"errors"
	"fmt"
	"testing"
)

func TestIsRecoverableSSHError(t *testing.T) {
	cases := []struct {
		err  error
		want bool
	}{
		{nil, false},
		{fmt.Errorf("failed to query gv$sysstat: permission denied"), false},
		{fmt.Errorf("not connected"), true},
		{fmt.Errorf("failed to create SSH session: EOF"), true},
		{fmt.Errorf("SFTP upload failed for \"/tmp/x\": connection reset by peer"), true},
		{fmt.Errorf("SSH command execution failed: %w", errors.New("broken pipe")), true},
	}
	for _, c := range cases {
		if got := IsRecoverableSSHError(c.err); got != c.want {
			t.Fatalf("IsRecoverableSSHError(%v) = %v, want %v", c.err, got, c.want)
		}
	}
}
