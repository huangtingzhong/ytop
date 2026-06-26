package executor

import (
	"strings"
	"testing"

	"github.com/yihan/ytop/internal/config"
)

func testExecutor(dbType string) *Executor {
	cfg := config.DefaultConfig()
	cfg.DBType = dbType
	return NewExecutor(cfg, nil)
}

func promptInfo(script, variable string) variablePromptInfo {
	vars := collectScriptVariables(script)
	return resolveVariablePromptInfos(script, vars)[variable]
}

func TestFindVariablePromptInfoSkipsCommentVariables(t *testing.T) {
	script := `-- Variables: &dryrun (Enter=1 print only, 0=execute)

SET SERVEROUTPUT ON

PROMPT dryrun (Enter=1 print only, 0=execute):

DECLARE
  l_dryrun NUMBER := NVL(TO_NUMBER(NULLIF(TRIM('&dryrun'), '')), 1);
BEGIN
  NULL;
END;
/
`
	info := promptInfo(script, "&dryrun")
	want := "dryrun (Enter=1 print only, 0=execute):"
	if info.Hint != want {
		t.Fatalf("hint = %q, want %q", info.Hint, want)
	}
}

func TestOnePromptLinePerVariable(t *testing.T) {
	script := `
PROMPT Enter begin_snap:
PROMPT Enter end_snap:
SELECT &begin_snap AS b, &end_snap AS e FROM dual;
`
	vars := collectScriptVariables(script)
	if len(vars) != 2 {
		t.Fatalf("vars = %v", vars)
	}
	infos := resolveVariablePromptInfos(script, vars)
	if infos[vars[0]].Hint != "Enter begin_snap:" {
		t.Fatalf("first var %s hint = %q", vars[0], infos[vars[0]].Hint)
	}
	if infos[vars[1]].Hint != "Enter end_snap:" {
		t.Fatalf("second var %s hint = %q", vars[1], infos[vars[1]].Hint)
	}
}

func TestBannerPromptWithVariableName(t *testing.T) {
	script := `
PROMPT | User status (username = &username) |
SELECT username FROM dba_users WHERE username = UPPER('&username');
`
	info := promptInfo(script, "&username")
	if !strings.Contains(info.Hint, "&username") {
		t.Fatalf("banner hint = %q", info.Hint)
	}
}

func TestFindVariablesSkipsCommentLines(t *testing.T) {
	e := testExecutor("yashandb")
	script := `-- Variables: &dryrun (documentation)
SELECT '&dryrun' FROM dual;
`
	vars := e.findVariables(script)
	if len(vars) != 1 || vars[0] != "&dryrun" {
		t.Fatalf("vars = %v, want [&dryrun]", vars)
	}
}

func TestReplaceVariableSkipsCommentLines(t *testing.T) {
	e := testExecutor("yashandb")
	script := `-- keep &dryrun unchanged
SELECT '&dryrun' FROM dual;
`
	out := e.replaceVariable(script, "&dryrun", "1")
	if !strings.Contains(out, "-- keep &dryrun unchanged") {
		t.Fatalf("comment line was modified:\n%s", out)
	}
	if !strings.Contains(out, "'1'") || strings.Contains(out, "'&dryrun'") {
		t.Fatalf("SQL line not replaced:\n%s", out)
	}
}

const testPromptAcceptSQL = `-- Variables: &top_n &name (doc only, ignored)
SET SERVEROUTPUT ON
SET VERIFY OFF

PROMPT Enter filter name (empty=ALL):

ACCEPT top_n prompt 'Enter top_n count: ' default '10'

SELECT '&top_n' AS top_n, '&name' AS filter_name FROM DUAL;
`

func applyYashandbSubstitutions(e *Executor, script string, read func(string, variablePromptInfo) string) string {
	variables := e.findVariables(script)
	promptInfos := resolveVariablePromptInfos(script, variables)
	varMap := make(map[string]string)
	for _, variable := range variables {
		info := promptInfos[variable]
		value := read(variable, info)
		if value == "" && info.Default != "" {
			value = info.Default
		}
		if e.cfg.DBType == "yashandb" {
			value = escapeYasqlSubstValue(value)
		}
		varMap[variable] = value
	}
	script = stripSQLPlusClientCommands(script)
	for variable, value := range varMap {
		script = e.replaceVariable(script, variable, value)
	}
	return script
}

func TestYashandbPromptAcceptHintsAndDefault(t *testing.T) {
	e := testExecutor("yashandb")
	vars := collectScriptVariables(testPromptAcceptSQL)
	infos := resolveVariablePromptInfos(testPromptAcceptSQL, vars)

	topInfo := infos["&top_n"]
	if topInfo.Hint != "Enter top_n count: " || topInfo.Default != "10" {
		t.Fatalf("&top_n info = %+v", topInfo)
	}

	nameInfo := infos["&name"]
	if nameInfo.Hint != "Enter filter name (empty=ALL):" {
		t.Fatalf("&name hint = %q", nameInfo.Hint)
	}

	out := applyYashandbSubstitutions(e, testPromptAcceptSQL, func(string, variablePromptInfo) string {
		return ""
	})
	if strings.Contains(out, "PROMPT") || strings.Contains(out, "ACCEPT") {
		t.Fatalf("client commands not stripped:\n%s", out)
	}
	if !strings.Contains(out, "'10'") || !strings.Contains(out, "''") {
		t.Fatalf("ACCEPT default not applied:\n%s", out)
	}
	if strings.Contains(out, "-- Variables: 10") {
		t.Fatalf("comment line was substituted:\n%s", out)
	}
}

func TestYashandbPromptAcceptExplicitValues(t *testing.T) {
	e := testExecutor("yashandb")
	inputs := map[string]string{
		"&top_n": "5",
		"&name":  "APP",
	}
	out := applyYashandbSubstitutions(e, testPromptAcceptSQL, func(varName string, info variablePromptInfo) string {
		return inputs[varName]
	})
	if !strings.Contains(out, "'5'") || !strings.Contains(out, "'APP'") {
		t.Fatalf("explicit values not applied:\n%s", out)
	}
}

func TestParseAcceptLineDefaultVariants(t *testing.T) {
	_, _, def, ok := parseAcceptLine("ACCEPT n prompt 'Enter n: ' default '10'")
	if !ok || def != "10" {
		t.Fatalf("quoted default = %q ok=%v", def, ok)
	}
	_, _, def, ok = parseAcceptLine("ACCEPT n prompt 'Enter n: ' default 10")
	if !ok || def != "10" {
		t.Fatalf("bare default = %q ok=%v", def, ok)
	}
}

func TestFormatVariableInputPromptShowsDefaultKeyword(t *testing.T) {
	got := formatVariableInputPrompt("&top_n", "10")
	want := "\r\nEnter value for &top_n (default 10): "
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
	if got := formatVariableInputPrompt("&name", ""); got != "\r\nEnter value for &name: " {
		t.Fatalf("no-default prompt = %q", got)
	}
}

func TestPromptTwoVarsSelectThreeVars(t *testing.T) {
	scriptWithThirdPrompt := `
PROMPT Enter &begin_snap and &end_snap:
PROMPT Enter inst_id:
SELECT &begin_snap, &end_snap, &inst_id FROM dual;
`
	vars := collectScriptVariables(scriptWithThirdPrompt)
	if len(vars) != 3 {
		t.Fatalf("vars = %v", vars)
	}
	infos := resolveVariablePromptInfos(scriptWithThirdPrompt, vars)
	banner := "Enter &begin_snap and &end_snap:"
	if infos["&begin_snap"].Hint != banner || infos["&end_snap"].Hint != banner {
		t.Fatalf("banner hints = begin=%q end=%q", infos["&begin_snap"].Hint, infos["&end_snap"].Hint)
	}
	if infos["&inst_id"].Hint != "Enter inst_id:" {
		t.Fatalf("&inst_id hint = %q", infos["&inst_id"].Hint)
	}

	scriptNoThirdPrompt := `
PROMPT Enter &begin_snap and &end_snap:
SELECT &begin_snap, &end_snap, &inst_id FROM dual;
`
	infos = resolveVariablePromptInfos(scriptNoThirdPrompt, vars)
	if infos["&begin_snap"].Hint != banner || infos["&end_snap"].Hint != banner {
		t.Fatalf("banner hints = begin=%q end=%q", infos["&begin_snap"].Hint, infos["&end_snap"].Hint)
	}
	if infos["&inst_id"].Hint != "" {
		t.Fatalf("&inst_id hint = %q, want empty (use Enter value for &inst_id:)", infos["&inst_id"].Hint)
	}
	if got := formatVariableInputPrompt("&inst_id", ""); got != "\r\nEnter value for &inst_id: " {
		t.Fatalf("default input prompt = %q", got)
	}
}

func TestAcceptDoesNotConsumePromptLine(t *testing.T) {
	script := `
PROMPT Orphan prompt should not bind:
ACCEPT a prompt 'Hint for a: ' default '1'
PROMPT Hint for b:
SELECT &a, &b FROM dual;
`
	vars := collectScriptVariables(script)
	infos := resolveVariablePromptInfos(script, vars)
	if infos["&a"].Hint != "Hint for a: " || infos["&a"].Default != "1" {
		t.Fatalf("&a = %+v", infos["&a"])
	}
	if infos["&b"].Hint != "Hint for b:" {
		t.Fatalf("&b hint = %q", infos["&b"].Hint)
	}
}
