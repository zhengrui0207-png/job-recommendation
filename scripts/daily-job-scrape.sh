#!/bin/bash
# Daily Job Scraper - Runs at 10 AM via launchd
# Scrapes jobs from Boss直聘 and updates the website

set -e

PROJECT_DIR="/Users/zhengrui/.newmax/workspace/job-recommendation"
LOG_FILE="$PROJECT_DIR/scripts/job-scrape.log"
DATA_FILE="$PROJECT_DIR/scripts/job_data.json"

echo "=== Job Scrape Started: $(date) ===" >> "$LOG_FILE"

cd "$PROJECT_DIR"

# Check if Chrome extension is available by testing opencli
echo "Checking opencli availability..." >> "$LOG_FILE"
if ! command -v opencli &> /dev/null; then
    echo "Error: opencli not found. Install it first." >> "$LOG_FILE"
    exit 1
fi

# Try to scrape jobs from Boss
# Note: This requires Chrome browser with opencli extension enabled
echo "Attempting to scrape jobs from Boss直聘..." >> "$LOG_FILE"

# Create a temporary script to handle the scraping
TEMP_SCRIPT=$(mktemp)

cat > "$TEMP_SCRIPT" << 'SCRIPT_EOF'
#!/bin/bash
# Use opencli to search jobs on Boss
opencli boss search "AI产品经理" --location beijing --salary 15000 --experience 1-3 --field job 2>&1 || echo "BOSS_SCRAPE_FAILED"
SCRIPT_EOF

chmod +x "$TEMP_SCRIPT"

# Run the scraping with timeout
SCRAPE_OUTPUT=$(timeout 60 "$TEMP_SCRIPT" 2>&1) || true
rm -f "$TEMP_SCRIPT"

if echo "$SCRAPE_OUTPUT" | grep -q "BOSS_SCRAPE_FAILED"; then
    echo "Boss直聘 scraping failed - Chrome extension may not be enabled" >> "$LOG_FILE"
    echo "Please ensure Chrome is running with opencli extension enabled" >> "$LOG_FILE"

    # Still push existing data to GitHub (may trigger Vercel redeploy)
    if [ -n "$(git status --porcelain)" ]; then
        git add -A
        git commit -m "Daily job data update (scraping unavailable): $(date '+%Y-%m-%d %H:%M')" >> "$LOG_FILE" 2>&1 || true
    fi
else
    echo "Scraping completed, parsing results..." >> "$LOG_FILE"

    # Parse the output and update job data
    # The output format from opencli boss is typically JSON or structured text

    # For now, save the raw output as job data
    echo "$SCRAPE_OUTPUT" > "$DATA_FILE"

    # Update the HTML with new job data
    # This is a simplified version - actual implementation depends on output format
    python3 << 'PYEOF' 2>> "$LOG_FILE" || true
import json
import re
import os

data_file = "/Users/zhengrui/.newmax/workspace/job-recommendation/scripts/job_data.json"
html_file = "/Users/zhengrui/.newmax/workspace/job-recommendation/index.html"

if os.path.exists(data_file):
    with open(data_file, 'r', encoding='utf-8') as f:
        raw_data = f.read()

    # Try to parse job listings from the output
    # This is a placeholder - actual parsing depends on opencli boss output format
    jobs = []

    # Look for job patterns in the output
    # Pattern: company name, job title, salary, location
    lines = raw_data.strip().split('\n')
    for line in lines:
        if any(keyword in line for keyword in ['K', 'k', '薪', '岗位', '公司']):
            jobs.append(line.strip())

    # Save parsed jobs to a JS file that can be included in HTML
    js_file = "/Users/zhengrui/.newmax/workspace/job-recommendation/scripts/parsed_jobs.js"
    with open(js_file, 'w', encoding='utf-8') as f:
        f.write(f"// Auto-generated job data - {__import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
        f.write(f"const scrapedJobs = {json.dumps(jobs, ensure_ascii=False)};\n")
        f.write(f"const lastUpdated = '{__import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M')}';\n")

    print(f"Parsed {len(jobs)} jobs")
PYEOF

    # Commit and push changes
    git add -A >> "$LOG_FILE" 2>&1
    git commit -m "Daily job data update: $(date '+%Y-%m-%d %H:%M')" >> "$LOG_FILE" 2>&1 || true
fi

# Push to GitHub (triggers Vercel redeployment)
git push origin main >> "$LOG_FILE" 2>&1 || true

echo "=== Job Scrape Completed: $(date) ===" >> "$LOG_FILE"
