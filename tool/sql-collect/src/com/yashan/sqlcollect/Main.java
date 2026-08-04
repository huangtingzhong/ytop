package com.yashan.sqlcollect;

import com.yashan.sqlcollect.cli.Args;
import com.yashan.sqlcollect.collect.CollectCommand;
import com.yashan.sqlcollect.replay.ReplayCommand;

/** 入口: collect | replay | check | --version | -h */
public class Main {

    public static void main(String[] argv) {
        if (!Version.ensureRuntimeSupported()) {
            System.exit(1);
        }
        Args args = Args.parse(argv);
        if (args.version) {
            System.out.println("sql-collect " + Version.VERSION
                    + " (Java " + Version.MIN_JAVA_MAJOR + "+; runtime "
                    + System.getProperty("java.version", "?") + ")");
            System.exit(0);
        }
        if (args.help) {
            printHelp();
            System.exit(0);
        }
        int rc;
        if ("replay".equals(args.command)) {
            rc = new ReplayCommand().run(args);
        } else if ("check".equals(args.command)) {
            rc = new CheckCommand().run(args);
        } else {
            rc = new CollectCommand().run(args);
        }
        System.exit(rc);
    }

    private static void printHelp() {
        System.out.println("sql-collect " + Version.VERSION + " - JDBC SQL collect + replay");
        System.out.println("Requires Java " + Version.MIN_JAVA_MAJOR
                + "+ (bytecode target 8; tested on 8/11/17/21).");
        System.out.println();
        System.out.println("Usage:");
        System.out.println("  sql-collect [--version|-V] [--help|-h]");
        System.out.println("  sql-collect check [options]     health check before long collect/replay");
        System.out.println("  sql-collect collect [options]");
        System.out.println("  sql-collect replay [options]");
        System.out.println();
        System.out.println("Short options: common=lowercase, uncommon=UPPERCASE; see map below.");
        System.out.println();
        System.out.println("Check options:");
        System.out.println("  --jdbc-config|-j PATH  JDBC INI (default ./jdbc_replay.ini)");
        System.out.println("  --log-dir|-l DIR       log directory (default ./logs)");
        System.out.println("  --debug|-d BOOL        write DEBUG/STEP to debug log (default true)");
        System.out.println();
        System.out.println("Collect options:");
        System.out.println("  --outdir|-o DIR        output directory (default ./sql_collect)");
        System.out.println("  --log-dir|-l DIR       log directory (default ./logs)");
        System.out.println("  --jdbc-config|-j PATH  JDBC INI (default ./jdbc_replay.ini)");
        System.out.println("  --interval|-i SEC      poll interval seconds");
        System.out.println("  --count|-c N           number of rounds");
        System.out.println("  --skip-backup          skip HTZ_GV_* backup");
        System.out.println("  --backup-only          backup only, no reports");
        System.out.println("  --skip-replay-export   skip replay package export");
        System.out.println("  --max-new|-m N         cap new sql_id per round");
        System.out.println("  --sql-id|-s ID[,ID...] force export/report these sql_id(s) only");
        System.out.println("  --report-timeout|-T SEC  report gather timeout (default 600; 0=unlimited)");
        System.out.println("  --schema-via-alter|-A  ALTER SESSION for current_schema on connect");
        System.out.println("  --current-schema|-C NAME  optional schema for collect session");
        System.out.println("  --debug|-d BOOL        write DEBUG/STEP to debug log (default true)");
        System.out.println();
        System.out.println("Replay options:");
        System.out.println("  --jdbc-config|-j PATH  JDBC INI (default ./jdbc_replay.ini)");
        System.out.println("  --init-config          write jdbc_replay.ini template");
        System.out.println("  --overwrite            with --init-config, replace existing file");
        System.out.println("  --source|-S file|htz|gv  replay source (default file)");
        System.out.println("  --sql-id|-s ID[,ID...] target sql_id(s)");
        System.out.println("  --outdir|-o DIR        replay package root / results dir (default ./sql_collect)");
        System.out.println("  --dry-run              validate only (DEFAULT; no execute)");
        System.out.println("  --exec|-e              LIVE execute (required for real replay)");
        System.out.println("  --force|-f             allow non-query SQL (with --exec)");
        System.out.println("  --parallel|-p N        parallel targets (default 1)");
        System.out.println("  --sessions|-N N        concurrent sessions per SQL (default 1)");
        System.out.println("  --timeout|-t SEC       overall replay timeout (default 600; 0=unlimited; exit 124)");
        System.out.println("  --results-csv|-R PATH  replay_results.csv path (default OUTDIR/replay_results.csv)");
        System.out.println("  --schema-via-alter|-A  login as jdbc user + ALTER SESSION");
        System.out.println("  --on-sha-mismatch|-M MODE  fail=block (DEFAULT); warn=WARN then continue");
        System.out.println("  --allow-sha-mismatch   alias for --on-sha-mismatch warn");
        System.out.println("  --debug|-d BOOL        write DEBUG/STEP to debug log (default true)");
        System.out.println("  --no-debug             alias for --debug false");
        System.out.println("  --log-dir|-l DIR       log directory (default ./logs)");
    }
}
