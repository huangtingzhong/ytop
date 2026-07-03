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
