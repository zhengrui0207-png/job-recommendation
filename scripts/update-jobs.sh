#!/bin/bash
# Job Recommendation Data Updater
# Runs the Python scraper and relies on git push for GitHub Pages deployment.

set -euo pipefail

PROJECT_DIR="/Users/zhengrui/.newmax/workspace/job-recommendation"
LOG_FILE="/Users/zhengrui/.newmax/workspace/job-recommendation/scripts/update.log"
SCRAPER="$PROJECT_DIR/scripts/daily-job-scrape.sh"

echo "=== Job Update Started: $(date) ===" >> "$LOG_FILE"

cd "$PROJECT_DIR"
echo "Running scraper: $SCRAPER" >> "$LOG_FILE"
if python3 "$SCRAPER" >> "$LOG_FILE" 2>&1; then
    echo "Scraper completed successfully" >> "$LOG_FILE"
else
    status=$?
    echo "Scraper exited with status $status" >> "$LOG_FILE"
fi

echo "=== Job Update Completed: $(date) ===" >> "$LOG_FILE"
