package platform

import (
	"strings"
	"testing"
)

func TestParseWindowsMssqlRegistryProbeOutput(t *testing.T) {
	out := "noise\r\nYTOP_SQLCMD=C:\\Program Files\\Microsoft SQL Server\\Client SDK\\ODBC\\130\\Tools\\Binn\\SQLCMD.EXE\r\nYTOP_MSSQL_PORT=1433\r\n"
	path, port, err := ParseWindowsMssqlRegistryProbeOutput(out)
	if err != nil {
		t.Fatal(err)
	}
	if path == "" || port != "1433" {
		t.Fatalf("path=%q port=%q", path, port)
	}
}

func TestParseWindowsMssqlRegistryProbeOutput_missingPath(t *testing.T) {
	_, _, err := ParseWindowsMssqlRegistryProbeOutput("YTOP_MSSQL_PORT=1433\n")
	if err == nil {
		t.Fatal("expected error for missing sqlcmd path")
	}
}

func TestParseWindowsMssqlRegistryProbeOutput_clixmlNoise(t *testing.T) {
	out := "#< CLIXML\r\nYTOP_SQLCMD=C:\\Tools\\Binn\\sqlcmd.exe\r\nYTOP_MSSQL_PORT=1433\r\n<Objs Version=\"1.1.0.1\" />\r\n"
	path, port, err := ParseWindowsMssqlRegistryProbeOutput(out)
	if err != nil {
		t.Fatal(err)
	}
	if path == "" || port != "1433" {
		t.Fatalf("path=%q port=%q", path, port)
	}
}

func TestBuildWindowsMssqlRegistryProbeCmd(t *testing.T) {
	got := BuildWindowsMssqlRegistryProbeCmd()
	if got == "" || !strings.Contains(got, "powershell") || !strings.Contains(got, "-EncodedCommand") {
		t.Fatalf("BuildWindowsMssqlRegistryProbeCmd = %q", got)
	}
}
