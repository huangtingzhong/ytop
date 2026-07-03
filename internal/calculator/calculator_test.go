package calculator

import (
	"testing"

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
