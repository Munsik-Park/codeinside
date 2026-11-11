#!/usr/bin/env python3
"""ast-grep Screening 규칙으로 후보 목록을 만든다.

사용: python3 scripts/screen/candidates.py <대상 레포 폴더> [-o 출력.json]

- 규칙은 config/ast-grep/sgconfig.yml이 가리키는 rules/ 폴더에서 읽는다.
- 출력은 정렬된 JSON이다. 시각, 절대 경로처럼 실행마다 달라지는 값은 넣지 않는다.
  같은 커밋에서 두 번 돌리면 바이트 단위로 같아야 한다.
- MCP를 거치지 않고 ast-grep CLI를 직접 부른다(docs/plan.md 위험 표).
"""
import argparse
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SGCONFIG = ROOT / "config" / "ast-grep" / "sgconfig.yml"


def run(cmd, cwd):
    return subprocess.run(cmd, cwd=cwd, check=True, capture_output=True, text=True).stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("repo", help="대상 레포 폴더(git 체크아웃)")
    ap.add_argument("-o", "--output", help="출력 파일. 없으면 표준 출력")
    args = ap.parse_args()
    repo = pathlib.Path(args.repo).resolve()

    sha = run(["git", "rev-parse", "HEAD"], repo).strip()
    dirty = run(["git", "status", "--porcelain", "--untracked-files=no"], repo).strip() != ""
    version = run(["ast-grep", "--version"], repo).strip()
    rule_ids = sorted(p.stem for p in (SGCONFIG.parent / "rules").glob("*.yml"))

    # cwd를 레포 루트로 두고 "."을 넘겨 결과 경로가 레포 기준 상대 경로가 되게 한다.
    out = run(["ast-grep", "scan", "--config", str(SGCONFIG), "--json=stream", "."], repo)
    candidates = []
    for line in out.splitlines():
        if not line.strip():
            continue
        m = json.loads(line)
        r = m["range"]
        candidates.append({
            "rule": m["ruleId"],
            "file": m["file"].removeprefix("./"),
            "start": [r["start"]["line"] + 1, r["start"]["column"] + 1],
            "end": [r["end"]["line"] + 1, r["end"]["column"] + 1],
            "text": m["text"].splitlines()[0].strip(),  # 일치한 노드의 첫 줄
        })
    candidates.sort(key=lambda c: (c["file"], c["start"], c["end"], c["rule"]))

    counts = {rid: 0 for rid in rule_ids}
    for c in candidates:
        counts[c["rule"]] = counts.get(c["rule"], 0) + 1

    doc = {
        "tool": version,
        "repo_sha": sha,
        "repo_dirty": dirty,
        "rules": rule_ids,
        "counts": counts,
        "candidates": candidates,
    }
    text = json.dumps(doc, ensure_ascii=False, indent=1, sort_keys=True) + "\n"
    if args.output:
        pathlib.Path(args.output).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
