package config

import "testing"

func TestDefaultSysStatQueryMetrics(t *testing.T) {
	cfg := DefaultConfig()
	if len(cfg.SysStatMetrics) != 20 {
		t.Fatalf("SysStatMetrics len = %d, want 20", len(cfg.SysStatMetrics))
	}
	if len(cfg.SessionStatMetrics) != 20 {
		t.Fatalf("SessionStatMetrics len = %d, want 20", len(cfg.SessionStatMetrics))
	}
	if len(SessionStatDisplayNames()) != len(SysStatDisplayNames()) {
		t.Fatalf("session display names should match sysstat display names")
	}
	has := func(name string) bool {
		for _, m := range cfg.SysStatMetrics {
			if m == name {
				return true
			}
		}
		return false
	}
	for _, want := range []string{
		MetricCheckpointsCompleted, MetricUserIOWaitTime,
		MetricDiskReadTime, MetricDiskWriteTime, MetricVMOpen, MetricVMSwapOut,
	} {
		if !has(want) {
			t.Fatalf("SysStatMetrics missing %q", want)
		}
	}
}
