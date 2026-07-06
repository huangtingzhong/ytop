package executor

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCollectPromptBlocksInRange_contiguousWithBlank(t *testing.T) {
	lines := splitScriptLines(`SET X=1
PROMPT
PROMPT +---+
PROMPT | hi |
PROMPT
DECLARE
  x := '&&confirm';
`)
	blocks := collectPromptBlocksInRange(lines, 0, 6)
	if len(blocks) != 1 {
		t.Fatalf("blocks=%d want 1", len(blocks))
	}
	if len(blocks[0]) != 4 {
		t.Fatalf("lines in block=%d want 4", len(blocks[0]))
	}
	if !blocks[0][0].blank || blocks[0][1].text != "+---+" {
		t.Fatalf("unexpected block: %+v", blocks[0])
	}
}

func TestCollectPromptBlocksInRange_nonContiguous(t *testing.T) {
	lines := splitScriptLines(`PROMPT block A
SET SERVEROUTPUT ON
PROMPT block B
DECLARE
  v := '&&x';
`)
	blocks := collectPromptBlocksInRange(lines, 0, 4)
	if len(blocks) != 2 {
		t.Fatalf("blocks=%d want 2", len(blocks))
	}
	if blocks[0][0].text != "block A" || blocks[1][0].text != "block B" {
		t.Fatalf("unexpected blocks: %+v %+v", blocks[0], blocks[1])
	}
}

func TestCollectPromptBlocksInRange_tailNotIncluded(t *testing.T) {
	lines := splitScriptLines(`DECLARE
  v := '&&x';
/
PROMPT after sql
SELECT 1 FROM dual;
`)
	blocks := collectPromptBlocksInRange(lines, 3, len(lines))
	if len(blocks) != 1 || blocks[0][0].text != "after sql" {
		t.Fatalf("tail blocks=%+v", blocks)
	}
	blocksBefore := collectPromptBlocksInRange(lines, 0, 1)
	if len(blocksBefore) != 0 {
		t.Fatalf("before first var blocks=%+v want none", blocksBefore)
	}
}

func TestFormatYashanDBPromptBlocks_dedupDisplayed(t *testing.T) {
	script := "PROMPT one\nPROMPT two\nDECLARE\n  v := '&&x';\n"
	displayed := map[int]bool{0: true}
	out := formatYashanDBPromptBlocks(script, 0, 3, displayed)
	if strings.Contains(out, "one") || !strings.Contains(out, "two") {
		t.Fatalf("out=%q displayed=%v", out, displayed)
	}
	if !displayed[1] {
		t.Fatal("line 1 should be marked displayed")
	}
}

func TestYashanDBPromptWindow_twoVariables(t *testing.T) {
	script := `PROMPT owner hint
DECLARE
  o := '&&owner';
PROMPT table hint
  t := '&&tablename';
`
	lines := splitScriptLines(script)
	vars := []string{"&&owner", "&&tablename"}
	s0, e0 := yashanDBPromptWindow(vars, 0, lines)
	if s0 != 0 || e0 != 2 {
		t.Fatalf("window0=%d..%d want 0..2", s0, e0)
	}
	s1, e1 := yashanDBPromptWindow(vars, 1, lines)
	if s1 != 3 || e1 != 4 {
		t.Fatalf("window1=%d..%d want 3..4", s1, e1)
	}
	out0 := formatYashanDBPromptBlocks(script, s0, e0, nil)
	out1 := formatYashanDBPromptBlocks(script, s1, e1, nil)
	if !strings.Contains(out0, "owner hint") || strings.Contains(out0, "table hint") {
		t.Fatalf("out0=%q", out0)
	}
	if !strings.Contains(out1, "table hint") {
		t.Fatalf("out1=%q", out1)
	}
}

func TestResolveVariablePromptInfos_skipsDisplayedLines(t *testing.T) {
	script := `PROMPT Enter dryrun:
PROMPT Enter owner:
DECLARE
  v_dryrun NUMBER := NVL(TO_NUMBER(NULLIF(TRIM('&&dryrun'), '')), 1);
  v_owner VARCHAR2(128) := '&&owner';
`
	displayed := map[int]bool{0: true, 1: true}
	infos := resolveVariablePromptInfos(script, []string{"&&dryrun", "&&owner"}, displayed)
	if infos["&&dryrun"].Hint != "" || infos["&&owner"].Hint != "" {
		t.Fatalf("hints should be empty after display: %+v", infos)
	}
}

func TestResolveVariablePromptInfos_acceptWithBanner(t *testing.T) {
	script := `PROMPT +---+
PROMPT | warn |
ACCEPT confirm PROMPT 'Confirm (1=on): '
DECLARE
  v := TRIM('&&confirm');
`
	infos := resolveVariablePromptInfos(script, []string{"&&confirm"}, nil)
	if infos["&&confirm"].Hint != "Confirm (1=on): " {
		t.Fatalf("hint=%q", infos["&&confirm"].Hint)
	}
	displayed := map[int]bool{}
	out := formatYashanDBPromptBlocks(script, 0, firstVariableLineIndex(splitScriptLines(script), "confirm"), displayed)
	if !strings.Contains(out, "+---+") || !strings.Contains(out, "| warn |") {
		t.Fatalf("banner out=%q", out)
	}
}

func TestFlashbackOnScriptPromptWindow(t *testing.T) {
	script, err := readTestScript("flashback_on.sql")
	if err != nil {
		t.Skip(err)
	}
	vars := collectScriptVariables(script)
	if len(vars) != 1 || vars[0] != "&&confirm" {
		t.Fatalf("vars=%v", vars)
	}
	lines := splitScriptLines(script)
	start, end := yashanDBPromptWindow(vars, 0, lines)
	out := formatYashanDBPromptBlocks(script, start, end, nil)
	for _, want := range []string{
		"Database FLASHBACK ON / OFF",
		"1 = ALTER DATABASE FLASHBACK ON",
		"0 = ALTER DATABASE FLASHBACK OFF",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("missing %q in:\n%s", want, out)
		}
	}
}

func readTestScript(name string) (string, error) {
	roots := []string{
		"../../internal/scripts/sql/yashandb",
		"../scripts/sql/yashandb",
		"internal/scripts/sql/yashandb",
	}
	for _, base := range roots {
		path := filepath.Join(base, name)
		b, err := os.ReadFile(path)
		if err == nil {
			return string(b), nil
		}
	}
	return "", errNotFound
}

var errNotFound = errTest("script not found")

type errTest string

func (e errTest) Error() string { return string(e) }
