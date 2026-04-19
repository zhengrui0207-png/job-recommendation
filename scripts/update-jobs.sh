#!/bin/bash
# Job Recommendation Data Updater
# Runs daily at 6 PM to fetch latest job listings from Boss直聘

set -e

PROJECT_DIR="/Users/zhengrui/.newmax/workspace/job-recommendation"
LOG_FILE="/Users/zhengrui/.newmax/workspace/job-recommendation/scripts/update.log"

echo "=== Job Update Started: $(date) ===" >> "$LOG_FILE"

# Navigate to project directory
cd "$PROJECT_DIR"

# Step 1: Search jobs on Boss using opencli
echo "Searching jobs on Boss..." >> "$LOG_FILE"
opencli boss search "AI产品经理" --location beijing --salary 15000 --experience 1-3 --field job >> "$LOG_FILE" 2>&1 || true

# Step 2: Commit changes if any
if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -m "Update job listings: $(date '+%Y-%m-%d %H:%M')"
    git push origin main
    echo "Changes pushed to GitHub" >> "$LOG_FILE"
else
    echo "No changes to commit" >> "$LOG_FILE"
fi

# Step 3: Deploy to Vercel
cd "$PROJECT_DIR"
vercel --prod >> "$LOG_FILE" 2>&1 || vercel deploy --prod >> "$LOG_FILE" 2>&1 || true

echo "=== Job Update Completed: $(date) ===" >> "$LOG_FILE"
