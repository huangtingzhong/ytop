package executor

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func repoRoot(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", ".."))
}

func readTestSQL(t *testing.T, rel string) string {
	t.Helper()
	path := filepath.Join(repoRoot(t), rel)
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", rel, err)
	}
	return string(b)
}

func hintsForScript(t *testing.T, script string) map[string]variablePromptInfo {
	t.Helper()
	vars := collectScriptVariables(script)
	return resolveVariablePromptInfos(script, vars)
}

func substScript(t *testing.T, script string, inputs map[string]string) string {
	t.Helper()
	e := testExecutor("yashandb")
	return applyYashandbSubstitutions(e, script, func(varName string, _ variablePromptInfo) string {
		return inputs[varName]
	})
}

func TestOfflinePromptScripts(t *testing.T) {
	root := repoRoot(t)

	cases := []struct {
		name   string
		rel    string
		check  func(t *testing.T, script string)
	}{
		{
			name: "01_basic_mixed",
			rel:  "test/test_yashandb_prompt_accept.sql",
			check: func(t *testing.T, script string) {
				infos := hintsForScript(t, script)
				if infos["&top_n"].Hint != "Enter top_n count: " || infos["&top_n"].Default != "10" {
					t.Fatalf("&top_n = %+v", infos["&top_n"])
				}
				if infos["&name"].Hint != "Enter filter name (empty=ALL):" {
					t.Fatalf("&name hint = %q", infos["&name"].Hint)
				}
				out := substScript(t, script, nil)
				if !strings.Contains(out, "'10'") || !strings.Contains(out, "''") {
					t.Fatalf("defaults not applied:\n%s", out)
				}
				if strings.Contains(out, "\nPROMPT ") || strings.Contains(out, "\nACCEPT ") {
					t.Fatalf("client commands not stripped:\n%s", out)
				}
			},
		},
		{
			name: "02_one_line_per_var",
			rel:  "test/yashandb_prompt_02_one_line_per_var.sql",
			check: func(t *testing.T, script string) {
				infos := hintsForScript(t, script)
				if infos["&begin_snap"].Hint != "Enter begin_snap:" {
					t.Fatalf("begin_snap = %q", infos["&begin_snap"].Hint)
				}
				if infos["&end_snap"].Hint != "Enter end_snap:" {
					t.Fatalf("end_snap = %q", infos["&end_snap"].Hint)
				}
				out := substScript(t, script, map[string]string{"&begin_snap": "100", "&end_snap": "200"})
				if !strings.Contains(out, "'100'") || !strings.Contains(out, "'200'") {
					t.Fatalf("subst failed:\n%s", out)
				}
			},
		},
		{
			name: "03_banner_user",
			rel:  "test/yashandb_prompt_03_banner_user.sql",
			check: func(t *testing.T, script string) {
				info := hintsForScript(t, script)["&username"]
				if !strings.Contains(info.Hint, "&username") {
					t.Fatalf("banner = %q", info.Hint)
				}
				out := substScript(t, script, map[string]string{"&username": "SYS"})
				if !strings.Contains(out, "'SYS'") {
					t.Fatalf("subst failed:\n%s", out)
				}
			},
		},
		{
			name: "04_three_vars",
			rel:  "test/yashandb_prompt_04_three_vars.sql",
			check: func(t *testing.T, script string) {
				infos := hintsForScript(t, script)
				banner := "Enter &begin_snap and &end_snap:"
				if infos["&begin_snap"].Hint != banner || infos["&end_snap"].Hint != banner {
					t.Fatalf("banner mismatch: begin=%q end=%q", infos["&begin_snap"].Hint, infos["&end_snap"].Hint)
				}
				if infos["&inst_id"].Hint != "Enter inst_id:" {
					t.Fatalf("inst_id = %q", infos["&inst_id"].Hint)
				}
				out := substScript(t, script, map[string]string{
					"&begin_snap": "1", "&end_snap": "2", "&inst_id": "1",
				})
				if !strings.Contains(out, "'1'") || !strings.Contains(out, "'2'") {
					t.Fatalf("subst failed:\n%s", out)
				}
			},
		},
		{
			name: "05_third_no_prompt",
			rel:  "test/yashandb_prompt_05_third_no_prompt.sql",
			check: func(t *testing.T, script string) {
				infos := hintsForScript(t, script)
				if infos["&inst_id"].Hint != "" {
					t.Fatalf("inst_id hint = %q, want empty", infos["&inst_id"].Hint)
				}
				out := substScript(t, script, map[string]string{
					"&begin_snap": "10", "&end_snap": "20", "&inst_id": "3",
				})
				if !strings.Contains(out, "'3'") {
					t.Fatalf("subst failed:\n%s", out)
				}
			},
		},
		{
			name: "06_orphan_accept",
			rel:  "test/yashandb_prompt_06_orphan_accept.sql",
			check: func(t *testing.T, script string) {
				infos := hintsForScript(t, script)
				for _, v := range []string{"&a", "&b"} {
					if strings.Contains(infos[v].Hint, "Orphan") {
						t.Fatalf("%s bound to orphan: %q", v, infos[v].Hint)
					}
				}
				if infos["&a"].Hint != "Hint for a: " || infos["&a"].Default != "1" {
					t.Fatalf("&a = %+v", infos["&a"])
				}
				if infos["&b"].Hint != "Hint for b:" {
					t.Fatalf("&b = %q", infos["&b"].Hint)
				}
				out := substScript(t, script, map[string]string{"&b": "99"})
				if !strings.Contains(out, "'1'") || !strings.Contains(out, "'99'") {
					t.Fatalf("a default / b input failed:\n%s", out)
				}
			},
		},
		{
			name: "07_dryrun_nvl",
			rel:  "test/yashandb_prompt_07_dryrun_nvl.sql",
			check: func(t *testing.T, script string) {
				info := hintsForScript(t, script)["&dryrun"]
				if !strings.Contains(info.Hint, "dryrun") {
					t.Fatalf("hint = %q", info.Hint)
				}
				out := substScript(t, script, nil)
				if !strings.Contains(out, "''") {
					t.Fatalf("empty dryrun not substituted:\n%s", out)
				}
			},
		},
		{
			name: "08_no_prompt",
			rel:  "test/yashandb_prompt_08_no_prompt.sql",
			check: func(t *testing.T, script string) {
				if hintsForScript(t, script)["&sid"].Hint != "" {
					t.Fatal("expected empty hint for &sid")
				}
				out := substScript(t, script, map[string]string{"&sid": "100"})
				if !strings.Contains(out, "'100'") {
					t.Fatalf("subst failed:\n%s", out)
				}
			},
		},
		{
			name: "09_comment_skip",
			rel:  "test/yashandb_prompt_09_comment_skip.sql",
			check: func(t *testing.T, script string) {
				vars := collectScriptVariables(script)
				if len(vars) != 1 || vars[0] != "&secret" {
					t.Fatalf("vars = %v", vars)
				}
				out := substScript(t, script, map[string]string{"&secret": "hello"})
				if !strings.Contains(out, "-- Variables: &secret") {
					t.Fatalf("comment line modified:\n%s", out)
				}
				if !strings.Contains(out, "&decoy") {
					t.Fatalf("decoy in comment removed:\n%s", out)
				}
				if !strings.Contains(out, "'hello'") {
					t.Fatalf("secret not substituted:\n%s", out)
				}
			},
		},
		{
			name: "10_accept_defaults",
			rel:  "test/yashandb_prompt_10_accept_defaults.sql",
			check: func(t *testing.T, script string) {
				infos := hintsForScript(t, script)
				if infos["&top_n"].Default != "10" || infos["&hours"].Default != "24" {
					t.Fatalf("defaults: top_n=%q hours=%q", infos["&top_n"].Default, infos["&hours"].Default)
				}
				out := substScript(t, script, nil)
				if !strings.Contains(out, "'10'") || !strings.Contains(out, "'24'") {
					t.Fatalf("defaults not applied:\n%s", out)
				}
			},
		},
		{
			name: "11_optional_filter",
			rel:  "test/yashandb_prompt_11_optional_filter.sql",
			check: func(t *testing.T, script string) {
				if hintsForScript(t, script)["&login"].Hint != "Enter username filter (empty=ALL):" {
					t.Fatal("login hint mismatch")
				}
				out := substScript(t, script, nil)
				if !strings.Contains(out, "''") {
					t.Fatalf("empty login not substituted:\n%s", out)
				}
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			path := filepath.Join(root, tc.rel)
			if _, err := os.Stat(path); err != nil {
				t.Fatalf("missing script %s: %v", tc.rel, err)
			}
			script := readTestSQL(t, tc.rel)
			tc.check(t, script)
		})
	}
}
