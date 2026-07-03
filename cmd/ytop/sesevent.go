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
