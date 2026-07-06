package connector

import (
	"bufio"
	"fmt"
	"regexp"
	"strings"
)

// yashanErrorPattern matches YashanDB error codes like YAS-04209
var yashanErrorPattern = regexp.MustCompile(`YAS-\d{5}`)

// stripSttyWarnings removes stty warnings from shell profile output
func stripSttyWarnings(output string) string {
	var lines []string
	for _, line := range strings.Split(output, "\n") {
		if strings.HasPrefix(line, "stty:") {
			continue
		}
		lines = append(lines, line)
	}
	return strings.Join(lines, "\n")
}

// checkYashanError checks if output contains YashanDB error codes
func checkYashanError(output string) error {
	if yashanErrorPattern.MatchString(output) {
		// Extract error lines
		var errorLines []string
		scanner := bufio.NewScanner(strings.NewReader(output))
		for scanner.Scan() {
			line := scanner.Text()
			if yashanErrorPattern.MatchString(line) {
				errorLines = append(errorLines, line)
			}
		}
		if len(errorLines) > 0 {
			return fmt.Errorf("YashanDB error detected:\n%s", strings.Join(errorLines, "\n"))
		}
	}
	return nil
}

// parseYasqlOutput parses yasql output into rows
// YashanDB yasql outputs data in fixed-width columns with headers
func parseYasqlOutput(output string) ([][]string, error) {
	output = stripSttyWarnings(output)
	// Check for YashanDB errors first
	if err := checkYashanError(output); err != nil {
		return nil, err
	}

	var rows [][]string
	scanner := bufio.NewScanner(strings.NewReader(output))

	var separatorLine string
	var dataStarted bool
	var pastResultFooter bool

	for scanner.Scan() {
		line := scanner.Text()

		// Skip empty lines
		if strings.TrimSpace(line) == "" {
			continue
		}

		// Skip "X rows fetched" lines; ignore everything after (disconnect banner).
		if strings.Contains(line, "rows fetched") || strings.Contains(line, "row fetched") {
			pastResultFooter = true
			continue
		}
		if pastResultFooter {
			continue
		}

		// Skip "Disconnected from" lines
		if strings.Contains(line, "Disconnected from") {
			continue
		}

		// Detect separator line (dashes)
		if strings.Contains(line, "---") && !dataStarted {
			separatorLine = line
			dataStarted = true
			continue
		}

		// If we haven't found separator yet, skip (likely header)
		if !dataStarted {
			continue
		}

		// Parse data line using separator positions
		if separatorLine != "" {
			fields := parseFixedWidthLine(line, separatorLine)
			if len(fields) > 0 {
				rows = append(rows, fields)
			}
		} else {
			// Fallback to whitespace splitting
			fields := strings.Fields(line)
			if len(fields) > 0 {
				rows = append(rows, fields)
			}
		}
	}

	return rows, nil
}

// parseFixedWidthLine parses a line based on separator positions.
// Empty columns are preserved so downstream row indices stay aligned with headers.
func parseFixedWidthLine(line, separator string) []string {
	ranges := fixedWidthColumnRanges(separator)
	fields := make([]string, 0, len(ranges))
	for _, r := range ranges {
		start, end := r[0], r[1]
		if start >= len(line) {
			fields = append(fields, "")
			continue
		}
		if end > len(line) {
			end = len(line)
		}
		fields = append(fields, strings.TrimSpace(line[start:end]))
	}
	return fields
}

// fixedWidthColumnRanges returns [start,end) spans for each dash group in a yasql separator line.
func fixedWidthColumnRanges(separator string) [][2]int {
	var ranges [][2]int
	inDash := false
	start := 0
	for i, ch := range separator {
		if ch == '-' {
			if !inDash {
				start = i
				inDash = true
			}
			continue
		}
		if inDash {
			ranges = append(ranges, [2]int{start, i})
			inDash = false
		}
	}
	if inDash {
		ranges = append(ranges, [2]int{start, len(separator)})
	}
	return ranges
}

// ParseYasqlOutputWithHeader parses yasql output and returns header + data rows
// This is similar to parseYasqlOutput but also returns the header row
func ParseYasqlOutputWithHeader(output string) (header []string, rows [][]string, err error) {
	output = stripSttyWarnings(output)
	// Check for YashanDB errors first
	if err := checkYashanError(output); err != nil {
		return nil, nil, err
	}

	scanner := bufio.NewScanner(strings.NewReader(output))

	var separatorLine string
	var headerFound bool
	var dataStarted bool
	var pastResultFooter bool

	for scanner.Scan() {
		line := scanner.Text()

		// Skip empty lines
		if strings.TrimSpace(line) == "" {
			continue
		}

		// Skip "X rows fetched" lines; ignore everything after (disconnect banner).
		if strings.Contains(line, "rows fetched") || strings.Contains(line, "row fetched") {
			pastResultFooter = true
			continue
		}
		if pastResultFooter {
			continue
		}

		// Skip "Disconnected from" lines
		if strings.Contains(line, "Disconnected from") {
			continue
		}

		// Detect separator line (dashes)
		if strings.Contains(line, "---") && !dataStarted {
			separatorLine = line
			dataStarted = true
			continue
		}

		// If we haven't found separator yet, this is header
		if !dataStarted {
			headerLine := strings.Fields(line)
			if len(headerLine) > 0 {
				header = headerLine
				headerFound = true
			}
			continue
		}

		// Parse data line using separator positions
		if separatorLine != "" {
			fields := parseFixedWidthLine(line, separatorLine)
			if len(fields) > 0 {
				rows = append(rows, fields)
			}
		} else {
			// Fallback to whitespace splitting
			fields := strings.Fields(line)
			if len(fields) > 0 {
				rows = append(rows, fields)
			}
		}
	}

	// If no header found but we have data, generate default column names
	if !headerFound && len(rows) > 0 {
		header = make([]string, len(rows[0]))
		for i := range header {
			header[i] = fmt.Sprintf("COL%d", i+1)
		}
	}

	return header, rows, nil
}

// WrapSQLSuppressScriptEcho prepends session commands so Oracle-style CLIs do not print
// the executed SQL/script before the result grid: sqlplus, disql (oracle / dameng).
// YashanDB yasql does not support SET ECHO (YASQL-00008); mysql/psql/yashandb leave SQL unchanged.
func WrapSQLSuppressScriptEcho(dbType string, sql string) string {
	sql = strings.TrimSpace(sql)
	if sql == "" {
		return sql
	}
	switch dbType {
	case "mysql", "postgresql", "yashandb", "mssql":
		return sql
	default:
		return "SET ECHO OFF\nSET VERIFY OFF\n" + sql
	}
}

// EnsureSQLStatementTerminator ensures non-empty SQL ends with a statement terminator.
// For mysql/postgresql, appends ';' when missing. For Oracle-style CLIs (yasql/sqlplus/disql),
// a line containing only '/' executes the buffer like ';'; appending ';' after such a script
// would duplicate termination — so when the last non-empty line is '/', nothing is appended.
// Call this before appending "\nexit\n".
func EnsureSQLStatementTerminator(sql string, dbType string) string {
	sql = strings.TrimRight(strings.TrimSpace(sql), "\r")
	if sql == "" {
		return sql
	}
	if strings.HasSuffix(sql, ";") {
		return sql
	}
	switch dbType {
	case "mysql", "postgresql":
		return sql + ";"
	case "mssql":
		return sql
	default:
		if endsWithSlashOnlyLine(sql) {
			return sql
		}
		return sql + ";"
	}
}

// endsWithSlashOnlyLine is true when the last non-empty line is exactly '/' (SQL*Plus / yasql run delimiter).
func endsWithSlashOnlyLine(sql string) bool {
	lines := strings.Split(strings.TrimRight(sql, "\n\r"), "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		line := strings.TrimSpace(strings.TrimRight(lines[i], "\r"))
		if line == "" {
			continue
		}
		return line == "/"
	}
	return false
}
