package connector

import "strings"

// WrapSQLSuppressScriptEcho prepends session commands so Oracle-style CLIs do not print
// the executed SQL/script before the result grid: sqlplus, disql (oracle / dameng).
// YashanDB yasql does not support these SET options (YASQL-00008); mysql/psql/yashandb leave SQL unchanged.
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
