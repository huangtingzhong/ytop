package display

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"
	"time"

	"github.com/yihan/ytop/internal/config"
	"github.com/yihan/ytop/internal/connector"
	"github.com/yihan/ytop/internal/logger"
	"github.com/yihan/ytop/internal/models"
	"github.com/yihan/ytop/internal/scripts"
	"golang.org/x/term"
)

// Display handles terminal output
type Display struct {
	cfg        *config.Config
	outputFile *os.File
	iteration  int
	isTerminal bool
}

// NewDisplay creates a new display
func NewDisplay(cfg *config.Config) (*Display, error) {
	isTerminal := term.IsTerminal(int(os.Stdout.Fd()))

	d := &Display{
		cfg:        cfg,
		isTerminal: isTerminal,
	}

	// Disable color if not outputting to a terminal
	if !isTerminal {
		d.cfg.ColorEnabled = false
	}

	// Open output file if specified
	if cfg.OutputFile != "" {
		f, err := os.OpenFile(cfg.OutputFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
		if err != nil {
			return nil, fmt.Errorf("failed to open output file: %w", err)
		}
		d.outputFile = f
	}

	return d, nil
}

// Render renders the snapshot to terminal and optionally to file
func (d *Display) Render(snapshot *models.Snapshot) {
	d.iteration++

	if d.cfg.DebugMode {
		logger.Debug("[display] Render iteration #%d: sysStats=%d events=%d sessionMetrics=%d sessionDetails=%d\n",
			d.iteration, len(snapshot.SysStats), len(snapshot.SystemEvents), len(snapshot.SessionMetrics), len(snapshot.SessionDetails))
	}

	// Clear screen only if output is to a terminal
	if d.isTerminal {
		fmt.Print("\033[2J\033[H")
	}

	var output strings.Builder

	// Header
	d.renderHeader(&output, snapshot.Timestamp)

	// v$sysstat metrics
	d.renderSysStats(&output, snapshot.SysStats)

	// v$system_event TOP N
	d.renderSystemEvents(&output, snapshot.SystemEvents)

	// Session metrics TOP N
	d.renderSessionMetrics(&output, snapshot.SessionMetrics)

	// Session details
	d.renderSessionDetails(&output, snapshot.SessionDetails)

	// Footer
	d.renderFooter(&output)

	// Print to terminal
	fmt.Print(output.String())

	// Write to file if configured
	if d.outputFile != nil {
		d.outputFile.WriteString(output.String())
		d.outputFile.WriteString("\n" + strings.Repeat("=", 120) + "\n\n")
	}
}

// renderHeader renders the header section
func (d *Display) renderHeader(out *strings.Builder, timestamp time.Time) {
	// Only show timestamp when output file is specified
	if d.cfg.OutputFile != "" {
		out.WriteString(fmt.Sprintf("Time: %s", timestamp.Format("2006-01-02 15:04:05")))
		if d.cfg.Count > 0 {
			out.WriteString(fmt.Sprintf(" | Iteration: %d / %d", d.iteration, d.cfg.Count))
		}
		out.WriteString("\n")
		out.WriteString(strings.Repeat("-", 120))
		out.WriteString("\n\n")
	}
}

// renderSysStats renders v$sysstat metrics in a single row (rates + IO latency ms).
func (d *Display) renderSysStats(out *strings.Builder, metrics []models.SysStatMetric) {
	if len(metrics) == 0 {
		out.WriteString(d.colorize("v$SYSSTAT Metrics (Per Second)\n", "yellow"))
		out.WriteString(strings.Repeat("-", 120))
		out.WriteString("\nNo metrics available\n\n")
		return
	}

	if !d.sysStatsReady(metrics) {
		out.WriteString(d.colorize("v$SYSSTAT Metrics (Per Second)\n", "yellow"))
		out.WriteString(strings.Repeat("-", 120))
		out.WriteString("\nCollecting baseline data...\n\n")
		return
	}

	d.renderSysStatPanel(out, "v$SYSSTAT Metrics (Per Second)", config.SysStatDisplayNames(), metrics)
}

func (d *Display) sysStatsReady(metrics []models.SysStatMetric) bool {
	display := make(map[string]bool, len(config.SysStatDisplayNames()))
	for _, n := range config.SysStatDisplayNames() {
		display[n] = true
	}
	for _, m := range metrics {
		if config.IsSysStatSourceOnly(m.Name) {
			continue
		}
		if !display[m.Name] {
			continue
		}
		if m.IsIntervalAvg && m.IntervalValue > 0.001 {
			return true
		}
		if m.DeltaPerSec > 0.01 {
			return true
		}
	}
	return false
}

func (d *Display) renderSysStatPanel(out *strings.Builder, title string, order []string, metrics []models.SysStatMetric) {
	out.WriteString(d.colorize(title+"\n", "yellow"))
	out.WriteString(strings.Repeat("-", 120))
	out.WriteString("\n")

	colWidth := 6
	nameMap := sysStatShortNames()

	instMetrics := make(map[int]map[string]models.SysStatMetric)
	var instIDs []int
	seenInst := make(map[int]bool)
	for _, m := range metrics {
		if _, ok := instMetrics[m.InstID]; !ok {
			instMetrics[m.InstID] = make(map[string]models.SysStatMetric)
		}
		instMetrics[m.InstID][m.Name] = m
		if !seenInst[m.InstID] {
			seenInst[m.InstID] = true
			instIDs = append(instIDs, m.InstID)
		}
	}
	sort.Ints(instIDs)

	out.WriteString(d.colorize(fmt.Sprintf("%2s", "I"), "bold"))
	out.WriteString(" ")
	for i, name := range order {
		shortName := nameMap[name]
		if shortName == "" {
			shortName = d.truncate(name, colWidth)
		}
		if i > 0 {
			out.WriteString(" ")
		}
		out.WriteString(d.colorize(fmt.Sprintf("%*s", colWidth, shortName), "bold"))
	}
	out.WriteString("\n")

	for _, instID := range instIDs {
		out.WriteString(fmt.Sprintf("%2d", instID))
		out.WriteString(" ")
		row := instMetrics[instID]
		for i, name := range order {
			if i > 0 {
				out.WriteString(" ")
			}
			m, ok := row[name]
			if !ok {
				out.WriteString(fmt.Sprintf("%*s", colWidth, "0"))
				continue
			}
			var valueStr string
			if m.IsIntervalAvg {
				if m.IntervalValue > 0.001 {
					valueStr = d.formatNumber(m.IntervalValue)
				} else {
					valueStr = "0"
				}
			} else if m.DeltaPerSec > 0.01 {
				valueStr = d.formatNumber(m.DeltaPerSec)
			} else {
				valueStr = "0"
			}
			out.WriteString(fmt.Sprintf("%*s", colWidth, valueStr))
		}
		out.WriteString("\n")
	}
	out.WriteString("\n")
}

func sysStatShortNames() map[string]string {
	return map[string]string{
		"BLOCK CHANGES":                   "BLKCHG",
		"BUFFER CR GETS":                  "CRGETS",
		"BUFFER GETS":                     "GETS",
		"COMMITS":                         "COMMIT",
		"CPU TIME":                        "CPUTIM",
		"DB TIME":                         "DBTIM",
		"DISK READS":                      "PHYRD",
		"DISK WRITES":                     "PHYWR",
		"EXECUTE COUNT":                   "EXEC",
		"INSERT COUNT":                    "INSERT",
		"LOGONS TOTAL":                    "LOGONS",
		"PARSE COUNT (HARD)":              "HRDPRS",
		"QUERY COUNT":                     "QUERY",
		"REDO SIZE":                       "REDO",
		config.MetricCheckpointsCompleted: "CHKPT",
		config.MetricUserIOWaitTime:       "IOWAIT",
		config.MetricVMOpen:               "VMOPN",
		config.MetricVMSwapOut:            "VMSWP",
		config.DerivedAvgReadMS:           "RDMS",
		config.DerivedAvgWriteMS:          "WRMS",
	}
}

// renderSystemEvents renders v$system_event TOP N
func (d *Display) renderSystemEvents(out *strings.Builder, events []models.SystemEvent) {
	out.WriteString(d.colorize(fmt.Sprintf("v$SYSTEM_EVENT TOP %d (By Wait Time)\n", d.cfg.EventTopN), "yellow"))
	out.WriteString(strings.Repeat("-", 120))
	out.WriteString("\n")

	if len(events) == 0 {
		out.WriteString("Collecting baseline data...\n\n")
		return
	}

	// Column widths
	instWidth := 2
	eventWidth := 40
	waitsWidth := 15
	timeWidth := 15
	avgWidth := 15
	pctWidth := 10

	// Header (right-aligned for numbers)
	out.WriteString(d.colorize(fmt.Sprintf("%*s", instWidth, "I"), "bold"))
	out.WriteString(" ")
	out.WriteString(d.colorize(fmt.Sprintf("%-*s", eventWidth, "Event Name"), "bold"))
	out.WriteString(" ")
	out.WriteString(d.colorize(fmt.Sprintf("%*s", waitsWidth, "Total Waits"), "bold"))
	out.WriteString(" ")
	out.WriteString(d.colorize(fmt.Sprintf("%*s", timeWidth, "Time Wait(s)"), "bold"))
	out.WriteString(" ")
	out.WriteString(d.colorize(fmt.Sprintf("%*s", avgWidth, "Avg Wait(ms)"), "bold"))
	out.WriteString(" ")
	out.WriteString(d.colorize(fmt.Sprintf("%*s", pctWidth, "Pct%"), "bold"))
	out.WriteString("\n")
	out.WriteString(strings.Repeat("-", 120))
	out.WriteString("\n")

	// Data rows (right-aligned for numbers)
	for _, e := range events {
		avgWaitMs := e.AvgWaitTime * 1000
		out.WriteString(fmt.Sprintf("%*d", instWidth, e.InstID))
		out.WriteString(" ")
		out.WriteString(fmt.Sprintf("%-*s", eventWidth, d.truncate(e.EventName, eventWidth)))
		out.WriteString(" ")
		out.WriteString(fmt.Sprintf("%*s", waitsWidth, d.formatNumber(float64(e.TotalWaits))))
		out.WriteString(" ")
		out.WriteString(fmt.Sprintf("%*s", timeWidth, d.formatNumber(e.TimeWaited)))
		out.WriteString(" ")
		out.WriteString(fmt.Sprintf("%*s", avgWidth, d.formatNumber(avgWaitMs)))
		out.WriteString(" ")
		out.WriteString(fmt.Sprintf("%*.2f%%", pctWidth-1, e.Percentage))
		out.WriteString("\n")
	}

	out.WriteString("\n")
}

// renderSessionMetrics renders session metrics TOP N
func (d *Display) renderSessionMetrics(out *strings.Builder, metrics []models.SessionMetric) {
	out.WriteString(d.colorize(fmt.Sprintf("Session Metrics TOP %d (Sorted by %s)\n", d.cfg.SessionTopN, d.cfg.SessionSortBy), "yellow"))
	out.WriteString(strings.Repeat("-", 120))
	out.WriteString("\n")

	if len(metrics) == 0 {
		out.WriteString("Collecting baseline data...\n\n")
		return
	}

	// Column width
	instWidth := 2
	colWidth := 6
	sidTidWidth := 18
	usernameWidth := 12
	sqlIDWidth := 15
	programWidth := 20

	metricNames := config.SessionStatDisplayNames()
	nameMap := sysStatShortNames()

	// Header row: I, SID.Serial.TID, Username, SQL_ID, Program, Metrics
	out.WriteString(d.colorize(fmt.Sprintf("%*s", instWidth, "I"), "bold"))
	out.WriteString(" ")
	out.WriteString(d.colorize(fmt.Sprintf("%-*s", sidTidWidth, "SID.Serial.TID"), "bold"))
	out.WriteString(" ")
	out.WriteString(d.colorize(fmt.Sprintf("%-*s", usernameWidth, "Username"), "bold"))
	out.WriteString(" ")
	out.WriteString(d.colorize(fmt.Sprintf("%-*s", sqlIDWidth, "SQL_ID"), "bold"))
	out.WriteString(" ")
	out.WriteString(d.colorize(fmt.Sprintf("%-*s", programWidth, "Program"), "bold"))

	// Header row: Metric names
	for _, metricName := range metricNames {
		shortName := nameMap[metricName]
		out.WriteString(" ")
		out.WriteString(d.colorize(fmt.Sprintf("%*s", colWidth, shortName), "bold"))
	}
	out.WriteString("\n")
	out.WriteString(strings.Repeat("-", 120))
	out.WriteString("\n")

	// Data rows
	for _, m := range metrics {
		out.WriteString(fmt.Sprintf("%*d", instWidth, m.InstID))
		out.WriteString(" ")
		out.WriteString(fmt.Sprintf("%-*s", sidTidWidth, d.truncate(m.SidTid, sidTidWidth)))
		out.WriteString(" ")
		out.WriteString(fmt.Sprintf("%-*s", usernameWidth, d.truncate(m.Username, usernameWidth)))
		out.WriteString(" ")
		out.WriteString(fmt.Sprintf("%-*s", sqlIDWidth, d.truncate(m.SqlID, sqlIDWidth)))
		out.WriteString(" ")
		out.WriteString(fmt.Sprintf("%-*s", programWidth, d.truncate(m.Program, programWidth)))

		for _, metricName := range metricNames {
			out.WriteString(" ")
			value := m.Metrics[metricName]
			out.WriteString(fmt.Sprintf("%*s", colWidth, d.formatNumber(value)))
		}
		out.WriteString("\n")
	}

	out.WriteString("\n")
}

// renderSessionDetails renders session details
func (d *Display) renderSessionDetails(out *strings.Builder, details []models.SessionDetail) {
	out.WriteString(d.colorize(fmt.Sprintf("Active Sessions TOP %d (By Execution Time)\n", d.cfg.SessionDetailTopN), "yellow"))
	out.WriteString(strings.Repeat("-", 120))
	out.WriteString("\n")

	if len(details) == 0 {
		out.WriteString("No active sessions found\n\n")
		return
	}

	// Column widths
	instWidth := 2
	sidWidth := 30
	eventWidth := 20
	usernameWidth := 15
	sqlIDWidth := 20
	execTimeWidth := 10
	programWidth := 20
	clientWidth := 20

	// Header
	out.WriteString(d.colorize(fmt.Sprintf("%*s", instWidth, "I"), "bold"))
	out.WriteString(" ")
	out.WriteString(d.colorize(fmt.Sprintf("%-*s", sidWidth, "SID_TID"), "bold"))
	out.WriteString(" ")
	out.WriteString(d.colorize(fmt.Sprintf("%-*s", eventWidth, "Event"), "bold"))
	out.WriteString(" ")
	out.WriteString(d.colorize(fmt.Sprintf("%-*s", usernameWidth, "Username"), "bold"))
	out.WriteString(" ")
	out.WriteString(d.colorize(fmt.Sprintf("%-*s", sqlIDWidth, "SQL ID"), "bold"))
	out.WriteString(" ")
	out.WriteString(d.colorize(fmt.Sprintf("%-*s", execTimeWidth, "Exec Time"), "bold"))
	out.WriteString(" ")
	out.WriteString(d.colorize(fmt.Sprintf("%-*s", programWidth, "Program"), "bold"))
	out.WriteString(" ")
	out.WriteString(d.colorize(fmt.Sprintf("%-*s", clientWidth, "Client"), "bold"))
	out.WriteString("\n")
	out.WriteString(strings.Repeat("-", 120))
	out.WriteString("\n")

	// Data rows
	for _, s := range details {
		out.WriteString(fmt.Sprintf("%*d", instWidth, s.InstID))
		out.WriteString(" ")
		out.WriteString(fmt.Sprintf("%-*s", sidWidth, d.truncate(s.SidTid, sidWidth)))
		out.WriteString(" ")
		out.WriteString(fmt.Sprintf("%-*s", eventWidth, d.truncate(s.Event, eventWidth)))
		out.WriteString(" ")
		out.WriteString(fmt.Sprintf("%-*s", usernameWidth, d.truncate(s.Username, usernameWidth)))
		out.WriteString(" ")
		out.WriteString(fmt.Sprintf("%-*s", sqlIDWidth, d.truncate(s.SqlID, sqlIDWidth)))
		out.WriteString(" ")
		out.WriteString(fmt.Sprintf("%-*s", execTimeWidth, s.ExecTime))
		out.WriteString(" ")
		out.WriteString(fmt.Sprintf("%-*s", programWidth, d.truncate(s.Program, programWidth)))
		out.WriteString(" ")
		out.WriteString(fmt.Sprintf("%-*s", clientWidth, d.truncate(s.Client, clientWidth)))
		out.WriteString("\n")
	}

	out.WriteString("\n")
}

// renderFooter renders the footer section
func (d *Display) renderFooter(out *strings.Builder) {
	out.WriteString(strings.Repeat(d.colorize("-", "cyan"), 120))
	out.WriteString("\n")
	out.WriteString(d.colorize("Press Ctrl+C to exit", "cyan"))
	if d.cfg.OutputFile != "" {
		out.WriteString(d.colorize(fmt.Sprintf(" | Output: %s", d.cfg.OutputFile), "cyan"))
	}
	out.WriteString("\n")
}

// colorize adds ANSI color codes if color is enabled
func (d *Display) colorize(text, color string) string {
	if !d.cfg.ColorEnabled {
		return text
	}

	colors := map[string]string{
		"red":     "\033[31m",
		"green":   "\033[32m",
		"yellow":  "\033[33m",
		"blue":    "\033[34m",
		"magenta": "\033[35m",
		"cyan":    "\033[36m",
		"white":   "\033[37m",
		"bold":    "\033[1m",
		"reset":   "\033[0m",
	}

	if code, ok := colors[color]; ok {
		return code + text + colors["reset"]
	}

	return text
}

// center centers text in a given width
func (d *Display) center(text string, width int) string {
	if len(text) >= width {
		return text
	}
	padding := (width - len(text)) / 2
	return strings.Repeat(" ", padding) + text
}

// truncate truncates text to specified length
func (d *Display) truncate(text string, length int) string {
	if len(text) <= length {
		return text
	}
	return text[:length-3] + "..."
}

// formatNumber formats a number with K/M/G suffixes
func (d *Display) formatNumber(value float64) string {
	absValue := value
	if absValue < 0 {
		absValue = -absValue
	}

	var result string
	if absValue >= 1000000000 {
		result = fmt.Sprintf("%.1fG", value/1000000000)
	} else if absValue >= 1000000 {
		result = fmt.Sprintf("%.1fM", value/1000000)
	} else if absValue >= 1000 {
		result = fmt.Sprintf("%.1fK", value/1000)
	} else if absValue >= 1 {
		result = fmt.Sprintf("%.0f", value)
	} else if absValue > 0 {
		result = fmt.Sprintf("%.2f", value)
	} else {
		result = "0"
	}

	return result
}

// Close closes the display and any open files
func (d *Display) Close() error {
	if d.outputFile != nil {
		return d.outputFile.Close()
	}
	return nil
}

// InteractiveDisplay handles interactive terminal display
type InteractiveDisplay struct {
	*Display
	sessionList []models.SessionDetail
	conn        connector.Connector
}

// NewInteractiveDisplay creates a new interactive display
func NewInteractiveDisplay(d *Display, conn connector.Connector) *InteractiveDisplay {
	return &InteractiveDisplay{
		Display: d,
		conn:    conn,
	}
}

// RenderInteractive renders the snapshot with selection highlight
func (d *InteractiveDisplay) RenderInteractive(snapshot *models.Snapshot) {
	d.iteration++
	d.sessionList = snapshot.SessionDetails

	if d.cfg.DebugMode {
		selected := d.selectedSessionLabel()
		logger.Debug("[tui] RenderInteractive iteration #%d: sysStats=%d events=%d sessionMetrics=%d sessionDetails=%d selected=%s\n",
			d.iteration, len(snapshot.SysStats), len(snapshot.SystemEvents),
			len(snapshot.SessionMetrics), len(snapshot.SessionDetails), selected)
	}

	// Clear screen and move cursor to top-left
	fmt.Print("\033[2J\033[H")

	var output strings.Builder

	// Header
	d.renderHeader(&output, snapshot.Timestamp)

	// v$sysstat metrics
	d.renderSysStats(&output, snapshot.SysStats)

	// v$system_event TOP N
	d.renderSystemEvents(&output, snapshot.SystemEvents)

	// Session metrics TOP N
	d.renderSessionMetrics(&output, snapshot.SessionMetrics)

	// Session details
	d.renderSessionDetails(&output, snapshot.SessionDetails)

	// Footer with instructions
	d.renderInteractiveFooter(&output)

	// In raw terminal mode, we need to replace \n with \r\n for proper line breaks
	outputStr := strings.ReplaceAll(output.String(), "\n", "\r\n")

	// Print to terminal
	fmt.Print(outputStr)

	// Write to file if configured (use original output without \r)
	if d.outputFile != nil {
		d.outputFile.WriteString(output.String())
		d.outputFile.WriteString("\n" + strings.Repeat("=", 120) + "\n\n")
	}
}

// renderInteractiveFooter renders footer with keyboard instructions
func (d *InteractiveDisplay) renderInteractiveFooter(out *strings.Builder) {
	out.WriteString(strings.Repeat("-", 120))
	out.WriteString("\n")
	out.WriteString("Press: [a] Ad-hoc SQL | [s] Script/Cmd | [r] Read | [c] Copy | [f] Find | [h] Help | [q/ESC] Quit\n")
}

// ShowHelp displays help information
func (d *InteractiveDisplay) ShowHelp() string {
	var help strings.Builder
	help.WriteString("\n")
	help.WriteString(strings.Repeat("=", 80))
	help.WriteString("\n")
	help.WriteString("                    YTOP Interactive Mode Help\n")
	help.WriteString(strings.Repeat("=", 80))
	help.WriteString("\n\n")
	help.WriteString("Keyboard Commands:\n")
	help.WriteString("  ↑ / ↓       - Navigate up/down through active sessions\n")
	help.WriteString("  p / P       - View SQL plan for selected session's SQL ID\n")
	help.WriteString("  a / A       - Execute ad-hoc SQL statement\n")
	help.WriteString("  s / S       - Execute custom SQL script or OS command\n")
	help.WriteString("  r / R       - Read/view script content\n")
	help.WriteString("  c / C       - Copy script to server/local directory\n")
	help.WriteString("  f / F       - Find/search available scripts\n")
	help.WriteString("  h / H       - Show this help\n")
	help.WriteString("  q / Q / ESC - Quit ytop\n")
	help.WriteString("\n")
	help.WriteString("Copy Script (c key):\n")
	help.WriteString("  - Enter script filename and optional destination path\n")
	help.WriteString("  - Format: <scriptname> [destpath]\n")
	help.WriteString("  - Example: we.sql /tmp (copies to /tmp/we.sql)\n")
	help.WriteString("  - Example: we.sql (defaults to /tmp/we.sql)\n")
	help.WriteString("  - .sql files are searched in scripts/sql/ directory\n")
	help.WriteString("  - Other files are searched in scripts/os/ directory\n")
	help.WriteString("  - SSH mode: copies to remote server (-h specified)\n")
	help.WriteString("  - Local mode: copies to local filesystem (no -h)\n")
	help.WriteString("  - Verifies file after copy (checks existence and size)\n")
	help.WriteString("  - Press ESC to cancel input\n")
	help.WriteString("\n")
	help.WriteString("Find Scripts (f key):\n")
	help.WriteString("  - Enter regex pattern to search for scripts\n")
	help.WriteString("  - Use .* to list all available scripts\n")
	help.WriteString("  - Shows script type (sql/os), filename, and description\n")
	help.WriteString("  - Description is read from second line of script file\n")
	help.WriteString("  - Press ESC to cancel search\n")
	help.WriteString("\n")
	help.WriteString("Ad-hoc SQL (a key):\n")
	help.WriteString("  - Enter any SQL statement directly\n")
	help.WriteString("  - Executed immediately via yasql -c\n")
	help.WriteString("  - Special characters automatically escaped\n")
	help.WriteString("  - Press ESC to cancel input\n")
	help.WriteString("\n")
	help.WriteString("Execute Script/Command (s key):\n")
	help.WriteString("  - SQL scripts:  Enter filename ending with .sql (e.g., we.sql)\n")
	help.WriteString("                  Simple name: searches in embedded scripts/sql/\n")
	help.WriteString("                  Absolute path: /path/to/script.sql (Linux/Mac)\n")
	help.WriteString("                  Absolute path: D:\\path\\to\\script.sql (Windows)\n")
	help.WriteString("                  Relative path: ./script.sql or ../script.sql\n")
	help.WriteString("                  Scripts with & or && variables will prompt for input\n")
	help.WriteString("  - C sources:    memtest.c or memtest.c -i 1 -t 2 (compile on target, run with args)\n")
	help.WriteString("                  Embedded in scripts/os/ or path ./file.c\n")
	help.WriteString("  - Python:       probe.py or probe.py --verbose (run with python3 on target)\n")
	help.WriteString("                  Embedded in scripts/os/\n")
	help.WriteString("  - OS commands:  Enter any shell command (e.g., iostat 1 2)\n")
	help.WriteString("                  Or embedded OS scripts from scripts/os/\n")
	help.WriteString("  - Press ESC to cancel input\n")
	help.WriteString("\n")
	help.WriteString("Connection Modes:\n")
	help.WriteString("  - Local:    yasql executed locally\n")
	help.WriteString("  - SSH:      Commands executed on remote host via SSH\n")
	help.WriteString("              Scripts uploaded to /tmp/ for '/ as sysdba' auth\n")
	help.WriteString("\n")
	help.WriteString("Output:\n")
	help.WriteString("  - SQL plan output saved to: sql_<sqlid>.txt\n")
	help.WriteString("  - Command output saved to: output_<command>.txt\n")
	help.WriteString("  - Temporary files deleted unless --debug mode enabled\n")
	help.WriteString("\n")
	help.WriteString(strings.Repeat("=", 80))
	help.WriteString("\n")
	return help.String()
}

// GetSelectedSQLID returns the SQL ID of the currently selected session
func (d *InteractiveDisplay) GetSelectedSQLID() string {
	if len(d.sessionList) > 0 {
		sqlID := d.sessionList[0].SqlID
		// Remove command prefix (e.g., "SEL.abc123" -> "abc123")
		parts := strings.Split(sqlID, ".")
		if len(parts) > 1 {
			return parts[1]
		}
		return sqlID
	}
	return ""
}

func (d *InteractiveDisplay) selectedSessionLabel() string {
	if len(d.sessionList) == 0 {
		return "(none)"
	}
	s := d.sessionList[0]
	if s.SidTid != "" {
		return s.SidTid
	}
	return s.SqlID
}

// ExecuteSQLPlan executes the SQL plan script for the selected SQL ID
func (d *InteractiveDisplay) ExecuteSQLPlan(ctx context.Context) error {
	sqlID := d.GetSelectedSQLID()
	if sqlID == "" {
		return fmt.Errorf("no SQL ID available for selected session")
	}

	// Get SQL script
	script, err := scripts.GetSQLScript("sql.sql")
	if err != nil {
		return fmt.Errorf("failed to load SQL script: %w", err)
	}

	// Replace &&sqlid with actual SQL ID
	script = scripts.ReplaceSQLID(script, sqlID)

	// Execute SQL script
	output, err := d.executeSQLScript(ctx, script)
	if err != nil {
		return fmt.Errorf("failed to execute SQL script: %w", err)
	}

	// Write output to file
	if err := scripts.WriteSQLOutput(sqlID, output); err != nil {
		return fmt.Errorf("failed to write SQL output: %w", err)
	}

	// Show success message
	fmt.Printf("\n\nSQL plan saved to: sql_%s.txt\nPress any key to continue...", sqlID)

	// Wait for key press
	exec.Command("bash", "-c", "read -n 1").Run()

	return nil
}

// executeSQLScript executes a SQL script via connector
func (d *InteractiveDisplay) executeSQLScript(ctx context.Context, script string) (string, error) {
	// Split script into individual statements
	statements := strings.Split(script, ";")

	var output strings.Builder

	for _, stmt := range statements {
		stmt = strings.TrimSpace(stmt)
		if stmt == "" {
			continue
		}

		// Skip comments and prompts
		if strings.HasPrefix(stmt, "--") || strings.HasPrefix(stmt, "prompt") ||
			strings.HasPrefix(stmt, "set ") {
			continue
		}

		// Execute statement
		rows, err := d.conn.ExecuteQuery(ctx, stmt)
		if err != nil {
			output.WriteString(fmt.Sprintf("Error executing statement: %v\n", err))
			continue
		}

		// Format output
		for _, row := range rows {
			output.WriteString(strings.Join(row, " | "))
			output.WriteString("\n")
		}
		output.WriteString("\n")
	}

	return output.String(), nil
}
