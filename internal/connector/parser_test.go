package connector

import (
	"strings"
	"testing"
)

func buildTestSeparator(widths []int) string {
	parts := make([]string, len(widths))
	for i, w := range widths {
		parts[i] = strings.Repeat("-", w)
	}
	return strings.Join(parts, " ")
}

func buildTestLine(cols []string, widths []int) string {
	parts := make([]string, len(cols))
	for i, col := range cols {
		parts[i] = padRight(col, widths[i])
	}
	return strings.Join(parts, " ")
}

func padRight(s string, width int) string {
	if len(s) >= width {
		return s[:width]
	}
	return s + strings.Repeat(" ", width-len(s))
}

func TestParseFixedWidthLine_preservesEmptyColumns(t *testing.T) {
	widths := []int{20, 20, 15, 20, 10, 30, 20, 7}
	cols := []string{
		"1.36.116259.10114",
		"",
		"TPCC",
		"SEL.5q09a3h33cysu",
		"123",
		"YashanDB JDBC Driver",
		"10.0.0.1.54321",
		"1",
	}
	sep := buildTestSeparator(widths)
	line := buildTestLine(cols, widths)

	got := parseFixedWidthLine(line, sep)
	if len(got) != 8 {
		t.Fatalf("parseFixedWidthLine fields = %d, want 8: %v", len(got), got)
	}
	if got[1] != "" {
		t.Fatalf("empty event = %q, want empty", got[1])
	}
	if got[3] != "SEL.5q09a3h33cysu" {
		t.Fatalf("sql_id = %q", got[3])
	}
	if got[5] != "YashanDB JDBC Driver" {
		t.Fatalf("program = %q", got[5])
	}
	if got[4] != "123" {
		t.Fatalf("exec_ms = %q", got[4])
	}
	if got[7] != "1" {
		t.Fatalf("inst_id = %q", got[7])
	}
}

func TestParseYasqlOutput_skipsDisconnectBanner(t *testing.T) {
	widths := []int{20, 20, 15, 20, 10, 30, 20, 7}
	cols := []string{
		"1.36.2102.154772",
		"CPU",
		"SYS",
		"SEL.abc",
		"500",
		"yasql",
		"127.0.0.1.22",
		"1",
	}
	sep := buildTestSeparator(widths)
	line := buildTestLine(cols, widths)
	out := "SID_TID              EVENT                USERNAME        SQL_ID               EXEC_MS    PROGRAM                        CLIENT               INST_ID\n" +
		sep + "\n" +
		line + "\n\n1 row fetched.\n\nDisconnected from:\nYashanDB Server Enterprise Edition Release 23.5.2.101 aarch64 - Linux\n"

	_, rows, err := ParseYasqlOutputWithHeader(out)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 {
		t.Fatalf("rows = %d, want 1 (disconnect banner must not be parsed): %v", len(rows), rows)
	}
	if rows[0][0] != "1.36.2102.154772" || rows[0][5] != "yasql" {
		t.Fatalf("row = %v", rows[0])
	}
}

func TestParseYasqlOutput_sessionDetailsLayout(t *testing.T) {
	// Column order aligned with we.sql: sid_tid, event, username, sql_id, exec_ms, program, client, inst_id
	widths := []int{20, 20, 15, 20, 10, 30, 20, 7}
	cols := []string{
		"1.36.116259.10114",
		"CPU",
		"TPCC",
		"SEL.5q09a3h33cysu",
		"123",
		"YashanDB JDBC Driver",
		"10.0.0.1.54321",
		"1",
	}
	sep := buildTestSeparator(widths)
	line := buildTestLine(cols, widths)
	out := "SID_TID              EVENT                USERNAME        SQL_ID               EXEC_MS    PROGRAM                        CLIENT               INST_ID\n" +
		sep + "\n" +
		line + "\n\n1 rows fetched\n"

	rows, err := parseYasqlOutput(out)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || len(rows[0]) != 8 {
		t.Fatalf("rows = %v", rows)
	}
	if rows[0][0] != "1.36.116259.10114" || rows[0][5] != "YashanDB JDBC Driver" {
		t.Fatalf("we.sql column order mismatch: %v", rows[0])
	}
}
