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
	widths := []int{20, 20, 15, 30, 20, 10, 20, 7}
	cols := []string{
		"1.36.116259.10114",
		"",
		"TPCC",
		"YashanDB JDBC Driver",
		"SEL.5q09a3h33cysu",
		"123",
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
	if got[5] != "123" {
		t.Fatalf("exec_ms = %q", got[5])
	}
	if got[7] != "1" {
		t.Fatalf("inst_id = %q", got[7])
	}
}

func TestParseYasqlOutput_sessionDetailsLayout(t *testing.T) {
	widths := []int{20, 20, 15, 30, 20, 10, 20, 7}
	cols := []string{
		"1.36.116259.10114",
		"",
		"TPCC",
		"YashanDB JDBC Driver",
		"SEL.5q09a3h33cysu",
		"123",
		"10.0.0.1.54321",
		"1",
	}
	sep := buildTestSeparator(widths)
	line := buildTestLine(cols, widths)
	out := "SID_TID              EVENT                USERNAME        PROGRAM                        SQL_ID               EXEC_MS    CLIENT               INST_ID\n" +
		sep + "\n" +
		line + "\n\n1 rows fetched\n"

	rows, err := parseYasqlOutput(out)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 {
		t.Fatalf("rows = %d, want 1", len(rows))
	}
	if len(rows[0]) != 8 {
		t.Fatalf("columns = %d, want 8: %v", len(rows[0]), rows[0])
	}
}
