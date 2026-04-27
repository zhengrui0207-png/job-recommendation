#!/usr/bin/env python3
"""
Boss直聘职位抓取脚本
- 薪资15k以上，不限上限
- 多关键词：北京优先35条，再杭州/深圳/上海
- 每次最多50条
"""

import subprocess
import json
import re
import os
from datetime import datetime

# 配置
KEYWORDS = ["AI产品经理", "策略运营", "用户增长", "产品经理", "产品运营", "AI运营", "内容运营"]
CITY_TARGETS = {"北京": 35, "杭州": 10, "深圳": 10, "上海": 10}
MAX_TOTAL = 50

PROJECT_DIR = "/Users/zhengrui/.newmax/workspace/job-recommendation"
JOBS_FILE = os.path.join(PROJECT_DIR, "jobs.js")
LOG_FILE = os.path.join(PROJECT_DIR, "scripts", "job-scrape.log")

def log(msg):
    with open(LOG_FILE, 'a', encoding='utf-8') as f:
        f.write(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} - {msg}\n")
    print(msg)

def scrape_jobs(keyword, city):
    """使用opencli抓取职位"""
    cmd = [
        "opencli", "boss", "search", keyword,
        "--city", city,
        "--experience", "1-3年",
        "--salary", "15K以上",
        "--limit", "20",
        "--format", "json"
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr

        # 检查是否需要登录
        if "login" in output.lower() or "登录" in output or "auth" in output.lower():
            log(f"需要登录: {keyword}@{city}")
            return []

        # 提取JSON数组
        match = re.search(r'\[\s*\{.*\}\s*\]', output, re.DOTALL)
        if match:
            return json.loads(match.group())
        return []

    except Exception as e:
        log(f"抓取失败 {keyword}@{city}: {e}")
        return []

def main():
    log("=" * 50)
    log("开始抓取Boss直聘职位数据")
    log("=" * 50)

    all_jobs = []
    seen_keys = set()  # 去重：company+jobname

    # 按城市和关键词抓取
    for city, target in CITY_TARGETS.items():
        if len(all_jobs) >= MAX_TOTAL:
            break

        remaining = MAX_TOTAL - len(all_jobs)
        log(f"\n--- 抓取 {city} (目标: {target}条, 剩余: {remaining}条) ---")

        for keyword in KEYWORDS:
            if len(all_jobs) >= MAX_TOTAL:
                break

            log(f"  抓取: {keyword}@{city}")
            jobs = scrape_jobs(keyword, city)
            log(f"    返回 {len(jobs)} 条")

            for job in jobs:
                key = f"{job.get('company', '')}-{job.get('name', '')}"
                if key not in seen_keys and key != '-':
                    seen_keys.add(key)
                    all_jobs.append(job)
                    log(f"    ✓ 新增: {job.get('company', '')} - {job.get('name', '')}")

                    if len(all_jobs) >= MAX_TOTAL:
                        break

    log(f"\n共抓取到 {len(all_jobs)} 条职位（去重后）")

    # 生成jobs.js
    with open(JOBS_FILE, 'w', encoding='utf-8') as f:
        f.write(f"// 职位数据 - 由脚本自动生成\n")
        f.write(f"// 最后更新: {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
        f.write(f"const scrapedJobs = {json.dumps(all_jobs, ensure_ascii=False, indent=2)};\n")
        f.write(f"\nconst lastUpdated = \"{datetime.now().strftime('%Y-%m-%d %H:%M')}\";\n")

    log(f"已保存到 {JOBS_FILE}")

    # 自动提交到GitHub
    os.chdir(PROJECT_DIR)
    log("\n提交到GitHub...")

    subprocess.run(["git", "add", "-A"], capture_output=True)
    subprocess.run(["git", "commit", "-m", f"Job data update: {datetime.now().strftime('%Y-%m-%d %H:%M')}"], capture_output=True)
    result = subprocess.run(["git", "push", "origin", "main"], capture_output=True, text=True)

    if result.returncode == 0:
        log("✓ GitHub推送成功")
    else:
        log(f"✗ GitHub推送失败: {result.stderr}")

    log("=" * 50)
    log("抓取完成!")
    log("=" * 50)

if __name__ == "__main__":
    main()