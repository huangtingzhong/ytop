package calculator

import (
	"fmt"
	"sort"
	"time"

	"github.com/yihan/ytop/internal/config"
	"github.com/yihan/ytop/internal/logger"
	"github.com/yihan/ytop/internal/models"
)

// Calculator calculates deltas and rankings
type Calculator struct {
	cfg                *config.Config
	prevSysStats       map[string]float64
	prevTimestamp      time.Time
	prevSystemEvents   map[string]models.SystemEvent
	prevSessionMetrics map[string]models.SessionMetric // key: "SID-Serial"
}

// NewCalculator creates a new calculator
func NewCalculator(cfg *config.Config) *Calculator {
	return &Calculator{
		cfg:                cfg,
		prevSysStats:       make(map[string]float64),
		prevSystemEvents:   make(map[string]models.SystemEvent),
		prevSessionMetrics: make(map[string]models.SessionMetric),
	}
}

// CalculateSysStatDeltas calculates per-second deltas for sysstat metrics
func (c *Calculator) CalculateSysStatDeltas(metrics []models.SysStatMetric, timestamp time.Time) []models.SysStatMetric {
	if c.prevTimestamp.IsZero() {
		for _, m := range metrics {
			key := fmt.Sprintf("%d-%s", m.InstID, m.Name)
			c.prevSysStats[key] = m.CurrentValue
		}
		c.prevTimestamp = timestamp
		if c.cfg.DebugMode {
			logger.Debug("[calculator] SysStats first run: stored %d baseline values\n", len(metrics))
		}
		return metrics
	}

	timeDiff := timestamp.Sub(c.prevTimestamp).Seconds()
	if timeDiff <= 0 {
		timeDiff = 1
	}

	if c.cfg.DebugMode {
		logger.Debug("[calculator] SysStats delta: timeDiff=%.2fs, metrics=%d\n", timeDiff, len(metrics))
	}

	result := make([]models.SysStatMetric, len(metrics))
	for i, m := range metrics {
		result[i] = m
		key := fmt.Sprintf("%d-%s", m.InstID, m.Name)
		if prevValue, exists := c.prevSysStats[key]; exists {
			delta := m.CurrentValue - prevValue
			result[i].DeltaPerSec = delta / timeDiff
			if c.cfg.DebugMode {
				logger.Debug("[calculator]   %s: prev=%.2f cur=%.2f delta/s=%.4f\n", m.Name, prevValue, m.CurrentValue, result[i].DeltaPerSec)
			}
		}
		c.prevSysStats[key] = m.CurrentValue
	}

	c.prevTimestamp = timestamp
	return result
}

// CalculateSystemEventDeltas computes interval deltas for v$system_event and returns TOP N.
// Percentage is each event's share of total interval wait time across ALL events with
// activity in the window (not re-normalized within TOP N).
func (c *Calculator) CalculateSystemEventDeltas(events []models.SystemEvent) []models.SystemEvent {
	if len(c.prevSystemEvents) == 0 {
		for _, e := range events {
			key := fmt.Sprintf("%d-%s", e.InstID, e.EventName)
			c.prevSystemEvents[key] = e
		}
		if c.cfg.DebugMode {
			logger.Debug("[calculator] SystemEvents first run: stored %d baseline events\n", len(events))
		}
		return []models.SystemEvent{}
	}

	deltas := make([]models.SystemEvent, 0, len(events))
	var totalWaitAll float64

	for _, e := range events {
		key := fmt.Sprintf("%d-%s", e.InstID, e.EventName)
		if prev, exists := c.prevSystemEvents[key]; exists {
			deltaWaits := e.TotalWaits - prev.TotalWaits
			deltaTime := e.TimeWaited - prev.TimeWaited

			if deltaWaits > 0 && deltaTime > 0 {
				deltas = append(deltas, models.SystemEvent{
					InstID:      e.InstID,
					EventName:   e.EventName,
					TotalWaits:  deltaWaits,
					TimeWaited:  deltaTime,
					AvgWaitTime: deltaTime / float64(deltaWaits),
				})
				totalWaitAll += deltaTime
			}
		}
		c.prevSystemEvents[key] = e
	}

	for i := range deltas {
		if totalWaitAll > 0 {
			deltas[i].Percentage = (deltas[i].TimeWaited / totalWaitAll) * 100
		}
	}

	sort.Slice(deltas, func(i, j int) bool {
		return deltas[i].TimeWaited > deltas[j].TimeWaited
	})

	topN := deltas
	if len(topN) > c.cfg.EventTopN {
		topN = topN[:c.cfg.EventTopN]
	}

	if c.cfg.DebugMode {
		logger.Debug("[calculator] SystemEvents: %d events with wait in interval, totalWait=%.4fs, showing top %d\n",
			len(deltas), totalWaitAll, len(topN))
		for i, e := range topN {
			logger.Debug("[calculator]   #%d %s: waits=%d time=%.4f avg=%.6f pct=%.2f%% (of all interval wait)\n",
				i+1, e.EventName, e.TotalWaits, e.TimeWaited, e.AvgWaitTime, e.Percentage)
		}
	}

	return topN
}

// RankSessionMetrics ranks sessions by specified metric and calculates per-second deltas
func (c *Calculator) RankSessionMetrics(metrics []models.SessionMetric, timestamp time.Time) []models.SessionMetric {
	result := make([]models.SessionMetric, 0, len(metrics))

	// Calculate time difference in seconds
	var timeDiff float64
	if !c.prevTimestamp.IsZero() {
		timeDiff = timestamp.Sub(c.prevTimestamp).Seconds()
		if timeDiff <= 0 {
			timeDiff = 1
		}
	}

	// Calculate deltas if we have previous data
	if len(c.prevSessionMetrics) > 0 && timeDiff > 0 {
		for _, m := range metrics {
			key := fmt.Sprintf("%d-%d-%d", m.InstID, m.SID, m.Serial)

			// Check if we have previous data for this session
			if prev, exists := c.prevSessionMetrics[key]; exists {
				// Calculate deltas per second for all metrics
				deltaMetrics := make(map[string]float64)
				for metricName, currentValue := range m.Metrics {
					if prevValue, ok := prev.Metrics[metricName]; ok {
						delta := currentValue - prevValue
						if delta > 0 {
							deltaMetrics[metricName] = delta / timeDiff
						} else {
							deltaMetrics[metricName] = 0
						}
					} else {
						deltaMetrics[metricName] = 0
					}
				}

				// Create new session metric with delta per second values
				result = append(result, models.SessionMetric{
					InstID:   m.InstID,
					SID:      m.SID,
					Serial:   m.Serial,
					ThreadID: m.ThreadID,
					SidTid:   m.SidTid,
					Username: m.Username,
					SqlID:    m.SqlID,
					Program:  m.Program,
					Metrics:  deltaMetrics,
				})
			} else {
				// New session, show zero values
				zeroMetrics := make(map[string]float64)
				for metricName := range m.Metrics {
					zeroMetrics[metricName] = 0
				}
				result = append(result, models.SessionMetric{
					InstID:   m.InstID,
					SID:      m.SID,
					Serial:   m.Serial,
					ThreadID: m.ThreadID,
					SidTid:   m.SidTid,
					Username: m.Username,
					SqlID:    m.SqlID,
					Program:  m.Program,
					Metrics:  zeroMetrics,
				})
			}
		}
	}

	// Store current metrics (with original cumulative values) for next iteration
	c.prevSessionMetrics = make(map[string]models.SessionMetric)
	for _, m := range metrics {
		key := fmt.Sprintf("%d-%d-%d", m.InstID, m.SID, m.Serial)
		c.prevSessionMetrics[key] = m
	}

	// First iteration, return empty result (don't show cumulative values)
	if len(result) == 0 {
		if c.cfg.DebugMode {
			logger.Debug("[calculator] SessionMetrics: first iteration, no delta yet\n")
		}
		return result
	}

	sort.Slice(result, func(i, j int) bool {
		valI := result[i].Metrics[c.cfg.SessionSortBy]
		valJ := result[j].Metrics[c.cfg.SessionSortBy]
		return valI > valJ
	})

	if len(result) > c.cfg.SessionTopN {
		result = result[:c.cfg.SessionTopN]
	}

	if c.cfg.DebugMode {
		logger.Debug("[calculator] SessionMetrics: %d sessions (top %d), sortBy=%s\n", len(result), c.cfg.SessionTopN, c.cfg.SessionSortBy)
		for i, m := range result {
			sortVal := m.Metrics[c.cfg.SessionSortBy]
			logger.Debug("[calculator]   #%d %s user=%s sortVal=%.4f\n", i+1, m.SidTid, m.Username, sortVal)
		}
	}

	return result
}
