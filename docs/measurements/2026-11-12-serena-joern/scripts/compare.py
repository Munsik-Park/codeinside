#!/usr/bin/env python3
"""docs/plan.md 단계 4: Serena 참조 결과와 Joern 호출자 결과를 (파일, 함수) 쌍으로 맞춰 비교한다.

사용:
  python3 compare.py --joern raw/callers-jto-2G.log --serena raw/serena-run1.jsonl \
      --query Q1 --call-index 0 --name record_evidence_entry [--exclude-prefix tests/]

- Joern: callers.sc가 남긴 CALLER(호출하는 함수 fullName)와 CALLSITE(호출 지점 줄) 줄을 읽는다.
  fullName "<파일>:<module>.A.b"는 (파일, "A.b")로, "<파일>:<module>"은 (파일, "<module>")로 바꾼다.
- Serena: find_referencing_symbols 응답. 참조 위치마다 감싸는 심볼(name_path)이 나온다.
  name_path "A/b"는 "A.b"로, File 종류(모듈 수준)는 "<module>"로 바꾼다.
  Serena가 보여 주는 줄 번호는 0부터 세므로 1을 더한다.
  참조 줄을 보고 import / call(이름 바로 뒤에 "(") / other로 나눈다. 비교에는 call만 쓴다.
- Joern 그래프는 최상위 tests/를 빼고 만들었으므로(3단계) Serena 쪽에서도 같은 접두어를 뺀다.
출력: 정렬된 JSON(표준 출력).
"""
import argparse
import json
import re


def joern_pairs(path, query):
    callers, sites = set(), []
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if line.startswith(f"CALLER {query}\t"):
            callers.add(line.split("\t", 1)[1])
        elif line.startswith(f"CALLSITE {query}\t"):
            _, f, ln, m, code = line.split("\t", 4)
            sites.append({"file": f, "line": int(ln), "caller": m, "code": code})
    def split(full):
        f, rest = full.split(":", 1)
        if rest == "<module>":
            return (f, "<module>")
        return (f, rest.removeprefix("<module>."))
    return {split(c): c for c in callers}, sites


REF_LINE = re.compile(r"^\s*>\s*(\d+):(.*)$")


def serena_refs(path, call_index, name):
    calls = [json.loads(l) for l in open(path, encoding="utf-8") if '"call"' in l]
    res = json.loads(calls[call_index]["text"])
    refs = []
    for f, kinds in res.items():
        for kind, entries in kinds.items():
            for e in entries:
                m = next((REF_LINE.match(x) for x in e["content_around_reference"].splitlines() if REF_LINE.match(x)), None)
                ln, code = (int(m.group(1)) + 1, m.group(2)) if m else (-1, "")
                stripped = code.strip()
                if stripped.startswith(("from ", "import ")) or re.search(r"\bimport\b", stripped) and name in stripped and "(" not in stripped:
                    usage = "import"
                elif re.search(rf"\b{re.escape(name)}\s*\(", code) or stripped.endswith(f"{name}("):
                    usage = "call"
                else:
                    usage = "other"
                func = "<module>" if kind == "File" else e["name_path"].replace("/", ".")
                refs.append({"file": f, "func": func, "kind": kind, "line": ln, "usage": usage, "code": stripped})
    return refs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--joern", required=True)
    ap.add_argument("--serena", required=True)
    ap.add_argument("--query", required=True)
    ap.add_argument("--call-index", type=int, required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--exclude-prefix", default="tests/")
    a = ap.parse_args()

    jmap, jsites = joern_pairs(a.joern, a.query)
    refs_all = serena_refs(a.serena, a.call_index, a.name)
    refs = [r for r in refs_all if not r["file"].startswith(a.exclude_prefix)]
    s_call = {(r["file"], r["func"]) for r in refs if r["usage"] == "call"}
    s_any = {(r["file"], r["func"]) for r in refs}
    j = set(jmap)

    def fmt(pairs):
        return [f"{f}::{fn}" for f, fn in sorted(pairs)]

    usage_counts = {}
    for r in refs:
        usage_counts[r["usage"]] = usage_counts.get(r["usage"], 0) + 1
    out = {
        "query": a.query,
        "name": a.name,
        "joern": {"callers": len(j), "callsites": len(jsites)},
        "serena": {
            "references_all": len(refs_all),
            "references_excluding_prefix": len(refs),
            "excluded_prefix": a.exclude_prefix,
            "usage_counts": dict(sorted(usage_counts.items())),
            "call_pairs": len(s_call),
            "any_pairs": len(s_any),
        },
        "both": len(j & s_call),
        "joern_only": fmt(j - s_call),
        "serena_only": fmt(s_call - j),
        "serena_non_call_refs": sorted(
            (f"{r['file']}:{r['line']}::{r['func']}::{r['usage']}::{r['code']}" for r in refs if r["usage"] != "call")
        ),
        "joern_only_callsites": sorted(
            (f"{s['file']}:{s['line']}::{s['code']}" for s in jsites
             if any(jmap[p] == s["caller"] for p in (j - s_call))),
        ),
        "serena_only_refs": sorted(
            (f"{r['file']}:{r['line']}::{r['func']}::{r['code']}" for r in refs
             if r["usage"] == "call" and (r["file"], r["func"]) in (s_call - j))
        ),
    }
    print(json.dumps(out, ensure_ascii=False, indent=1, sort_keys=True))


if __name__ == "__main__":
    main()
