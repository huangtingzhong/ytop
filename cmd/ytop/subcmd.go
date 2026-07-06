package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/yihan/ytop/internal/config"
	"github.com/yihan/ytop/internal/connector"
	"github.com/yihan/ytop/internal/logger"
	"github.com/yihan/ytop/internal/subcommand"
)

func runSSH() {
	// Check for help flag anywhere in arguments
	for _, arg := range os.Args[2:] {
		if arg == "--help" || arg == "-h" || arg == "help" {
			config.PrintSSHUsage()
			return
		}
	}

	// Parse flags using dedicated FlagSet (consistent with sesstat/sesevent)
	fs := flag.NewFlagSet("ssh", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	globalFlags := config.ParseGlobalFlags(fs)

	var deleteMode bool
	fs.BoolVar(&deleteMode, "delete", false, "Delete passwordless login from remote host")

	if err := fs.Parse(os.Args[2:]); err != nil {
		if err != flag.ErrHelp {
			fmt.Fprintf(os.Stderr, "Error: %v\n\n", err)
		}
		config.PrintSSHUsage()
		os.Exit(1)
	}

	cfg, err := config.LoadSubcommandConfig(globalFlags, fs, "ssh")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Configuration error: %v\n", err)
		os.Exit(1)
	}

	// Initialize logger
	if err := logger.Init(cfg.DebugMode); err != nil {
		fmt.Fprintf(os.Stderr, "Error initializing logger: %v\n", err)
		os.Exit(1)
	}
	defer logger.Close()

	config.DebugLogSummary(cfg)

	logger.Debug("[ssh] mode=%s host=%s user=%s port=%d delete=%v\n",
		cfg.ConnectionMode, cfg.SSHHost, cfg.SSHUser, cfg.SSHPort, deleteMode)

	// Validate required parameters
	if cfg.SSHHost == "" {
		fmt.Fprintf(os.Stderr, "Error: -t <host> is required\n\n")
		config.PrintSSHUsage()
		os.Exit(1)
	}
	if cfg.SSHUser == "" {
		fmt.Fprintf(os.Stderr, "Error: -u <user> is required\n\n")
		config.PrintSSHUsage()
		os.Exit(1)
	}

	if deleteMode {
		runSSHDelete(cfg)
	} else {
		runSSHSetup(cfg)
	}
}

// runSSHSetup configures passwordless SSH login
func runSSHSetup(cfg *config.Config) {
	if cfg.SSHPassword == "" {
		fmt.Fprintf(os.Stderr, "Error: -p <password> is required\n\n")
		config.PrintSSHUsage()
		os.Exit(1)
	}

	// Step 1: Ensure local key pair
	logger.Debug("[ssh] step 1: ensuring local key pair (keyFile=%s)\n", cfg.SSHKeyFile)
	keyFile, err := connector.EnsureLocalKey(cfg.SSHKeyFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	// Step 2: Read public key
	logger.Debug("[ssh] step 2: reading public key\n")
	pubKey, err := connector.ReadPublicKey(keyFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	// Step 3: Copy public key to remote host
	logger.Debug("[ssh] step 3: copying public key to %s@%s\n", cfg.SSHUser, cfg.SSHHost)
	if err := connector.CopyPublicKeyToHost(cfg, pubKey); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	// Step 4: Test key-based authentication
	logger.Debug("[ssh] step 4: testing key-based authentication\n")
	if err := connector.TestKeyAuth(cfg, keyFile); err != nil {
		logger.Debug("[ssh] key auth test failed: %v\n", err)
		fmt.Fprintf(os.Stderr, "Error: key authentication test failed: %v\n", err)
		fmt.Fprintf(os.Stderr, "Manual steps:\n")
		fmt.Fprintf(os.Stderr, "  ssh-copy-id -i %s %s@%s\n", keyFile+".pub", cfg.SSHUser, cfg.SSHHost)
		os.Exit(1)
	}

	logger.Debug("[ssh] setup completed successfully\n")
	fmt.Printf("Success! Passwordless SSH login configured.\n")
}

// runSSHDelete removes passwordless SSH login from the remote host.
// Uses existing key auth to connect (passwordless already configured),
// removes the public key, then verifies key auth no longer works.
func runSSHDelete(cfg *config.Config) {
	// Resolve local key file
	keyFile := cfg.SSHKeyFile
	if keyFile == "" {
		keyFile = connector.FindLocalKey()
	}
	if keyFile == "" {
		fmt.Fprintf(os.Stderr, "Error: no SSH key found. Use -k <keyfile> to specify\n")
		os.Exit(1)
	}

	// Step 1: Read public key
	logger.Debug("[ssh] step 1: reading public key from %s\n", keyFile)
	pubKey, err := connector.ReadPublicKey(keyFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	// Step 2: Use key auth to connect and remove public key
	logger.Debug("[ssh] step 2: removing public key from %s@%s\n", cfg.SSHUser, cfg.SSHHost)
	if err := connector.DeletePublicKeyFromHost(cfg, keyFile, pubKey); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	// Step 3: Test that key auth no longer works (proves delete succeeded)
	logger.Debug("[ssh] step 3: verifying key auth no longer works\n")
	if err := connector.TestKeyAuth(cfg, keyFile); err == nil {
		logger.Debug("[ssh] warning: key auth still works after delete\n")
		fmt.Fprintf(os.Stderr, "Error: key authentication still works, delete may have failed\n")
		os.Exit(1)
	}

	logger.Debug("[ssh] delete completed successfully (key auth correctly denied)\n")
	fmt.Printf("Success! Passwordless login to %s@%s has been removed.\n", cfg.SSHUser, cfg.SSHHost)
}

func runSesstat() {
	// Check for help flag anywhere in arguments
	for _, arg := range os.Args[2:] {
		if arg == "--help" || arg == "-h" || arg == "help" || arg == "-help" {
			config.PrintSesstatUsage()
			return
		}
	}

	fs := flag.NewFlagSet("sesstat", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	globalFlags := config.ParseGlobalFlags(fs)

	var sids, statNames string
	fs.StringVar(&sids, "sid", "", "Session ID filter (comma-separated, e.g., 40,50,90)")
	fs.StringVar(&sids, "S", "", "Session ID filter (short)")
	fs.StringVar(&statNames, "stat", "", "Statistic name filter (comma-separated, supports % wildcard)")
	fs.StringVar(&statNames, "n", "", "Statistic name filter (short)")

	if err := fs.Parse(os.Args[2:]); err != nil {
		if err != flag.ErrHelp {
			fmt.Fprintf(os.Stderr, "Error: %v\n\n", err)
		}
		config.PrintSesstatUsage()
		os.Exit(1)
	}

	cfg, err := config.LoadSubcommandConfig(globalFlags, fs, "stat")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Configuration error: %v\n", err)
		os.Exit(1)
	}

	interval, count, topN := config.SubcommandTiming(cfg, globalFlags, subcommandVisited(fs))
	if err := logger.Init(cfg.DebugMode); err != nil {
		fmt.Fprintf(os.Stderr, "Error initializing logger: %v\n", err)
		os.Exit(1)
	}
	defer logger.Close()

	config.DebugLogSummary(cfg)

	if err := config.FinalizeSourceCmd(cfg); err != nil {
		fmt.Fprintf(os.Stderr, "Configuration error: %v\n", err)
		os.Exit(1)
	}
	if err := cfg.Validate(); err != nil {
		fmt.Fprintf(os.Stderr, "Configuration error: %v\n", err)
		os.Exit(1)
	}

	conn, err := connector.NewConnector(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error creating connector: %v\n", err)
		os.Exit(1)
	}

	ctx := context.Background()
	if err := conn.Connect(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "Error connecting to database: %v\n", err)
		os.Exit(1)
	}
	defer conn.Close()

	instIDs := fmt.Sprintf("%d", cfg.InstanceID)
	if cfg.InstanceID == 0 {
		instIDs = ""
	}

	qc := &subcommand.QueryConfig{
		ViewName:      "gv$sesstat a, v$statname b",
		ValueColumns:  []string{"a.value"},
		FilterColumn:  "b.name",
		ExcludeFilter: "a.statistic# = b.statistic#",
		NoAlias:       true,
	}

	displayFunc := func(deltas []subcommand.Record, topN int, instIDs, sids, names string, sample, totalSamples int) {
		subcommand.DisplayResults(deltas, topN, instIDs, sids, names, sample, totalSamples, "Session Statistics", false)
	}

	subcommand.RunSubcommand(ctx, conn, qc, interval, count, topN, instIDs, sids, statNames, displayFunc)
}

func subcommandVisited(fs *flag.FlagSet) map[string]bool {
	visited := map[string]bool{}
	fs.Visit(func(f *flag.Flag) { visited[f.Name] = true })
	return visited
}

func runSesevent() {
	for _, arg := range os.Args[2:] {
		if arg == "--help" || arg == "-h" || arg == "help" || arg == "-help" {
			config.PrintSeseventUsage()
			return
		}
	}

	fs := flag.NewFlagSet("sesevent", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	globalFlags := config.ParseGlobalFlags(fs)

	var sids, eventNames string
	fs.StringVar(&sids, "sid", "", "Session ID filter (comma-separated, e.g., 40,50,90)")
	fs.StringVar(&sids, "S", "", "Session ID filter (short)")
	fs.StringVar(&eventNames, "event", "", "Event name filter (comma-separated, supports % wildcard)")
	fs.StringVar(&eventNames, "e", "", "Event name filter (short)")

	if err := fs.Parse(os.Args[2:]); err != nil {
		if err != flag.ErrHelp {
			fmt.Fprintf(os.Stderr, "Error: %v\n\n", err)
		}
		config.PrintSeseventUsage()
		os.Exit(1)
	}

	cfg, err := config.LoadSubcommandConfig(globalFlags, fs, "event")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Configuration error: %v\n", err)
		os.Exit(1)
	}

	interval, count, topN := config.SubcommandTiming(cfg, globalFlags, subcommandVisited(fs))

	if err := logger.Init(cfg.DebugMode); err != nil {
		fmt.Fprintf(os.Stderr, "Error initializing logger: %v\n", err)
		os.Exit(1)
	}
	defer logger.Close()

	config.DebugLogSummary(cfg)

	if err := config.FinalizeSourceCmd(cfg); err != nil {
		fmt.Fprintf(os.Stderr, "Configuration error: %v\n", err)
		os.Exit(1)
	}
	if err := cfg.Validate(); err != nil {
		fmt.Fprintf(os.Stderr, "Configuration error: %v\n", err)
		os.Exit(1)
	}

	conn, err := connector.NewConnector(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error creating connector: %v\n", err)
		os.Exit(1)
	}

	ctx := context.Background()
	if err := conn.Connect(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "Error connecting to database: %v\n", err)
		os.Exit(1)
	}
	defer conn.Close()

	instIDs := fmt.Sprintf("%d", cfg.InstanceID)
	if cfg.InstanceID == 0 {
		instIDs = ""
	}

	qc := &subcommand.QueryConfig{
		ViewName:      "gv$session_event",
		ValueColumns:  []string{"a.total_waits", "a.time_waited"},
		FilterColumn:  "a.event",
		ExcludeFilter: "a.wait_class NOT IN ('Idle')",
	}

	displayFunc := func(deltas []subcommand.Record, topN int, instIDs, sids, names string, sample, totalSamples int) {
		subcommand.DisplayResults(deltas, topN, instIDs, sids, names, sample, totalSamples, "Session Events", true)
	}

	subcommand.RunSubcommand(ctx, conn, qc, interval, count, topN, instIDs, sids, eventNames, displayFunc)
}
