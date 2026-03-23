#!/usr/bin/env python3
import argparse
import glob
import json
import os
from collections import Counter


def parse_args():
    parser = argparse.ArgumentParser(
        description="Summarize producer capture sessions before training."
    )
    parser.add_argument(
        "--sessions-dir",
        required=True,
        help="Directory containing exported producer session .json files",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit machine-readable JSON instead of text output",
    )
    return parser.parse_args()


def _safe_session_id(session, path):
    return str(session.get("session_id") or os.path.basename(path))


def summarize_session(path):
    with open(path, "r", encoding="utf-8") as handle:
        session = json.load(handle)

    prompt_cycles = session.get("prompt_cycles", [])
    if isinstance(prompt_cycles, list) and prompt_cycles:
        ai_steps = 0
        manual_edits = 0
        prompt_cycle_stops = 0
        estimated_action_rows = 0
        completed_prompt_cycles = 0
        prompts = set()

        for cycle in prompt_cycles:
            if not isinstance(cycle, dict):
                continue
            ai_steps += 1
            prompt = str(cycle.get("prompt") or "").strip()
            if prompt:
                prompts.add(prompt)
            resolved_actions = cycle.get("resolved_ai_actions", [])
            if isinstance(resolved_actions, list):
                estimated_action_rows += sum(
                    1 for action in resolved_actions if isinstance(action, dict)
                )
            manual_debug = cycle.get("manual_edits_debug", [])
            if isinstance(manual_debug, list):
                manual_edits += sum(1 for item in manual_debug if isinstance(item, dict))
            status = str(cycle.get("status") or "").strip().lower()
            if status == "complete":
                prompt_cycle_stops += 1
                completed_prompt_cycles += 1

        raw_project_id = str(session.get("project_id") or "").strip()
        raw_project_name = str(session.get("project_name") or "").strip()

        return {
            "path": path,
            "session_id": _safe_session_id(session, path),
            "project_id": raw_project_id,
            "project_name": raw_project_name,
            "has_project_id": bool(raw_project_id),
            "has_project_name": bool(raw_project_name),
            "ai_steps": ai_steps,
            "manual_edits": manual_edits,
            "prompt_cycle_stops": prompt_cycle_stops,
            "completed_prompt_cycles": completed_prompt_cycles,
            "estimated_action_rows": estimated_action_rows,
            "unique_prompts": len(prompts),
            "quality_rating_0_to_5": session.get("quality_rating_0_to_5"),
        }

    events = session.get("events", [])
    if not isinstance(events, list):
        events = []

    ai_steps = 0
    manual_edits = 0
    prompt_cycle_stops = 0
    completed_prompt_cycles = 0
    estimated_action_rows = 0
    prompts = set()

    for event in events:
        if not isinstance(event, dict):
            continue
        event_type = str(event.get("type") or "").strip().lower()
        if event_type == "ai_step":
            ai_steps += 1
            prompt = str(event.get("prompt") or "").strip()
            if prompt:
                prompts.add(prompt)
            resolved_actions = event.get("resolved_actions", [])
            if isinstance(resolved_actions, list):
                estimated_action_rows += sum(
                    1 for action in resolved_actions if isinstance(action, dict)
                )
        elif event_type == "manual_edit":
            manual_edits += 1
        elif event_type == "prompt_cycle_stop":
            prompt_cycle_stops += 1
            completed_prompt_cycles += 1

    raw_project_id = str(session.get("project_id") or "").strip()
    raw_project_name = str(session.get("project_name") or "").strip()

    return {
        "path": path,
        "session_id": _safe_session_id(session, path),
        "project_id": raw_project_id,
        "project_name": raw_project_name,
        "has_project_id": bool(raw_project_id),
        "has_project_name": bool(raw_project_name),
        "ai_steps": ai_steps,
        "manual_edits": manual_edits,
        "prompt_cycle_stops": prompt_cycle_stops,
        "completed_prompt_cycles": completed_prompt_cycles,
        "estimated_action_rows": estimated_action_rows,
        "unique_prompts": len(prompts),
        "quality_rating_0_to_5": session.get("quality_rating_0_to_5"),
    }


def build_summary(rows):
    project_ids = {row["project_id"] for row in rows if row["project_id"]}
    project_names = [row["project_name"] for row in rows if row["project_name"]]
    project_name_counts = Counter(project_names)
    ai_steps = sum(row["ai_steps"] for row in rows)
    estimated_action_rows = sum(row["estimated_action_rows"] for row in rows)

    return {
        "sessions": len(rows),
        "unique_project_ids": len(project_ids),
        "sessions_missing_project_id": sum(1 for row in rows if not row["has_project_id"]),
        "sessions_missing_project_name": sum(
            1 for row in rows if not row["has_project_name"]
        ),
        "sessions_with_quality_rating": sum(
            1 for row in rows if isinstance(row["quality_rating_0_to_5"], (int, float))
        ),
        "ai_steps": ai_steps,
        "manual_edits": sum(row["manual_edits"] for row in rows),
        "prompt_cycle_stops": sum(row["prompt_cycle_stops"] for row in rows),
        "completed_prompt_cycles": sum(row["completed_prompt_cycles"] for row in rows),
        "estimated_action_rows": estimated_action_rows,
        "avg_actions_per_ai_step": (
            round(estimated_action_rows / ai_steps, 2) if ai_steps else 0.0
        ),
        "avg_ai_steps_per_session": round(ai_steps / len(rows), 2) if rows else 0.0,
        "avg_action_rows_per_session": (
            round(estimated_action_rows / len(rows), 2) if rows else 0.0
        ),
        "top_project_names": project_name_counts.most_common(5),
    }


def print_text(summary):
    print(f"Sessions: {summary['sessions']}")
    print(f"Unique project IDs: {summary['unique_project_ids']}")
    print(f"Sessions missing project_id: {summary['sessions_missing_project_id']}")
    print(f"Sessions missing project_name: {summary['sessions_missing_project_name']}")
    print(f"Sessions with quality rating: {summary['sessions_with_quality_rating']}")
    print(f"AI steps: {summary['ai_steps']}")
    print(f"Manual edits: {summary['manual_edits']}")
    print(f"Prompt cycle stops: {summary['prompt_cycle_stops']}")
    print(f"Completed prompt cycles: {summary['completed_prompt_cycles']}")
    print(f"Estimated action rows: {summary['estimated_action_rows']}")
    print(f"Avg actions / AI step: {summary['avg_actions_per_ai_step']}")
    print(f"Avg AI steps / session: {summary['avg_ai_steps_per_session']}")
    print(f"Avg action rows / session: {summary['avg_action_rows_per_session']}")
    if summary["top_project_names"]:
        print("Top project names:")
        for name, count in summary["top_project_names"]:
            print(f"  {count}  {name}")


def main():
    args = parse_args()
    session_files = sorted(glob.glob(os.path.join(args.sessions_dir, "*.json")))
    if not session_files:
        raise SystemExit(f"No session files found in: {args.sessions_dir}")

    rows = []
    for path in session_files:
        try:
            rows.append(summarize_session(path))
        except Exception as exc:
            print(f"[warn] failed to parse {path}: {exc}")

    if not rows:
        raise SystemExit("No readable producer session files were found.")

    summary = build_summary(rows)
    if args.json:
        print(json.dumps(summary, indent=2))
        return

    print_text(summary)


if __name__ == "__main__":
    main()
