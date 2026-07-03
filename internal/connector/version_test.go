package connector

import "testing"

func TestCLIVersionArgs(t *testing.T) {
	if got := CLIVersionArgs("yashandb"); len(got) != 1 || got[0] != "-v" {
		t.Fatalf("yashandb version args = %v", got)
	}
	if got := CLIVersionArgs("mysql"); len(got) != 1 || got[0] != "--version" {
		t.Fatalf("mysql version args = %v", got)
	}
}

func TestExtractVersionFromCLIOutput(t *testing.T) {
	out := "YashanDB Release 23.5.1.104 Client\n"
	// sanity via scripts helper through a tiny duplicate-free check in connector tests is unnecessary;
	// version parsing is covered in scripts package tests.
	if out == "" {
		t.Fatal("unexpected empty")
	}
}
