#!/usr/bin/env python3
"""
Boss直聘职位抓取脚本
- 搜索职位列表后逐条补抓 JD 详情
- 落盘 jobs.js + job_data.json
- 抓取失败时保留上一版线上数据，避免页面被清空
"""

import json
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path

KEYWORDS = [
    "AI产品经理 社招",
    "AI产品 社招",
    "策略产品经理 社招",
    "增长产品经理 社招",
    "商业化产品经理 社招",
    "策略运营 社招",
    "AI运营 社招",
    "数据产品经理 社招",
]
CITY_TARGETS = {"北京": 24}
MAX_TOTAL = 24
SEARCH_LIMIT = 12
SEARCH_TIMEOUT = 90
DETAIL_TIMEOUT = 90

PROJECT_DIR = "/Users/zhengrui/.newmax/workspace/job-recommendation"
JOBS_FILE = os.path.join(PROJECT_DIR, "jobs.js")
JOB_JSON_FILE = os.path.join(PROJECT_DIR, "scripts", "job_data.json")
LOG_FILE = os.path.join(PROJECT_DIR, "scripts", "job-scrape.log")
RAW_OUTPUT_DIR = os.path.join(PROJECT_DIR, "scripts", "raw_opencli")

SKILL_VOCABULARY = [
    "AI", "Agent", "RAG", "Prompt", "Prompt工程", "大模型", "LLM", "A/B", "SQL",
    "数据分析", "产品策略", "需求分析", "商业化", "工作流", "多模态", "增长实验",
    "用户研究", "项目管理", "SaaS", "B端产品", "C端产品", "自动化", "机器人"
]

blocking_issues = set()


def log(msg):
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} - {msg}\n")
    print(msg)


def sanitize_name(value):
    return re.sub(r"[^0-9A-Za-z\u4e00-\u9fff_-]+", "_", value)


def normalize_text(value):
    return re.sub(r"\s+", " ", str(value or "")).strip()


def preview_output(output, limit=400):
    compact = normalize_text(output)
    return compact if len(compact) <= limit else compact[:limit] + "..."


def unique_list(items):
    return list(dict.fromkeys([item for item in items if item]))


def save_raw_output(label, output):
    Path(RAW_OUTPUT_DIR).mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    filename = f"{timestamp}-{sanitize_name(label)}.log"
    path = os.path.join(RAW_OUTPUT_DIR, filename)
    with open(path, "w", encoding="utf-8") as f:
        f.write(output)
    return path


def classify_opencli_issue(output):
    lowered = output.lower()
    if "login" in lowered or "登录" in output or "auth" in lowered:
        return "login"
    if "daemon" in lowered or "extension" in lowered or "not connected" in lowered:
        return "daemon"
    return ""


def extract_json_payload(output):
    decoder = json.JSONDecoder()
    for index, char in enumerate(output):
        if char not in "[{":
            continue
        try:
            parsed, _ = decoder.raw_decode(output[index:])
        except json.JSONDecodeError:
            continue
        return parsed
    return None


def split_skill_text(value):
    return unique_list(
        [part.strip() for part in re.split(r"[,，、|/；;\n]", normalize_text(value)) if part.strip()]
    )


def parse_salary_floor_k(salary):
    text = normalize_text(salary).upper()
    if not text or "面议" in text:
        return None
    range_match = re.search(r"(\d+)\s*-\s*(\d+)\s*K", text)
    if range_match:
        return int(range_match.group(1))
    above_match = re.search(r"(\d+)\s*K以上", text)
    if above_match:
        return int(above_match.group(1))
    single_match = re.search(r"(\d+)\s*K", text)
    if single_match:
        return int(single_match.group(1))
    return None


def meets_salary_requirement(job):
    floor = parse_salary_floor_k(job.get("salary", ""))
    return floor is not None and floor >= 15


def is_social_hire_job(job):
    title = normalize_text(job.get("name")).lower()
    experience = normalize_text(job.get("experience")).lower()

    if any(keyword in title for keyword in ["校招", "应届", "实习", "管培"]):
        return False
    if "在校" in experience or "应届" in experience:
        return False
    if "5-10" in experience or "10年" in experience:
        return False

    return True


def run_opencli(cmd, label, timeout):
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        output = (result.stdout or "") + (result.stderr or "")
        raw_output_file = save_raw_output(label, output)
        issue = classify_opencli_issue(output)
        if issue:
            blocking_issues.add(issue)
        return result.returncode, output, raw_output_file, issue
    except Exception as exc:
        log(f"执行失败 {label}: {exc}")
        return 1, str(exc), "", ""


def normalize_search_job(job):
    return {
        "name": job.get("name", ""),
        "salary": job.get("salary", ""),
        "company": job.get("company", ""),
        "area": job.get("area", ""),
        "experience": job.get("experience", ""),
        "degree": job.get("degree", ""),
        "skills": job.get("skills", ""),
        "boss": job.get("boss", ""),
        "security_id": job.get("security_id", ""),
        "url": job.get("url", "")
    }


def infer_skill_keywords(job):
    text = " ".join([
        normalize_text(job.get("name")),
        normalize_text(job.get("skills")),
        normalize_text(job.get("description")),
        normalize_text(job.get("welfare")),
        normalize_text(job.get("industry"))
    ]).lower()
    raw_skills = split_skill_text(job.get("skills", ""))
    matched = [keyword for keyword in SKILL_VOCABULARY if keyword.lower() in text]
    return unique_list(raw_skills + matched)[:6]


def build_jd_summary(job):
    description = normalize_text(job.get("description"))
    summary = ""

    if description:
        sentences = [
            normalize_text(sentence)
            for sentence in re.split(r"[。；;！!?]", description)
            if normalize_text(sentence)
        ]
        summary = "。".join(sentences[:3])
        if summary and not summary.endswith("。"):
            summary += "。"

    if len(summary) < 100:
        fallback_parts = [
            f"{normalize_text(job.get('company')) or '该公司'}发布的{normalize_text(job.get('name')) or '该岗位'}，当前薪资区间为{normalize_text(job.get('salary')) or '面议'}，工作地点在{normalize_text(job.get('area') or job.get('city')) or '目标城市'}。",
            f"岗位更看重{('、'.join(job.get('skillKeywords', [])) or normalize_text(job.get('skills')) or '产品策略、需求分析、跨团队协作')}等能力，通常会考察候选人对业务场景的理解、数据判断和项目推动能力。",
            f"{normalize_text(job.get('experience')) and f'经验要求偏向{normalize_text(job.get('experience'))}' or '经验字段仍待补全'}{normalize_text(job.get('degree')) and f'，学历要求为{normalize_text(job.get('degree'))}' or ''}。{normalize_text(job.get('size')) and f'公司规模约{normalize_text(job.get('size'))}' or '当前公司规模字段缺失'}{normalize_text(job.get('finance')) and f'，发展阶段为{normalize_text(job.get('finance'))}' or ''}。"
        ]
        summary = "".join(fallback_parts)

    if len(summary) < 110:
        summary += " 目前这条职位还缺少完整 JD 原文，建议登录 Boss 后重新抓取详情，这样才能补齐职责描述、技能栈、业务目标和福利信息，后续的匹配度评估也会更稳定。"

    return summary


def build_highlight_points(job):
    rows = []
    skill_keywords = job.get("skillKeywords", [])
    if skill_keywords:
        rows.append(f"技能重点：{' / '.join(skill_keywords[:4])}")
    if normalize_text(job.get("skills")):
        rows.append(f"原始关键词：{normalize_text(job.get('skills'))}")

    description = normalize_text(job.get("description"))
    if description:
        sentences = [
            normalize_text(sentence)
            for sentence in re.split(r"[。；;！!?]", description)
            if normalize_text(sentence)
        ]
        for sentence in sentences:
            if len(sentence) >= 12 and re.search(r"负责|要求|熟悉|经验|能力|策略|分析|产品|增长|协同|落地", sentence):
                rows.append(sentence)
            if len(rows) >= 4:
                break

    if len(rows) < 3:
        rows.append(
            f"硬性条件：{normalize_text(job.get('experience')) or '经验待补充'} · "
            f"{normalize_text(job.get('degree')) or '学历不限'} · "
            f"{normalize_text(job.get('area') or job.get('city')) or '城市待补充'}"
        )

    if len(rows) < 4 and normalize_text(job.get("welfare")):
        rows.append(f"福利亮点：{normalize_text(job.get('welfare'))}")

    return unique_list(rows)[:4]


def merge_job_data(search_job, detail_job):
    skill_text = unique_list(
        split_skill_text(search_job.get("skills", "")) +
        split_skill_text(detail_job.get("skills", ""))
    )

    merged = {
        **search_job,
        "name": detail_job.get("name") or search_job.get("name", ""),
        "salary": detail_job.get("salary") or search_job.get("salary", ""),
        "experience": detail_job.get("experience") or search_job.get("experience", ""),
        "degree": detail_job.get("degree") or search_job.get("degree", ""),
        "company": detail_job.get("company") or search_job.get("company", ""),
        "area": search_job.get("area") or " · ".join(filter(None, [detail_job.get("city"), detail_job.get("district")])),
        "city": detail_job.get("city", ""),
        "district": detail_job.get("district", ""),
        "address": detail_job.get("address", ""),
        "description": detail_job.get("description", ""),
        "welfare": detail_job.get("welfare", ""),
        "skills": "、".join(skill_text),
        "boss": detail_job.get("boss_name") or search_job.get("boss", ""),
        "bossTitle": detail_job.get("boss_title", ""),
        "activeTime": detail_job.get("active_time", ""),
        "industry": detail_job.get("industry", ""),
        "size": detail_job.get("scale", ""),
        "finance": detail_job.get("stage", ""),
        "url": detail_job.get("url") or search_job.get("url", "")
    }
    merged["skillKeywords"] = infer_skill_keywords(merged)
    merged["jdSummary"] = build_jd_summary(merged)
    merged["highlightPoints"] = build_highlight_points(merged)
    merged["dataSource"] = "detail" if merged.get("description") else "search"
    return merged


def scrape_jobs(keyword, city):
    cmd = [
        "opencli", "boss", "search", keyword,
        "--city", city,
        "--limit", str(SEARCH_LIMIT),
        "--format", "json"
    ]

    returncode, output, raw_output_file, issue = run_opencli(
        cmd, f"search-{city}-{keyword}", SEARCH_TIMEOUT
    )

    if issue == "login":
        log(f"需要登录 Boss 才能抓取搜索结果：{keyword}@{city} | 详情: {raw_output_file}")
        return []
    if issue == "daemon":
        log(f"opencli daemon/extension 未就绪：{keyword}@{city} | 详情: {raw_output_file}")
        return []
    if returncode != 0:
        log(f"抓取命令失败 {keyword}@{city}: exit={returncode} | 输出摘要: {preview_output(output)} | 详情: {raw_output_file}")
        return []

    payload = extract_json_payload(output)
    if payload is None:
        log(f"未解析到搜索结果 {keyword}@{city} | 输出摘要: {preview_output(output)} | 详情: {raw_output_file}")
        return []

    jobs = payload if isinstance(payload, list) else [payload]
    normalized = [normalize_search_job(job) for job in jobs if isinstance(job, dict)]
    return [job for job in normalized if meets_salary_requirement(job) and is_social_hire_job(job)]


def fetch_job_detail(job):
    security_id = normalize_text(job.get("security_id"))
    if not security_id:
        return {}

    cmd = ["opencli", "boss", "detail", "--format", "json", "--", security_id]
    returncode, output, raw_output_file, issue = run_opencli(
        cmd, f"detail-{security_id[:18]}", DETAIL_TIMEOUT
    )

    if issue == "login":
        log(f"需要登录 Boss 才能抓取职位详情：{job.get('company')} - {job.get('name')} | 详情: {raw_output_file}")
        return {}
    if issue == "daemon":
        log(f"opencli daemon/extension 未就绪，无法抓取职位详情：{job.get('company')} - {job.get('name')} | 详情: {raw_output_file}")
        return {}
    if returncode != 0:
        log(f"抓取职位详情失败 {job.get('company')} - {job.get('name')}: exit={returncode} | 输出摘要: {preview_output(output)} | 详情: {raw_output_file}")
        return {}

    payload = extract_json_payload(output)
    if payload is None:
        log(f"未解析到职位详情 {job.get('company')} - {job.get('name')} | 输出摘要: {preview_output(output)} | 详情: {raw_output_file}")
        return {}

    if isinstance(payload, list) and payload and isinstance(payload[0], dict):
        return payload[0]
    if isinstance(payload, dict):
        return payload
    return {}


def write_jobs_files(all_jobs):
    updated_at = datetime.now().strftime("%Y-%m-%d %H:%M")
    with open(JOB_JSON_FILE, "w", encoding="utf-8") as f:
        json.dump(all_jobs, f, ensure_ascii=False, indent=2)
        f.write("\n")

    with open(JOBS_FILE, "w", encoding="utf-8") as f:
        f.write("// 职位数据 - 由脚本自动生成\n")
        f.write(f"// 最后更新: {updated_at}\n")
        f.write(f"const scrapedJobs = {json.dumps(all_jobs, ensure_ascii=False, indent=2)};\n")
        f.write(f"\nconst lastUpdated = \"{updated_at}\";\n")


def log_blocking_issue_summary():
    if "daemon" in blocking_issues:
        log("检测到 opencli daemon / 浏览器扩展未连接。请先执行 opencli doctor，并确保浏览器扩展在线。")
    if "login" in blocking_issues:
        log("检测到 Boss 登录态缺失。请先打开 Boss 页面完成登录，再重新执行抓取。")


def main():
    log("=" * 50)
    log("开始抓取 Boss 直聘职位数据")
    log("=" * 50)

    all_jobs = []
    seen_keys = set()

    for city, target in CITY_TARGETS.items():
        if len(all_jobs) >= MAX_TOTAL:
            break

        log(f"\n--- 抓取 {city}（目标: {target} 条，当前已抓: {len(all_jobs)} 条）---")

        for keyword in KEYWORDS:
            if len(all_jobs) >= MAX_TOTAL:
                break

            log(f"  搜索: {keyword}@{city}")
            jobs = scrape_jobs(keyword, city)
            log(f"    搜索返回 {len(jobs)} 条")

            for search_job in jobs:
                key = f"{search_job.get('company', '')}-{search_job.get('name', '')}"
                if key in seen_keys or key == "-":
                    continue

                detail_job = fetch_job_detail(search_job)
                merged_job = merge_job_data(search_job, detail_job)
                if not is_social_hire_job(merged_job):
                    log(f"    跳过非社招岗位: {merged_job.get('company', '')} - {merged_job.get('name', '')}")
                    continue
                seen_keys.add(key)
                all_jobs.append(merged_job)

                detail_status = "详情已补全" if merged_job.get("dataSource") == "detail" else "仅基础信息"
                log(f"    ✓ 新增: {merged_job.get('company', '')} - {merged_job.get('name', '')} [{detail_status}]")

                if len(all_jobs) >= MAX_TOTAL:
                    break

    log(f"\n共抓取到 {len(all_jobs)} 条职位（去重后）")
    log_blocking_issue_summary()

    if not all_jobs:
        log("本次抓取结果为空，保留现有 jobs.js，不覆盖线上页面数据")
        log("=" * 50)
        log("抓取完成（未更新页面数据）")
        log("=" * 50)
        return 1

    write_jobs_files(all_jobs)
    log(f"已保存到 {JOBS_FILE}")

    os.chdir(PROJECT_DIR)
    log("\n提交到 GitHub...")

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
        log("✓ GitHub 推送成功")
    else:
        log(f"✗ GitHub 推送失败: {result.stderr}")

    log("=" * 50)
    log("抓取完成!")
    log("=" * 50)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
