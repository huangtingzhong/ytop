#!/bin/bash

# PostgreSQL Backup Script - Using pg_probackup
# Function: Automatic full/incremental backup based on weekday, auto-cleanup expired backups
# Date: 20250816
# Contact: 18081072613

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions - Format: YYYY-MM-DD HH24:MI:SS : content
# Using printf for better macOS compatibility
log_info() {
    printf "${BLUE}%s : %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_success() {
    printf "${GREEN}%s : %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_warning() {
    printf "${YELLOW}%s : %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

log_error() {
    printf "${RED}%s : %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Function to log command execution when verbose mode is enabled
log_command() {
    if $VERBOSE; then
        printf "${BLUE}%s : [COMMAND] %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    fi
}

# Function to validate recovery time format (YYYY-MM-DD HH24:MI:SS)
validate_recovery_time() {
    local recovery_time="$1"
    
    # Check if the format matches YYYY-MM-DD HH24:MI:SS
    if [[ "$recovery_time" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        # Validate date components
        local year=$(echo "$recovery_time" | cut -d' ' -f1 | cut -d'-' -f1)
        local month=$(echo "$recovery_time" | cut -d' ' -f1 | cut -d'-' -f2)
        local day=$(echo "$recovery_time" | cut -d' ' -f1 | cut -d'-' -f3)
        local hour=$(echo "$recovery_time" | cut -d' ' -f2 | cut -d':' -f1)
        local minute=$(echo "$recovery_time" | cut -d' ' -f2 | cut -d':' -f2)
        local second=$(echo "$recovery_time" | cut -d' ' -f2 | cut -d':' -f3)
        
        # Basic validation - use 10# to force base-10 interpretation
        if [[ $((10#$year)) -ge 1900 && $((10#$year)) -le 2100 ]] && \
           [[ $((10#$month)) -ge 1 && $((10#$month)) -le 12 ]] && \
           [[ $((10#$day)) -ge 1 && $((10#$day)) -le 31 ]] && \
           [[ $((10#$hour)) -ge 0 && $((10#$hour)) -le 23 ]] && \
           [[ $((10#$minute)) -ge 0 && $((10#$minute)) -le 59 ]] && \
           [[ $((10#$second)) -ge 0 && $((10#$second)) -le 59 ]]; then
            return 0
        fi
    fi
    
    return 1
}

# Show help information
show_help() {
    cat << EOF
PostgreSQL Backup Script - Using pg_probackup

Usage: $0 [options]

Options:
    -B <backup_dir>       pg_probackup backup directory (default: /postgresql/pgback)
    -i <instance_name>    PostgreSQL instance name (default: 1721)
    -d <weekday>          Weekday for full backup (1-7, 1=Monday, 7=Sunday, default: 7)
    -t <retention_days>   Backup retention days (default: 30)
    -m <incremental_mode> Incremental backup mode for DELTA, PAGE, or PTRACK (default: DELTA)
    -D                     Delete expired backups only (no backup execution)
    -R <recovery_time>    Validate recovery to specific time point (format: YYYY-MM-DD HH24:MI:SS)
    -v                     Verbose output
    -h                     Show this help information

Examples:
    $0 -B /backup/postgresql -i prod_db -d 7
    $0 -B /backup/postgresql -i prod_db -d 1 -t 60
    $0                                    # Use all default values
    $0 -d 1                              # Use default values but set Monday as full backup day
    $0 -m PAGE                           # Use PAGE mode for incremental backups
    $0 -D                                # Delete expired backups only
    $0 -D -t 60                          # Delete expired backups with custom retention (60 days)
    $0 -R "2025-08-16 10:30:00"         # Validate recovery to specific time point
    $0 -B /backup/postgresql -i prod_db -R "2025-08-16 15:45:00"  # Validate with custom backup dir and instance

Backup Strategy:
    - Full backup on specified weekday
    - Incremental backup on other days with specified mode
    - Auto-cleanup expired backups after backup completion
    - Use -D option to only delete expired backups without backup execution

Incremental Backup Modes:
    - DELTA: Reads all data files and copies only changed pages (default)
    - PAGE: Scans WAL files and copies only pages mentioned in WAL records
    - PTRACK: Uses page tracking for efficient incremental backups

Contact: 18081072613

EOF
}

# Parameter parsing with defaults
BACKUP_DIR="/postgresql/pgback"
INSTANCE_NAME="1721"
FULL_BACKUP_WEEKDAY="7"
RETENTION_DAYS=30
INCREMENTAL_MODE="DELTA"
VERBOSE=false
DELETE_ONLY=false
RECOVERY_TIME=""

while getopts "B:i:d:t:m:DR:vh" opt; do
    case $opt in
        B) BACKUP_DIR="$OPTARG" ;;
        i) INSTANCE_NAME="$OPTARG" ;;
        d) FULL_BACKUP_WEEKDAY="$OPTARG" ;;
        t) RETENTION_DAYS="$OPTARG" ;;
        m) INCREMENTAL_MODE="$OPTARG" ;;
        D) DELETE_ONLY=true ;;
        R) RECOVERY_TIME="$OPTARG" ;;
        v) VERBOSE=true ;;
        h) show_help; exit 0 ;;
        *) log_error "Invalid option: -$OPTARG"; show_help; exit 1 ;;
    esac
done

# Validate weekday parameter (1-7) - only if not delete-only mode
if [[ "$DELETE_ONLY" == false ]] && ! [[ "$FULL_BACKUP_WEEKDAY" =~ ^[1-7]$ ]]; then
    log_error "Invalid weekday parameter: $FULL_BACKUP_WEEKDAY (must be 1-7)"
    exit 1
fi

# Validate retention days parameter
if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || [ "$RETENTION_DAYS" -lt 1 ]; then
    log_error "Invalid retention days: $RETENTION_DAYS (must be positive integer)"
    exit 1
fi

# Validate incremental mode parameter - only if not delete-only mode
if [[ "$DELETE_ONLY" == false ]]; then
    case $INCREMENTAL_MODE in
        DELTA|PAGE|PTRACK) ;;
        *) log_error "Invalid incremental mode: $INCREMENTAL_MODE (must be DELTA, PAGE, or PTRACK)"; exit 1 ;;
    esac
fi

# Validate recovery time parameter if specified
if [[ -n "$RECOVERY_TIME" ]]; then
    if ! validate_recovery_time "$RECOVERY_TIME"; then
        log_error "Invalid recovery time format: $RECOVERY_TIME"
        log_error "Expected format: YYYY-MM-DD HH24:MI:SS (e.g., 2025-08-16 10:30:00)"
        exit 1
    fi
    log_info "Recovery time validation passed: $RECOVERY_TIME"
fi

# Check if pg_probackup is installed (only if not in recovery validation mode)
if [[ -z "$RECOVERY_TIME" ]]; then
    if ! command -v pg_probackup &> /dev/null; then
        log_error "pg_probackup is not installed or not in PATH"
        log_error "Please install pg_probackup first"
        log_error "Contact: 18081072613"
        exit 1
    fi
fi

# Function to check if recent full backup exists within specified days
check_recent_full_backup() {
    local instance_name="$1"
    local backup_dir="$2"
    local days="$3"
    
    # Get current timestamp in seconds
    local current_time=$(date +%s)
    local cutoff_time=$((current_time - (days * 24 * 3600)))
    
    # Get backup list and check for recent full backups
    local backup_list=$(pg_probackup show -B "$backup_dir" --instance "$instance_name" 2>/dev/null)
    
    if [[ $? -ne 0 || -z "$backup_list" ]]; then
        log_warning "Cannot get backup information, assuming no recent full backup"
        return 1
    fi
    
    # Parse the backup list to find recent FULL backups
    local full_backup_found=false
    local recent_backup_id=""
    local recent_backup_time=""
    
    while IFS= read -r line; do
        # Skip header lines and empty lines
        if [[ "$line" =~ ^[[:space:]]*$ ]] || [[ "$line" =~ ^[[:space:]]*Instance ]] || [[ "$line" =~ ^[[:space:]]*== ]]; then
            continue
        fi
        
        # Parse backup line: Instance Version ID Recovery_Time Mode WAL_Mode TLI Time Data WAL Zratio Start_LSN Stop_LSN Status
        # Example: 1721      14       T12HUQ  2025-08-16 11:34:23+08  FULL   ARCHIVE   8/0  1m:35s  16GB  512MB    1.00  A0/80000060  A0/A00000F0  OK
        # Handle both single-line and multi-line formats
        if [[ "$line" =~ ^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+[A-Z0-9]+[[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}\+[0-9]{2})[[:space:]]+FULL ]]; then
            # Extract backup ID and timestamp
            local backup_id=$(echo "$line" | awk '{print $3}')
            # Extract timestamp (field 4 and 5 combined, since timestamp has space)
            local backup_timestamp_str=$(echo "$line" | awk '{print $4" "$5}')
            
            # Convert timestamp to seconds (remove timezone part for parsing)
            # Use macOS compatible date parsing
            local backup_date=$(echo "$backup_timestamp_str" | sed 's/+[0-9][0-9]$//')
            local backup_timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S" "$backup_date" +%s 2>/dev/null)
            
            if [[ -n "$backup_timestamp" && $backup_timestamp -gt $cutoff_time ]]; then
                full_backup_found=true
                recent_backup_id="$backup_id"
                recent_backup_time="$backup_timestamp_str"
                log_info "Found recent full backup: ID=$backup_id, Time=$backup_timestamp_str"
                break
            fi
        fi
    done <<< "$backup_list"
    
    if [[ "$full_backup_found" == true ]]; then
        log_info "Found recent full backup within last $days days: $recent_backup_id ($recent_backup_time)"
        return 0
    else
        log_warning "No recent full backup found within last $days days"
        return 1
    fi
}

# Check backup directory
if [[ ! -d "$BACKUP_DIR" ]]; then
    log_error "Backup directory does not exist: $BACKUP_DIR"
    log_info "Creating backup directory: $BACKUP_DIR"
    if mkdir -p "$BACKUP_DIR"; then
        log_success "Backup directory created successfully"
    else
        log_error "Failed to create backup directory"
        exit 1
    fi
fi

# Check if instance is initialized by trying to show backups (only if not in recovery validation mode)
if [[ -z "$RECOVERY_TIME" ]]; then
    if ! pg_probackup show -B "$BACKUP_DIR" --instance "$INSTANCE_NAME" >/dev/null 2>&1; then
        log_error "Instance $INSTANCE_NAME is not initialized in backup directory"
        log_info "Please run: pg_probackup init -B $BACKUP_DIR"
        log_info "Then run: pg_probackup add-instance -B $BACKUP_DIR -D <data_directory> -i $INSTANCE_NAME"
        log_info "Contact: 18081072613"
        exit 1
    fi
fi

# If recovery validation mode, perform validation and exit
if [[ -n "$RECOVERY_TIME" ]]; then
    log_info "Recovery validation mode: Validating recovery to $RECOVERY_TIME"
    log_info "Instance: $INSTANCE_NAME"
    log_info "Backup directory: $BACKUP_DIR"
    
    # Show current backup list
    log_info "Current backup list:"
    log_command "pg_probackup show -B \"$BACKUP_DIR\" --instance \"$INSTANCE_NAME\" | tail -10"
    pg_probackup show -B "$BACKUP_DIR" --instance "$INSTANCE_NAME" | tail -10
    
    # Perform recovery validation using pg_probackup validate
    log_info "Starting recovery validation to time point: $RECOVERY_TIME"
    log_info "This will validate if recovery to the specified time is possible"
    
    # Convert recovery time to pg_probackup format (YYYY-MM-DD HH24:MI:SS)
    recovery_target="--recovery-target-time=$RECOVERY_TIME"
    
    # Log the validation command
    log_command "pg_probackup validate -B \"$BACKUP_DIR\" --instance \"$INSTANCE_NAME\" $recovery_target --log-level-file=INFO --log-level-console=INFO"
    
    if $VERBOSE; then
        pg_probackup validate -B "$BACKUP_DIR" --instance "$INSTANCE_NAME" "$recovery_target" \
            --log-level-file=INFO --log-level-console=INFO
    else
        pg_probackup validate -B "$BACKUP_DIR" --instance "$INSTANCE_NAME" "$recovery_target" \
            --log-level-file=INFO --log-level-console=WARNING
    fi
    
    VALIDATION_EXIT_CODE=$?
    
    if [[ $VALIDATION_EXIT_CODE -eq 0 ]]; then
        log_success "Recovery validation completed successfully"
        log_info "Recovery to $RECOVERY_TIME is possible"
        
        # Show validation details
        log_info "Validation details:"
        log_command "pg_probackup show -B \"$BACKUP_DIR\" --instance \"$INSTANCE_NAME\" --format=json | jq -r --arg target_time \"$RECOVERY_TIME\" '.[] | select(.backup_mode == \"FULL\" or .backup_mode == \"DELTA\" or .backup_mode == \"PAGE\" or .backup_mode == \"PTRACK\") | \"Backup ID: \\(.id), Mode: \\(.backup_mode), Start: \\(.start_time), End: \\(.end_time), Status: \\(.status)\"'"
        pg_probackup show -B "$BACKUP_DIR" --instance "$INSTANCE_NAME" --format=json | \
            jq -r --arg target_time "$RECOVERY_TIME" '
                .[] | 
                select(.backup_mode == "FULL" or .backup_mode == "DELTA" or .backup_mode == "PAGE" or .backup_mode == "PTRACK") |
                "Backup ID: \(.id), Mode: \(.backup_mode), Start: \(.start_time), End: \(.end_time), Status: \(.status)"
            ' 2>/dev/null || \
        (log_command "pg_probackup show -B \"$BACKUP_DIR\" --instance \"$INSTANCE_NAME\" | grep -E \"(FULL|DELTA|PAGE|PTRACK)\" | head -5" && \
        pg_probackup show -B "$BACKUP_DIR" --instance "$INSTANCE_NAME" | grep -E "(FULL|DELTA|PAGE|PTRACK)" | head -5)
        
    else
        log_error "Recovery validation failed with exit code: $VALIDATION_EXIT_CODE"
        log_error "Recovery to $RECOVERY_TIME may not be possible"
        log_error "Please check backup availability and WAL archive completeness"
        log_error "Contact: 18081072613"
        exit 1
    fi
    
    log_success "Recovery validation operation completed"
    log_info "Contact: 18081072613"
    exit 0
fi

# If delete-only mode, skip backup logic and go directly to cleanup
if [[ "$DELETE_ONLY" == true ]]; then
    log_info "Delete-only mode: Skipping backup execution"
    log_info "Instance: $INSTANCE_NAME"
    log_info "Backup directory: $BACKUP_DIR"
    log_info "Retention days: $RETENTION_DAYS"
    
    # Show current backup list before cleanup
    log_info "Current backup list before cleanup:"
    log_command "pg_probackup show -B \"$BACKUP_DIR\" --instance \"$INSTANCE_NAME\" | tail -10"
    pg_probackup show -B "$BACKUP_DIR" --instance "$INSTANCE_NAME" | tail -10
    
    # Cleanup expired backups using correct pg_probackup syntax
    log_info "Starting cleanup of expired backups (retain $RETENTION_DAYS days)..."
    log_command "pg_probackup delete -B \"$BACKUP_DIR\" --instance \"$INSTANCE_NAME\" --delete-expired --retention-window=\"$RETENTION_DAYS\""
    if pg_probackup delete -B "$BACKUP_DIR" --instance "$INSTANCE_NAME" --delete-expired --retention-window="$RETENTION_DAYS"; then
        log_success "Expired backup cleanup completed successfully"
    else
        log_warning "Expired backup cleanup failed"
    fi
    
    # Cleanup expired WAL archives
    log_info "Starting cleanup of expired WAL archives (retain $RETENTION_DAYS days)..."
    log_command "pg_probackup delete -B \"$BACKUP_DIR\" --instance \"$INSTANCE_NAME\" --delete-wal --retention-window=\"$RETENTION_DAYS\""
    if pg_probackup delete -B "$BACKUP_DIR" --instance "$INSTANCE_NAME" --delete-wal --retention-window="$RETENTION_DAYS"; then
        log_success "Expired WAL archive cleanup completed successfully"
    else
        log_warning "Expired WAL archive cleanup failed"
    fi
    
    # Show backup list after cleanup
    log_info "Backup list after cleanup:"
    log_command "pg_probackup show -B \"$BACKUP_DIR\" --instance \"$INSTANCE_NAME\" | tail -10"
    pg_probackup show -B "$BACKUP_DIR" --instance "$INSTANCE_NAME" | tail -10
    
    log_success "Delete-only operation completed"
    log_info "Contact: 18081072613"
    exit 0
fi

# Get current time information
CURRENT_DATE=$(date +%Y-%m-%d)
CURRENT_DAY=$(date +%u)  # 1=Monday, 7=Sunday
CURRENT_TIME=$(date +%H:%M:%S)

# Determine backup type based on weekday
if [[ "$CURRENT_DAY" -eq "$FULL_BACKUP_WEEKDAY" ]]; then
    BACKUP_TYPE="full"
    BACKUP_DESC="Full Backup"
    BACKUP_MODE="full"
else
    # Check if we have a recent full backup (within last 7 days)
    log_info "Checking for recent full backup within last 7 days..."
    if check_recent_full_backup "$INSTANCE_NAME" "$BACKUP_DIR" 7; then
        BACKUP_TYPE="incremental"
        BACKUP_DESC="Incremental Backup ($INCREMENTAL_MODE mode)"
        BACKUP_MODE="$INCREMENTAL_MODE"
        log_info "Recent full backup found, proceeding with incremental backup"
    else
        BACKUP_TYPE="full"
        BACKUP_DESC="Full Backup (auto-switched from incremental due to no recent full backup)"
        BACKUP_MODE="full"
        log_warning "No recent full backup found within 7 days, auto-switching to full backup"
    fi
fi

# Log file
LOG_FILE="$BACKUP_DIR/backup_${INSTANCE_NAME}_${BACKUP_TYPE}_${CURRENT_DATE}_${CURRENT_TIME//:/}.log"

# Start backup
log_info "Starting PostgreSQL backup"
log_info "Instance: $INSTANCE_NAME"
log_info "Current weekday: $CURRENT_DAY (1=Monday, 7=Sunday)"
log_info "Full backup weekday: $FULL_BACKUP_WEEKDAY"
log_info "Backup type: $BACKUP_TYPE ($BACKUP_DESC)"
log_info "Backup mode: $BACKUP_MODE"
log_info "Backup directory: $BACKUP_DIR"
log_info "Retention days: $RETENTION_DAYS"
log_info "Log file: $LOG_FILE"

# Record start time
BACKUP_START_TIME=$(date +%s)

# Execute backup using correct pg_probackup syntax (without --tag)
log_info "Executing $BACKUP_DESC..."
log_command "pg_probackup backup -B \"$BACKUP_DIR\" --instance \"$INSTANCE_NAME\" -b \"$BACKUP_MODE\" --log-level-file=INFO --log-level-console=INFO"
if $VERBOSE; then
    pg_probackup backup \
        -B "$BACKUP_DIR" \
        --instance "$INSTANCE_NAME" \
        -b "$BACKUP_MODE" \
        --log-level-file=INFO \
        --log-level-console=INFO \
        2>&1 | tee "$LOG_FILE"
else
    pg_probackup backup \
        -B "$BACKUP_DIR" \
        --instance "$INSTANCE_NAME" \
        -b "$BACKUP_MODE" \
        --log-level-file=INFO \
        --log-level-console=WARNING \
        2>&1 | tee "$LOG_FILE"
fi

BACKUP_EXIT_CODE=${PIPESTATUS[0]}

# Check if backup was successful
if [[ $BACKUP_EXIT_CODE -eq 0 ]]; then
    log_success "$BACKUP_DESC completed successfully"
    
    # Get the latest backup ID for cleanup operations
    log_info "Getting latest backup ID for cleanup operations..."
    
    # Try multiple methods to get backup ID
    LATEST_BACKUP_ID=""
    
    # Method 1: Try JSON format with jq (if available)
    if command -v jq &> /dev/null; then
        log_info "Trying to get backup ID using JSON format..."
        log_command "pg_probackup show -B \"$BACKUP_DIR\" --instance \"$INSTANCE_NAME\" --format=json"
        json_output=$(pg_probackup show -B "$BACKUP_DIR" --instance "$INSTANCE_NAME" --format=json 2>/dev/null)
        if [[ $? -eq 0 && -n "$json_output" ]]; then
            LATEST_BACKUP_ID=$(echo "$json_output" | jq -r '.[0].id' 2>/dev/null)
            if [[ -n "$LATEST_BACKUP_ID" && "$LATEST_BACKUP_ID" != "null" ]]; then
                log_info "Successfully got backup ID using JSON method: $LATEST_BACKUP_ID"
            fi
        fi
    fi
    
    # Method 2: Parse default output format if JSON method failed
    if [[ -z "$LATEST_BACKUP_ID" ]]; then
        log_info "JSON method failed, trying default output format..."
        log_command "pg_probackup show -B \"$BACKUP_DIR\" --instance \"$INSTANCE_NAME\""
        backup_list=$(pg_probackup show -B "$BACKUP_DIR" --instance "$INSTANCE_NAME" 2>/dev/null)
        if [[ $? -eq 0 && -n "$backup_list" ]]; then
            # Extract the first backup ID from the output
            LATEST_BACKUP_ID=$(echo "$backup_list" | grep -E '^[[:space:]]*[A-Z0-9]+[[:space:]]+' | head -1 | awk '{print $1}' | tr -d '[:space:]')
            if [[ -n "$LATEST_BACKUP_ID" ]]; then
                log_info "Successfully got backup ID using default format: $LATEST_BACKUP_ID"
            fi
        fi
    fi
    
    # Method 3: Use backup directory listing as last resort
    if [[ -z "$LATEST_BACKUP_ID" ]]; then
        log_info "Default format method failed, trying backup directory listing..."
        log_command "ls -1 \"$BACKUP_DIR/backups/$INSTANCE_NAME\" | grep -E '^[A-Z0-9]+$' | sort -r | head -1"
        backup_dirs=$(ls -1 "$BACKUP_DIR/backups/$INSTANCE_NAME" 2>/dev/null | grep -E '^[A-Z0-9]+$' | sort -r | head -1)
        if [[ -n "$backup_dirs" ]]; then
            LATEST_BACKUP_ID="$backup_dirs"
            log_info "Successfully got backup ID using directory listing: $LATEST_BACKUP_ID"
        fi
    fi
    
    if [[ -n "$LATEST_BACKUP_ID" ]]; then
        log_info "Latest backup ID: $LATEST_BACKUP_ID"
        
        # Cleanup expired backups using correct pg_probackup syntax
        log_info "Starting cleanup of expired backups (retain $RETENTION_DAYS days)..."
        log_command "pg_probackup delete -B \"$BACKUP_DIR\" --instance \"$INSTANCE_NAME\" --delete-expired --retention-window=\"$RETENTION_DAYS\" >> \"$LOG_FILE\" 2>&1"
        if pg_probackup delete -B "$BACKUP_DIR" --instance "$INSTANCE_NAME" --delete-expired --retention-window="$RETENTION_DAYS" >> "$LOG_FILE" 2>&1; then
            log_success "Expired backup cleanup completed"
        else
            log_warning "Expired backup cleanup failed"
        fi
        
        # Cleanup expired WAL archives
        log_info "Starting cleanup of expired WAL archives (retain $RETENTION_DAYS days)..."
        log_command "pg_probackup delete -B \"$BACKUP_DIR\" --instance \"$INSTANCE_NAME\" --delete-wal --retention-window=\"$RETENTION_DAYS\" >> \"$LOG_FILE\" 2>&1"
        if pg_probackup delete -B "$BACKUP_DIR" --instance "$INSTANCE_NAME" --delete-wal --retention-window="$RETENTION_DAYS" >> "$LOG_FILE" 2>&1; then
            log_success "Expired WAL archive cleanup completed"
        else
            log_warning "Expired WAL archive cleanup failed"
        fi
    else
        log_warning "All methods failed to get backup ID, skipping cleanup"
        log_warning "This may happen if pg_probackup show command fails or output format is unexpected"
        log_warning "Manual cleanup may be required"
    fi
    
else
    log_error "$BACKUP_DESC failed, exit code: $BACKUP_EXIT_CODE"
    log_error "Please check log file: $LOG_FILE"
    log_error "Contact: 18081072613"
    exit 1
fi

# Record end time
BACKUP_END_TIME=$(date +%s)
BACKUP_DURATION=$((BACKUP_END_TIME - BACKUP_START_TIME))

# Show backup statistics - using macOS compatible date formatting
log_info "Backup statistics:"
log_info "  Start time: $(date -r $BACKUP_START_TIME '+%Y-%m-%d %H:%M:%S')"
log_info "  End time: $(date -r $BACKUP_END_TIME '+%Y-%m-%d %H:%M:%S')"
log_info "  Duration: ${BACKUP_DURATION} seconds ($(($BACKUP_DURATION / 60)) minutes)"

# Show backup list - using default format (no --format option)
log_info "Current backup list:"
log_command "pg_probackup show -B \"$BACKUP_DIR\" --instance \"$INSTANCE_NAME\" | tail -10"
pg_probackup show -B "$BACKUP_DIR" --instance "$INSTANCE_NAME" | tail -10

log_success "PostgreSQL backup script execution completed"
exit 0
