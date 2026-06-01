package scripts

import "testing"

func TestNormalizeScriptDescription(t *testing.T) {
	tests := []struct {
		in, want string
	}{
		{"Purpose: YashanDB Show AWR load profile", "YashanDB Show AWR load profile"},
		{"Purpose:YashanDB no space", "YashanDB no space"},
		{"YashanDB already clean", "YashanDB already clean"},
		{"", ""},
	}
	for _, tt := range tests {
		if got := normalizeScriptDescription(tt.in); got != tt.want {
			t.Fatalf("normalizeScriptDescription(%q) = %q, want %q", tt.in, got, tt.want)
		}
	}
}

func TestGetDescriptionFromContent_SQLHeader(t *testing.T) {
	content := []byte("-- File Name: we.sql\n-- Purpose: YashanDB Session overview\n-- Created: 20251201  by  huangtingzhong\n")
	got := getDescriptionFromContent(content)
	want := "YashanDB Session overview"
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestGetRegexForPattern_EmptyMeansAll(t *testing.T) {
	matcher, err := getRegexForPattern("")
	if err != nil {
		t.Fatal(err)
	}
	if !matcher("we.sql") || !matcher("strace.sh") {
		t.Fatal("empty pattern should match any filename")
	}
}

func TestGetDescriptionFromContent_ShebangBeforeHeader(t *testing.T) {
	content := []byte("#!/usr/bin/env bash\n# File Name: strace.sh\n# Purpose: Wrap strace for DB troubleshooting\n# Created: 20260517  by  huangtingzhong\n")
	got := getDescriptionFromContent(content)
	want := "Wrap strace for DB troubleshooting"
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}
