package collector

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/yihan/ytop/internal/config"
	"github.com/yihan/ytop/internal/connector"
	"github.com/yihan/ytop/internal/logger"
	"github.com/yihan/ytop/internal/models"
)

// Collector collects metrics from YashanDB
type Collector struct {
	cfg  *config.Config
	conn connector.Connector
}

// NewCollector creates a new collector
func NewCollector(cfg *config.Config, conn connector.Connector) *Collector {
	return &Collector{
		cfg:  cfg,
		conn: conn,
	}
}

// CollectSysStats collects v$sysstat metrics
func (c *Collector) CollectSysStats(ctx context.Context) ([]models.SysStatMetric, error) {
	// Build SQL with metric names
	metricList := make([]string, len(c.cfg.SysStatMetrics))
	for i, m := range c.cfg.SysStatMetrics {
		metricList[i] = fmt.Sprintf("'%s'", m)
	}

	instFilter := ""
	if c.cfg.InstanceID > 0 {
		instFilter = fmt.Sprintf(" AND INST_ID = %d", c.cfg.InstanceID)
	}

	sql := fmt.Sprintf(`
SELECT INST_ID, NAME, VALUE
FROM GV$SYSSTAT
WHERE NAME IN (%s)%s
ORDER BY INST_ID, NAME
`, strings.Join(metricList, ","), instFilter)

	if c.cfg.DebugMode {
		logger.Debug("[collector] CollectSysStats SQL:\n%s\n", sql)
	}

	rows, err := c.conn.ExecuteQuery(ctx, sql)
	if err != nil {
		return nil, fmt.Errorf("failed to query gv$sysstat: %w", err)
	}

	if c.cfg.DebugMode {
		logger.Debug("[collector] CollectSysStats returned %d rows\n", len(rows))
	}

	var metrics []models.SysStatMetric
	for _, row := range rows {
		if len(row) < 3 {
			continue
		}

		// Skip header row
		if row[0] == "INST_ID" {
			continue
		}

		instID, err := strconv.Atoi(row[0])
		if err != nil {
			if c.cfg.DebugMode {
				logger.Debug("Failed to parse inst_id %s: %v\n", row[0], err)
			}
			continue
		}

		value, err := strconv.ParseFloat(row[2], 64)
		if err != nil {
			if c.cfg.DebugMode {
				logger.Debug("Failed to parse value for %s: %v\n", row[1], err)
			}
			continue
		}

		metrics = append(metrics, models.SysStatMetric{
			InstID:       instID,
			Name:         row[1],
			CurrentValue: value,
		})
	}

	return metrics, nil
}

// CollectSystemEvents collects v$system_event metrics
// Returns ALL events (not limited) so calculator can compute deltas and rank by interval activity
func (c *Collector) CollectSystemEvents(ctx context.Context) ([]models.SystemEvent, error) {
	instFilter := ""
	if c.cfg.InstanceID > 0 {
		instFilter = fmt.Sprintf(" AND INST_ID = %d", c.cfg.InstanceID)
	}

	sql := fmt.Sprintf(`
SELECT INST_ID, EVENT, TOTAL_WAITS, TIME_WAITED_MICRO/1000000 AS TIME_WAITED
FROM GV$SYSTEM_EVENT
WHERE EVENT NOT LIKE 'SQL*Net%%'
  AND EVENT NOT LIKE '%%idle%%'%s
ORDER BY INST_ID, EVENT
`, instFilter)

	if c.cfg.DebugMode {
		logger.Debug("[collector] CollectSystemEvents SQL:\n%s\n", sql)
	}

	rows, err := c.conn.ExecuteQuery(ctx, sql)
	if err != nil {
		return nil, fmt.Errorf("failed to query gv$system_event: %w", err)
	}

	if c.cfg.DebugMode {
		logger.Debug("[collector] CollectSystemEvents returned %d rows\n", len(rows))
	}

	var events []models.SystemEvent

	for _, row := range rows {
		if len(row) < 4 {
			continue
		}

		// Skip header row
		if row[0] == "INST_ID" {
			continue
		}

		instID, err := strconv.Atoi(row[0])
		if err != nil {
			continue
		}

		totalWaits, err := strconv.ParseInt(row[2], 10, 64)
		if err != nil {
			continue
		}

		timeWaited, err := strconv.ParseFloat(row[3], 64)
		if err != nil {
			continue
		}

		events = append(events, models.SystemEvent{
			InstID:     instID,
			EventName:  row[1],
			TotalWaits: totalWaits,
			TimeWaited: timeWaited,
		})
	}

	return events, nil
}

// CollectSessionMetrics collects session-level metrics
func (c *Collector) CollectSessionMetrics(ctx context.Context) ([]models.SessionMetric, error) {
	// Build metric list
	metricList := make([]string, len(c.cfg.SysStatMetrics))
	for i, m := range c.cfg.SysStatMetrics {
		metricList[i] = fmt.Sprintf("'%s'", m)
	}

	instFilter := ""
	if c.cfg.InstanceID > 0 {
		instFilter = fmt.Sprintf(" AND s.INST_ID = %d", c.cfg.InstanceID)
	}

	sql := fmt.Sprintf(`
SELECT
    s.INST_ID,
    s.SID,
    s.SERIAL#,
    p.THREAD_ID,
    s.USERNAME,
    s.SQL_ID,
    s.PROGRAM,
    n.NAME,
    st.VALUE
FROM GV$SESSION s
JOIN GV$PROCESS p ON s.INST_ID = p.INST_ID AND s.PADDR = p.THREAD_ADDR
JOIN GV$SESSTAT st ON s.INST_ID = st.INST_ID AND s.SID = st.SID
JOIN GV$STATNAME n ON st.INST_ID = n.INST_ID AND st.STATISTIC# = n.STATISTIC#
WHERE n.NAME IN (%s)
  AND s.USERNAME IS NOT NULL
  AND s.TYPE != 'BACKGROUND'
  AND NOT (s.INST_ID = TO_NUMBER(SYS_CONTEXT('USERENV', 'INSTANCE'))
       AND s.SID = TO_NUMBER(SYS_CONTEXT('USERENV', 'SID')))%s
ORDER BY s.INST_ID, s.SID, n.NAME
`, strings.Join(metricList, ","), instFilter)

	if c.cfg.DebugMode {
		logger.Debug("[collector] CollectSessionMetrics SQL:\n%s\n", sql)
	}

	rows, err := c.conn.ExecuteQuery(ctx, sql)
	if err != nil {
		return nil, fmt.Errorf("failed to query session metrics: %w", err)
	}

	if c.cfg.DebugMode {
		logger.Debug("[collector] CollectSessionMetrics returned %d rows\n", len(rows))
	}

	// Group by instance and session
	sessionMap := make(map[string]*models.SessionMetric)

	for _, row := range rows {
		if len(row) < 9 {
			continue
		}

		// Skip header row
		if row[0] == "INST_ID" {
			continue
		}

		instID, err := strconv.Atoi(row[0])
		if err != nil {
			continue
		}

		sid, err := strconv.Atoi(row[1])
		if err != nil {
			continue
		}

		serial, err := strconv.Atoi(row[2])
		if err != nil {
			continue
		}

		threadID, err := strconv.Atoi(row[3])
		if err != nil {
			continue
		}

		username := row[4]
		sqlID := row[5]
		program := row[6]
		metricName := row[7]

		value, err := strconv.ParseFloat(row[8], 64)
		if err != nil {
			continue
		}

		key := fmt.Sprintf("%d-%d-%d", instID, sid, serial)
		if _, exists := sessionMap[key]; !exists {
			sessionMap[key] = &models.SessionMetric{
				InstID:   instID,
				SID:      sid,
				Serial:   serial,
				ThreadID: threadID,
				SidTid:   fmt.Sprintf("%d.%d.%d", sid, serial, threadID),
				Username: username,
				SqlID:    sqlID,
				Program:  program,
				Metrics:  make(map[string]float64),
			}
		}

		sessionMap[key].Metrics[metricName] = value
	}

	// Convert map to slice
	var metrics []models.SessionMetric
	for _, m := range sessionMap {
		metrics = append(metrics, *m)
	}

	return metrics, nil
}

// CollectSessionDetails collects active session details (same session filter as we.sql).
// Note: CollectSessionMetrics does not filter INACTIVE status; this query does.
func (c *Collector) CollectSessionDetails(ctx context.Context) ([]models.SessionDetail, error) {
	instFilter := ""
	if c.cfg.InstanceID > 0 {
		instFilter = fmt.Sprintf(" AND a.INST_ID = %d", c.cfg.InstanceID)
	}

	sql := fmt.Sprintf(`
SELECT
    x.sid_tid,
    x.event,
    x.username,
    x.program,
    x.sql_id,
    GREATEST(0,
        EXTRACT(DAY FROM x.exec_delta) * 86400000 +
        EXTRACT(HOUR FROM x.exec_delta) * 3600000 +
        EXTRACT(MINUTE FROM x.exec_delta) * 60000 +
        EXTRACT(SECOND FROM x.exec_delta) * 1000
    ) AS exec_ms,
    x.client,
    x.inst_id
FROM (
    SELECT
        a.inst_id||'.'||a.sid||'.'||a.serial#||'.'||b.thread_id AS sid_tid,
        substr(a.wait_event,1,30) AS event,
        a.username AS username,
        substr(a.cli_program,1,30) AS program,
        substr(c.command_name,1,3)||'.'||nvl(a.sql_id,a.sql_id) AS sql_id,
        CAST(
            CAST(SYSTIMESTAMP AS TIMESTAMP(6)) - CAST(a.exec_start_time AS TIMESTAMP(6))
            AS INTERVAL DAY(9) TO SECOND(6)
        ) AS exec_delta,
        a.ip_address||'.'||a.ip_port AS client,
        a.inst_id
    FROM GV$SESSION a, GV$PROCESS b, V$SQLCOMMAND c
    WHERE a.inst_id = b.inst_id
      AND a.paddr = b.thread_addr
      AND a.command = c.command_type(+)
      AND a.TYPE NOT IN ('BACKGROUND')
      AND a.status NOT IN ('INACTIVE')
      AND NOT (a.INST_ID = TO_NUMBER(SYS_CONTEXT('USERENV', 'INSTANCE'))
           AND a.SID = TO_NUMBER(SYS_CONTEXT('USERENV', 'SID')))%s
) x
ORDER BY exec_ms DESC
FETCH FIRST %d ROWS ONLY
`, instFilter, c.cfg.SessionDetailTopN)

	if c.cfg.DebugMode {
		logger.Debug("[collector] CollectSessionDetails SQL:\n%s\n", sql)
	}

	_, rows, err := c.conn.ExecuteQueryWithHeader(ctx, sql)
	if err != nil {
		return nil, fmt.Errorf("failed to query session details: %w", err)
	}

	if c.cfg.DebugMode {
		logger.Debug("[collector] CollectSessionDetails returned %d rows\n", len(rows))
	}

	var details []models.SessionDetail
	for _, row := range rows {
		if len(row) < 8 {
			if c.cfg.DebugMode {
				logger.Debug("[collector] skipping row: expected 8 columns, got %d: %v\n", len(row), row)
			}
			continue
		}

		sidTid := strings.TrimSpace(row[0])
		if sidTid == "" || sidTid == "SID_TID" {
			continue
		}

		execMs := parseSessionDetailFloat(row[5])
		instID := parseSessionDetailInt(row[7])

		details = append(details, models.SessionDetail{
			InstID:   instID,
			SidTid:   sidTid,
			Event:    row[1],
			Username: row[2],
			Program:  row[3],
			SqlID:    row[4],
			ExecTime: formatExecTime(execMs),
			Client:   row[6],
		})
	}

	if c.cfg.DebugMode && len(rows) > 0 && len(details) == 0 {
		logger.Debug("[collector] CollectSessionDetails: %d raw rows parsed to 0 details\n", len(rows))
	}

	return details, nil
}

func parseSessionDetailFloat(s string) float64 {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0
	}
	return v
}

func parseSessionDetailInt(s string) int {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0
	}
	if v, err := strconv.Atoi(s); err == nil {
		return v
	}
	if v, err := strconv.ParseFloat(s, 64); err == nil {
		return int(v)
	}
	return 0
}

// formatExecTime formats elapsed time from milliseconds using MS/S/M/H/D (aligned with we.sql).
func formatExecTime(execMs float64) string {
	if execMs < 0 {
		execMs = 0
	}
	switch {
	case execMs < 1000:
		return fmt.Sprintf("%.0fMS", execMs)
	case execMs < 60000:
		return fmt.Sprintf("%.2fS", execMs/1000)
	case execMs < 3600000:
		return fmt.Sprintf("%.2fM", execMs/60000)
	case execMs < 86400000:
		return fmt.Sprintf("%.2fH", execMs/3600000)
	default:
		return fmt.Sprintf("%.2fD", execMs/86400000)
	}
}
