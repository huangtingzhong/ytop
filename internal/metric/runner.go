package metric

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/yihan/ytop/internal/config"
	"github.com/yihan/ytop/internal/connector"
	"github.com/yihan/ytop/internal/scripts"
)

// Runner orchestrates metric collection and display
type Runner struct {
	cfg     *config.Config
	conn    connector.Connector
	sqlFile string
}

// NewRunner creates a new metric runner
func NewRunner(cfg *config.Config, conn connector.Connector, sqlFile string) *Runner {
	return &Runner{
		cfg:     cfg,
		conn:    conn,
		sqlFile: sqlFile,
	}
}

// Run starts the metric collection loop
func (r *Runner) Run(ctx context.Context) error {
	// Create collector
	collector := NewCollector(r.conn, r.sqlFile)

	// First collection to detect columns
	firstSnapshot, err := collector.Collect(ctx)
	if err != nil {
		return fmt.Errorf("failed to collect initial snapshot: %w", err)
	}
	if firstSnapshot == nil {
		return fmt.Errorf("no data returned from query")
	}

	// Get column info
	columnInfo := collector.GetColumnInfo()
	if columnInfo == nil {
		return fmt.Errorf("failed to detect column info")
	}

	// Create calculator with column info
	calc := NewCalculator(columnInfo)

	// Create display
	disp := NewDisplay(r.sqlFile)

	// Setup signal handling
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	// Use interval from config (minimum 1 second)
	interval := time.Duration(r.cfg.Interval) * time.Second
	if interval <= 0 {
		interval = time.Second
	}

	// Main loop
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	iteration := 0
	maxIterations := r.cfg.Count

	// Process first snapshot (no delta yet)
	calc.Calculate(firstSnapshot)

	for {
		select {
		case <-ctx.Done():
			return nil
		case <-sigChan:
			return nil
		case <-ticker.C:
			// Collect snapshot
			snapshot, err := collector.Collect(ctx)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error collecting snapshot: %v\n", err)
				continue
			}

			// Calculate result
			result := calc.Calculate(snapshot)
			if result == nil {
				continue
			}

			iteration++

			// Render and display
			output := disp.Render(result, iteration, maxIterations)
			fmt.Print(output)
			fmt.Println()

			// Check if we've reached max iterations
			if maxIterations > 0 && iteration >= maxIterations {
				return nil
			}
		}
	}
}

// Display formats and renders metric results
type Display struct {
	sqlFile string
}

// NewDisplay creates a new display
func NewDisplay(sqlFile string) *Display {
	return &Display{
		sqlFile: sqlFile,
	}
}

// Render formats the result as a table string
func (d *Display) Render(result *Result, iteration, maxIterations int) string {
	if result == nil {
		return ""
	}

	var sb strings.Builder

	// Build all columns to display (already includes group + numeric + string columns)
	displayCols := result.Columns

	// Calculate column widths
	widths := make(map[string]int)
	for _, col := range displayCols {
		widths[col] = len(col)
	}

	// Check data widths
	for _, gd := range result.PerGroup {
		for _, col := range displayCols {
			var valStr string
			if col == result.GroupKey {
				valStr = gd.GroupKey
			} else if val, ok := gd.NumericVals[col]; ok {
				valStr = FormatFloat(val)
			} else if sval, ok := gd.StringVals[col]; ok {
				valStr = sval
			}
			if len(valStr) > widths[col] {
				widths[col] = len(valStr)
			}
		}
	}

	// Check AVG row widths (only for numeric columns)
	for _, col := range displayCols {
		if col != result.GroupKey {
			if val, ok := result.Aggregated[col]; ok {
				valStr := FormatFloat(val)
				if len(valStr) > widths[col] {
					widths[col] = len(valStr)
				}
			}
		}
	}

	// Ensure minimum width for group column
	if result.GroupKey != "" && widths[result.GroupKey] < 5 {
		widths[result.GroupKey] = 5
	}

	// Print header
	headerParts := make([]string, 0, len(displayCols))
	for _, col := range displayCols {
		headerParts = append(headerParts, fmt.Sprintf("%*s", widths[col], col))
	}
	sb.WriteString(strings.Join(headerParts, " | "))
	sb.WriteString("\n")

	// Print separator
	sepParts := make([]string, 0, len(displayCols))
	for _, col := range displayCols {
		sepParts = append(sepParts, strings.Repeat("-", widths[col]))
	}
	sb.WriteString(strings.Join(sepParts, "-|-"))
	sb.WriteString("\n")

	// Print data rows
	for _, gd := range result.PerGroup {
		rowParts := make([]string, 0, len(displayCols))
		for _, col := range displayCols {
			var valStr string
			if col == result.GroupKey {
				valStr = fmt.Sprintf("%*s", widths[col], gd.GroupKey)
			} else if val, ok := gd.NumericVals[col]; ok {
				valStr = fmt.Sprintf("%*s", widths[col], FormatFloat(val))
			} else if sval, ok := gd.StringVals[col]; ok {
				valStr = fmt.Sprintf("%*s", widths[col], sval)
			}
			rowParts = append(rowParts, valStr)
		}
		sb.WriteString(strings.Join(rowParts, " | "))
		sb.WriteString("\n")
	}

	// Print separator before AVG (only if multiple groups)
	if len(result.PerGroup) > 1 {
		sb.WriteString(strings.Join(sepParts, "-|-"))
		sb.WriteString("\n")

		// Print AVG row
		avgParts := make([]string, 0, len(displayCols))
		for _, col := range displayCols {
			var valStr string
			if col == result.GroupKey {
				valStr = fmt.Sprintf("%*s", widths[col], "AVG")
			} else if val, ok := result.Aggregated[col]; ok {
				valStr = fmt.Sprintf("%*s", widths[col], FormatFloat(val))
			} else {
				valStr = fmt.Sprintf("%*s", widths[col], "-")
			}
			avgParts = append(avgParts, valStr)
		}
		sb.WriteString(strings.Join(avgParts, " | "))
		sb.WriteString("\n")
	}

	return sb.String()
}

// Snapshot represents a single data collection snapshot
type Snapshot struct {
	Timestamp time.Time
	Columns   []string
	Rows      []map[string]interface{}
}

// ColumnInfo holds metadata about detected columns
type ColumnInfo struct {
	GroupColumn   string   // Column used for grouping (e.g., "INST_ID")
	ValueColumns  []string // Columns that contain numeric values (for delta calculation)
	StringColumns []string // Columns that contain string/time values (display as-is)
}

// Collector collects metrics from SQL queries
type Collector struct {
	conn       connector.Connector
	sqlFile    string
	sql        string
	columnInfo *ColumnInfo
}

// NewCollector creates a new metric collector
func NewCollector(conn connector.Connector, sqlFile string) *Collector {
	return &Collector{
		conn:    conn,
		sqlFile: sqlFile,
	}
}

// Collect executes the SQL and returns a snapshot
func (c *Collector) Collect(ctx context.Context) (*Snapshot, error) {
	// Read SQL from file (only once)
	if c.sql == "" {
		sql, err := scripts.GetSQLScript(c.sqlFile)
		if err != nil {
			return nil, err
		}
		c.sql = sql
	}

	// Execute query with header
	header, rows, err := c.conn.ExecuteQueryWithHeader(ctx, c.sql)
	if err != nil {
		return nil, err
	}

	if len(rows) == 0 || len(header) == 0 {
		return nil, nil
	}

	// Detect column info on first collection
	if c.columnInfo == nil {
		c.columnInfo = detectColumnInfo(header, rows)
	}

	// Build column names list
	var columnNames []string
	if c.columnInfo.GroupColumn != "" {
		columnNames = append(columnNames, c.columnInfo.GroupColumn)
	}
	columnNames = append(columnNames, c.columnInfo.ValueColumns...)

	// Parse data rows
	parsedRows := make([]map[string]interface{}, 0, len(rows))
	for _, row := range rows {
		// Map header -> value
		rowMap := make(map[string]interface{})
		for i, col := range header {
			if i < len(row) {
				rowMap[strings.ToUpper(col)] = row[i]
			}
		}
		parsedRows = append(parsedRows, rowMap)
	}

	return &Snapshot{
		Timestamp: time.Now(),
		Columns:   header,
		Rows:      parsedRows,
	}, nil
}

// GetColumnInfo returns the detected column information
func (c *Collector) GetColumnInfo() *ColumnInfo {
	return c.columnInfo
}

// detectColumnInfo analyzes the result set to determine grouping and value columns
func detectColumnInfo(header []string, sampleRows [][]string) *ColumnInfo {
	info := &ColumnInfo{
		ValueColumns:  make([]string, 0),
		StringColumns: make([]string, 0),
	}

	// Normalize header to uppercase
	upperHeader := make([]string, len(header))
	for i, col := range header {
		upperHeader[i] = strings.ToUpper(col)
	}

	// Find group column (look for INST_ID)
	for _, col := range upperHeader {
		if col == "INST_ID" {
			info.GroupColumn = col
			break
		}
	}

	// Determine value columns and string columns
	for colIdx, colName := range upperHeader {
		if colName == info.GroupColumn {
			continue
		}

		// Check if this column contains numeric values
		if isNumericColumn(colIdx, sampleRows) {
			info.ValueColumns = append(info.ValueColumns, colName)
		} else {
			info.StringColumns = append(info.StringColumns, colName)
		}
	}

	return info
}

// isNumericColumn checks if a column contains numeric values
func isNumericColumn(colIdx int, rows [][]string) bool {
	// Check first few data rows
	numericCount := 0
	totalCount := 0

	for i := 0; i < len(rows) && i < 5; i++ {
		if len(rows[i]) <= colIdx {
			continue
		}
		totalCount++
		val := rows[i][colIdx]
		if _, err := strconv.ParseFloat(strings.TrimSpace(val), 64); err == nil {
			numericCount++
		}
	}

	// If more than 80% of values are numeric, treat as numeric column
	return totalCount > 0 && float64(numericCount)/float64(totalCount) >= 0.8
}

// Calculator calculates deltas and per-second rates
type Calculator struct {
	previous   *Snapshot
	columnInfo *ColumnInfo
}

// NewCalculator creates a new calculator
func NewCalculator(columnInfo *ColumnInfo) *Calculator {
	return &Calculator{
		columnInfo: columnInfo,
	}
}

// Result represents the calculated metric result
type Result struct {
	SQLFile     string
	IntervalSec float64
	Columns     []string // All display columns (group + value + string)
	GroupKey    string
	// PerGroup contains delta/per-second values for each group
	PerGroup []GroupData
	// Aggregated contains average values across all groups (only for numeric columns)
	Aggregated map[string]float64
}

// GroupData represents metrics for a single group
type GroupData struct {
	GroupKey    string             // e.g., "1", "2" or "ALL"
	NumericVals map[string]float64 // column -> per_sec value (for numeric columns)
	StringVals  map[string]string  // column -> current value (for string/time columns)
}

// Calculate computes deltas and per-second rates
func (c *Calculator) Calculate(current *Snapshot) *Result {
	if c.previous == nil {
		c.previous = current
		return nil
	}

	// Calculate actual time interval
	intervalSec := current.Timestamp.Sub(c.previous.Timestamp).Seconds()
	if intervalSec <= 0 {
		intervalSec = 1
	}

	// Build all columns list
	var allColumns []string
	if c.columnInfo.GroupColumn != "" {
		allColumns = append(allColumns, c.columnInfo.GroupColumn)
	}
	allColumns = append(allColumns, c.columnInfo.ValueColumns...)
	allColumns = append(allColumns, c.columnInfo.StringColumns...)

	result := &Result{
		SQLFile:     "",
		IntervalSec: intervalSec,
		Columns:     allColumns,
		GroupKey:    c.columnInfo.GroupColumn,
		PerGroup:    make([]GroupData, 0),
		Aggregated:  make(map[string]float64),
	}

	// Group current and previous rows by group key
	prevMap := c.groupByColumn(c.previous)
	currMap := c.groupByColumn(current)

	// Calculate per-group deltas
	for groupKey, currRow := range currMap {
		prevRow, exists := prevMap[groupKey]
		if !exists {
			continue
		}

		// Calculate numeric deltas
		numericVals := make(map[string]float64)
		for _, col := range c.columnInfo.ValueColumns {
			currVal := toFloat(currRow[col])
			prevVal := toFloat(prevRow[col])
			delta := currVal - prevVal
			numericVals[col] = delta / intervalSec
		}

		// Get current string values (no delta, just current value)
		stringVals := make(map[string]string)
		for _, col := range c.columnInfo.StringColumns {
			stringVals[col] = toString(currRow[col])
		}

		result.PerGroup = append(result.PerGroup, GroupData{
			GroupKey:    groupKey,
			NumericVals: numericVals,
			StringVals:  stringVals,
		})
	}

	// Calculate aggregated averages (only for numeric columns)
	for _, col := range c.columnInfo.ValueColumns {
		var sum float64
		count := 0
		for _, gd := range result.PerGroup {
			sum += gd.NumericVals[col]
			count++
		}
		if count > 0 {
			result.Aggregated[col] = sum / float64(count)
		}
	}

	c.previous = current
	return result
}

// groupByColumn groups rows by the group column
func (c *Calculator) groupByColumn(snapshot *Snapshot) map[string]map[string]interface{} {
	result := make(map[string]map[string]interface{})
	for _, row := range snapshot.Rows {
		key := fmt.Sprintf("%v", row[c.columnInfo.GroupColumn])
		result[key] = row
	}
	return result
}

// toFloat converts interface{} to float64
func toFloat(v interface{}) float64 {
	switch val := v.(type) {
	case float64:
		return val
	case float32:
		return float64(val)
	case int:
		return float64(val)
	case int64:
		return float64(val)
	case int32:
		return float64(val)
	case string:
		f, err := strconv.ParseFloat(strings.TrimSpace(val), 64)
		if err == nil {
			return f
		}
	}
	return 0
}

// toString converts interface{} to string
func toString(v interface{}) string {
	if v == nil {
		return ""
	}
	switch val := v.(type) {
	case string:
		return val
	default:
		return fmt.Sprintf("%v", val)
	}
}

// FormatFloat formats a float with 2 decimal places
func FormatFloat(v float64) string {
	return fmt.Sprintf("%.2f", v)
}
