package config

import (
	"reflect"
	"testing"
)

func TestNormalizeFindScriptFlagArgs(t *testing.T) {
	args := []string{"ytop", "-S"}
	got := normalizeFindScriptFlagArgs(args)
	want := []string{"ytop", "-S", ""}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}

	args = []string{"ytop", "-S", "awr"}
	got = normalizeFindScriptFlagArgs(args)
	want = []string{"ytop", "-S", "awr"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}

	args = []string{"ytop", "-S", "-f", "we.sql"}
	got = normalizeFindScriptFlagArgs(args)
	want = []string{"ytop", "-S", "", "-f", "we.sql"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}
