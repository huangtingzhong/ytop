package calculator

import (
	"testing"
	"time"

	"github.com/yihan/ytop/internal/config"
	"github.com/yihan/ytop/internal/models"
)

func TestCalculateSystemEventDeltas_percentageUsesAllEventsNotTopN(t *testing.T) {
	cfg := &config.Config{EventTopN: 5}
	calc := NewCalculator(cfg)

	baseline := []models.SystemEvent{
		{InstID: 1, EventName: "big", TotalWaits: 0, TimeWaited: 0},
		{InstID: 1, EventName: "small-a", TotalWaits: 0, TimeWaited: 0},
		{InstID: 1, EventName: "small-b", TotalWaits: 0, TimeWaited: 0},
		{InstID: 1, EventName: "small-c", TotalWaits: 0, TimeWaited: 0},
		{InstID: 1, EventName: "small-d", TotalWaits: 0, TimeWaited: 0},
		{InstID: 1, EventName: "small-e", TotalWaits: 0, TimeWaited: 0},
		{InstID: 1, EventName: "small-f", TotalWaits: 0, TimeWaited: 0},
	}
	if got := calc.CalculateSystemEventDeltas(baseline); len(got) != 0 {
		t.Fatalf("baseline pass should return empty, got %d rows", len(got))
	}

	current := []models.SystemEvent{
		{InstID: 1, EventName: "big", TotalWaits: 100, TimeWaited: 80},
		{InstID: 1, EventName: "small-a", TotalWaits: 10, TimeWaited: 1},
		{InstID: 1, EventName: "small-b", TotalWaits: 10, TimeWaited: 1},
		{InstID: 1, EventName: "small-c", TotalWaits: 10, TimeWaited: 1},
		{InstID: 1, EventName: "small-d", TotalWaits: 10, TimeWaited: 1},
		{InstID: 1, EventName: "small-e", TotalWaits: 10, TimeWaited: 1},
		{InstID: 1, EventName: "small-f", TotalWaits: 10, TimeWaited: 1},
	}
	top := calc.CalculateSystemEventDeltas(current)
	if len(top) != 5 {
		t.Fatalf("top rows = %d, want 5", len(top))
	}

	var pctSum float64
	for _, e := range top {
		pctSum += e.Percentage
	}
	// 7 events share interval wait: 80 + 1*6 = 86; top 5 pct sum = (80+1+1+1+1)/86*100 < 100
	if pctSum >= 99.9 {
		t.Fatalf("top 5 pct sum = %.2f%%, expected < 100%% when other events also waited", pctSum)
	}
	if top[0].EventName != "big" || top[0].Percentage <= 90 {
		t.Fatalf("top event = %+v, want big with ~93%%", top[0])
	}
}

func TestCalculateSysStatDeltas_derivedIOAvg(t *testing.T) {
	cfg := &config.Config{DebugMode: false}
	calc := NewCalculator(cfg)
	t0 := time.Now()

	baseline := []models.SysStatMetric{
		{InstID: 1, Name: config.MetricDiskReads, CurrentValue: 1000},
		{InstID: 1, Name: config.MetricDiskReadTime, CurrentValue: 5000},
		{InstID: 1, Name: config.MetricDiskWrites, CurrentValue: 200},
		{InstID: 1, Name: config.MetricDiskWriteTime, CurrentValue: 800},
	}
	if got := calc.CalculateSysStatDeltas(baseline, t0); len(got) != 4 {
		t.Fatalf("baseline pass should return 4 rows, got %d", len(got))
	}

	t1 := t0.Add(5 * time.Second)
	current := []models.SysStatMetric{
		{InstID: 1, Name: config.MetricDiskReads, CurrentValue: 1100},
		{InstID: 1, Name: config.MetricDiskReadTime, CurrentValue: 5500},
		{InstID: 1, Name: config.MetricDiskWrites, CurrentValue: 220},
		{InstID: 1, Name: config.MetricDiskWriteTime, CurrentValue: 900},
	}
	got := calc.CalculateSysStatDeltas(current, t1)
	var readAvg, writeAvg *models.SysStatMetric
	for i := range got {
		switch got[i].Name {
		case config.DerivedAvgReadMS:
			readAvg = &got[i]
		case config.DerivedAvgWriteMS:
			writeAvg = &got[i]
		}
	}
	if readAvg == nil || writeAvg == nil {
		t.Fatalf("missing derived metrics in %d rows", len(got))
	}
	// delta reads=100, delta time=500ms -> 5.0 ms/read
	if readAvg.IntervalValue != 5.0 {
		t.Fatalf("AVG READ MS = %.4f, want 5.0", readAvg.IntervalValue)
	}
	// delta writes=20, delta time=100ms -> 5.0 ms/write
	if writeAvg.IntervalValue != 5.0 {
		t.Fatalf("AVG WRITE MS = %.4f, want 5.0", writeAvg.IntervalValue)
	}
}

func TestSessionDerivedIOAvg(t *testing.T) {
	prev := map[string]float64{
		config.MetricDiskReads: 100, config.MetricDiskReadTime: 500,
		config.MetricDiskWrites: 20, config.MetricDiskWriteTime: 80,
	}
	cur := map[string]float64{
		config.MetricDiskReads: 150, config.MetricDiskReadTime: 750,
		config.MetricDiskWrites: 30, config.MetricDiskWriteTime: 130,
	}
	got := sessionDerivedIOAvg(prev, cur)
	if got[config.DerivedAvgReadMS] != 5.0 {
		t.Fatalf("session RDMS = %.4f, want 5.0", got[config.DerivedAvgReadMS])
	}
	if got[config.DerivedAvgWriteMS] != 5.0 {
		t.Fatalf("session WRMS = %.4f, want 5.0", got[config.DerivedAvgWriteMS])
	}
}
