package connector

import (
	"context"
	"fmt"

	"github.com/yihan/ytop/internal/config"
)

// Connector defines the interface for database connections
type Connector interface {
	// Connect establishes the connection
	Connect(ctx context.Context) error

	// ExecuteQuery executes a SQL query and returns rows as string slices
	ExecuteQuery(ctx context.Context, sql string) ([][]string, error)

	// ExecuteQueryWithHeader executes a SQL query and returns header + data rows
	ExecuteQueryWithHeader(ctx context.Context, sql string) (header []string, rows [][]string, err error)

	// Close closes the connection
	Close() error

	// IsConnected returns true if the connection is active
	IsConnected() bool
}

// NewConnector creates a connector based on configuration
func NewConnector(cfg *config.Config) (Connector, error) {
	switch cfg.ConnectionMode {
	case "local":
		return NewLocalConnector(cfg), nil
	case "ssh":
		return NewSSHConnector(cfg), nil
	default:
		return nil, fmt.Errorf("unsupported connection mode: %s", cfg.ConnectionMode)
	}
}
