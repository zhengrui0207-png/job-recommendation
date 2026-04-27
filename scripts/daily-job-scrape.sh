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
from pathlib import Path

# 配置
KEYWORDS = ["AI产品经理", "策略运营", "用户增长", "产品经理", "产品运营", "AI运营", "内容运营"]
CITY_TARGETS = {"北京": 35, "杭州": 10, "深圳": 10, "上海": 10}
MAX_TOTAL = 50

PROJECT_DIR = "/Users/zhengrui/.newmax/workspace/job-recommendation"
JOBS_FILE = os.path.join(PROJECT_DIR, "jobs.js")
JOB_JSON_FILE = os.path.join(PROJECT_DIR, "scripts", "job_data.json")
LOG_FILE = os.path.join(PROJECT_DIR, "scripts", "job-scrape.log")
RAW_OUTPUT_DIR = os.path.join(PROJECT_DIR, "scripts", "raw_opencli")

def log(msg):
    with open(LOG_FILE, 'a', encoding='utf-8') as f:
        f.write(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} - {msg}\n")
    print(msg)

def sanitize_name(value):
    return re.sub(r'[^0-9A-Za-z\u4e00-\u9fff_-]+', '_', value)

def preview_output(output, limit=400):
    compact = re.sub(r'\s+', ' ', output).strip()
    if len(compact) <= limit:
        return compact
    return compact[:limit] + '...'

def save_raw_output(keyword, city, output):
    Path(RAW_OUTPUT_DIR).mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    filename = f"{timestamp}-{sanitize_name(city)}-{sanitize_name(keyword)}.log"
    path = os.path.join(RAW_OUTPUT_DIR, filename)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(output)
    return path

def extract_json_array(output):
    decoder = json.JSONDecoder()
    for index, char in enumerate(output):
        if char != '[':
            continue
        try:
            parsed, _ = decoder.raw_decode(output[index:])
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, list):
            return parsed
    return []

def parse_salary_floor_k(salary):
    if not salary:
        return None
    text = salary.upper()
    if '面议' in text:
        return None
    range_match = re.search(r'(\d+)\s*-\s*(\d+)\s*K', text)
    if range_match:
        return int(range_match.group(1))
    above_match = re.search(r'(\d+)\s*K以上', text)
    if above_match:
        return int(above_match.group(1))
    single_match = re.search(r'(\d+)\s*K', text)
    if single_match:
        return int(single_match.group(1))
    return None

def meets_salary_requirement(job):
    floor = parse_salary_floor_k(job.get('salary', ''))
    return floor is not None and floor >= 15

def write_jobs_files(all_jobs):
    updated_at = datetime.now().strftime('%Y-%m-%d %H:%M')
    with open(JOB_JSON_FILE, 'w', encoding='utf-8') as f:
        json.dump(all_jobs, f, ensure_ascii=False, indent=2)
        f.write('\n')

    with open(JOBS_FILE, 'w', encoding='utf-8') as f:
        f.write("// 职位数据 - 由脚本自动生成\n")
        f.write(f"// 最后更新: {updated_at}\n")
        f.write(f"const scrapedJobs = {json.dumps(all_jobs, ensure_ascii=False, indent=2)};\n")
        f.write(f"\nconst lastUpdated = \"{updated_at}\";\n")

def scrape_jobs(keyword, city):
    """使用opencli抓取职位"""
    cmd = [
        "opencli", "boss", "search", keyword,
        "--city", city,
        "--experience", "1-3年",
        "--limit", "20",
        "--format", "json"
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=90)
        output = (result.stdout or '') + (result.stderr or '')
        raw_output_file = save_raw_output(keyword, city, output)

        # 检查是否需要登录
        if "login" in output.lower() or "登录" in output or "auth" in output.lower():
            log(f"需要登录: {keyword}@{city} | 详情: {raw_output_file}")
            return []

        if result.returncode != 0:
            log(f"抓取命令失败 {keyword}@{city}: exit={result.returncode} | 输出摘要: {preview_output(output)} | 详情: {raw_output_file}")
            return []

        jobs = extract_json_array(output)
        if jobs:
            jobs = [job for job in jobs if meets_salary_requirement(job)]
            return jobs

        log(f"未解析到职位数据 {keyword}@{city} | 输出摘要: {preview_output(output)} | 详情: {raw_output_file}")
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

    if not all_jobs:
        log("本次抓取结果为空，保留现有 jobs.js，不覆盖线上页面数据")
        log("=" * 50)
        log("抓取完成（未更新页面数据）")
        log("=" * 50)
        return 1

    write_jobs_files(all_jobs)

    log(f"已保存到 {JOBS_FILE}")

    # 自动提交到GitHub
    os.chdir(PROJECT_DIR)
    log("\n提交到GitHub...")

    status = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True)
    if not status.stdout.strip():
        log("无文件变更，跳过 Git 提交")
        log("=" * 50)
        log("抓取完成!")
        log("=" * 50)
        return 0

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
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
