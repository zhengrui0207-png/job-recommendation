#!/bin/bash
# Daily Job Scraper - Runs at 10 AM via launchd
# Scrapes jobs from Boss直聘 and updates the website

set -e

PROJECT_DIR="/Users/zhengrui/.newmax/workspace/job-recommendation"
LOG_FILE="$PROJECT_DIR/scripts/job-scrape.log"
DATA_FILE="$PROJECT_DIR/scripts/job_data.json"
JOBS_FILE="$PROJECT_DIR/jobs.js"

echo "=== Job Scrape Started: $(date) ===" >> "$LOG_FILE"

cd "$PROJECT_DIR"

# Check if opencli is available
if ! command -v opencli &> /dev/null; then
    echo "Error: opencli not found" >> "$LOG_FILE"
    exit 1
fi

echo "Scraping jobs from Boss直聘..." >> "$LOG_FILE"

# Scrape jobs with corrected parameters
SCRAPE_OUTPUT=$(opencli boss search "AI产品经理" --city "北京" --experience "1-3年" --salary "15-20K" --limit 20 --format json 2>&1)

# Check if scraping was successful
if echo "$SCRAPE_OUTPUT" | grep -q "user"; then
    echo "Boss直聘 requires login. Please ensure you're logged in." >> "$LOG_FILE"
    exit 1
fi

# Save raw JSON data
echo "$SCRAPE_OUTPUT" > "$DATA_FILE"

# Parse and generate jobs.js
python3 << PYEOF >> "$LOG_FILE" 2>&1
import json
import re
from datetime import datetime

data_file = "/Users/zhengrui/.newmax/workspace/job-recommendation/scripts/job_data.json"
jobs_file = "/Users/zhengrui/.newmax/workspace/job-recommendation/jobs.js"

try:
    with open(data_file, 'r', encoding='utf-8') as f:
        raw_content = f.read()

    # Extract JSON part (remove any trailing text like "Update available...")
    json_match = re.search(r'\[\s*\{.*\}\s*\]', raw_content, re.DOTALL)
    if json_match:
        jobs = json.loads(json_match.group())

        # Generate jobs.js
        with open(jobs_file, 'w', encoding='utf-8') as f:
            f.write(f"// 职位数据 - 由脚本自动生成\n")
            f.write(f"// 最后更新: {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
            f.write(f"const scrapedJobs = {json.dumps(jobs, ensure_ascii=False, indent=2)};\n")
            f.write(f"\nconst lastUpdated = \"{datetime.now().strftime('%Y-%m-%d %H:%M')}\";\n")

        print(f"Successfully parsed {len(jobs)} jobs")
    else:
        print("No valid JSON found in output")
except Exception as e:
    print(f"Error: {e}")
PYEOF

# Commit and push changes
git add -A >> "$LOG_FILE" 2>&1
git commit -m "Daily job data update: $(date '+%Y-%m-%d %H:%M')" >> "$LOG_FILE" 2>&1 || true
git push origin main >> "$LOG_FILE" 2>&1 || true

echo "=== Job Scrape Completed: $(date) ===" >> "$LOG_FILE"
echo "Done! $JOBS_FILE generated and pushed to GitHub."
