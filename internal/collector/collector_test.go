package collector

import "testing"

func TestParseSessionDetailRow_weSqlColumnOrder(t *testing.T) {
	header := []string{"SID_TID", "EVENT", "USERNAME", "SQL_ID", "EXEC_MS", "PROGRAM", "CLIENT", "INST_ID"}
	row := []string{
		"1.36.116259.10114",
		"CPU",
		"TPCC",
		"SEL.abc",
		"500",
		"YashanDB Server Enterprise",
		"10.0.0.1.54321",
		"1",
	}
	d, ok := parseSessionDetailRow(header, row)
	if !ok {
		t.Fatal("parse failed")
	}
	if d.SidTid != "1.36.116259.10114" {
		t.Fatalf("SidTid = %q", d.SidTid)
	}
	if d.Program != "YashanDB Server Enterprise" {
		t.Fatalf("Program = %q", d.Program)
	}
	if d.SqlID != "SEL.abc" {
		t.Fatalf("SqlID = %q", d.SqlID)
	}
	if d.ExecTime != "500MS" {
		t.Fatalf("ExecTime = %q", d.ExecTime)
	}
}

func TestParseSessionDetailRow_legacyColumnOrderByHeader(t *testing.T) {
	// Old SQL had program before sql_id; header mapping must still work.
	header := []string{"SID_TID", "EVENT", "USERNAME", "PROGRAM", "SQL_ID", "EXEC_MS", "CLIENT", "INST_ID"}
	row := []string{
		"1.2.3.4",
		"WAIT",
		"SYS",
		"yasql",
		"INS.abc",
		"100",
		"127.0.0.1.22",
		"1",
	}
	d, ok := parseSessionDetailRow(header, row)
	if !ok {
		t.Fatal("parse failed")
	}
	if d.Program != "yasql" || d.SqlID != "INS.abc" {
		t.Fatalf("Program=%q SqlID=%q", d.Program, d.SqlID)
	}
}
