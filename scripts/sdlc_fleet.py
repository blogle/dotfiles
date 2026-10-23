#!/usr/bin/env python3
"""Pure validation helpers for the SDLC fleet controller."""

import argparse
import json
import re
import sys
from datetime import datetime, timezone


class FleetContractError(ValueError):
    pass


def required_checks(plan):
    try:
        rules = plan["ruleset"]["rules"]
        required = next(rule for rule in rules if rule["type"] == "required_status_checks")
        return required["parameters"]["required_status_checks"]
    except (KeyError, StopIteration, TypeError) as exc:
        raise FleetContractError("trusted SDLC plan has no required status checks") from exc


def verify_check_runs(plan, check_runs):
    return verify_check_runs_for_head(plan, check_runs, None)


def select_candidate_pr(pages, default_branch):
    pulls = [pull for page in pages for pull in page]
    candidates = [pull for pull in pulls if pull.get("base", {}).get("ref") == default_branch]
    return max(candidates, key=lambda pull: pull.get("updated_at", ""), default=None)


def verify_check_runs_for_head(plan, check_runs, head_sha):
    runs = check_runs.get("check_runs", check_runs) if isinstance(check_runs, dict) else check_runs
    if not isinstance(runs, list):
        raise FleetContractError("check-runs response is malformed")
    missing = [
        expected
        for expected in required_checks(plan)
        if not any(
            run.get("name") == expected.get("context")
            and run.get("app", {}).get("id") == expected.get("integration_id")
            and (head_sha is None or run.get("head_sha") == head_sha)
            for run in runs
        )
    ]
    if missing:
        raise FleetContractError(f"required status publisher is unavailable: {missing}")


def verify_ruleset(plan, ruleset, repository):
    if not isinstance(ruleset, dict) or not ruleset.get("id") or not ruleset.get("updated_at"):
        raise FleetContractError("ruleset readback is malformed")
    if ruleset.get("name") != plan["ruleset"].get("name"):
        raise FleetContractError("ruleset name does not match trusted SDLC policy")
    if ruleset.get("source", repository) != repository:
        raise FleetContractError("ruleset source does not match target repository")
    if ruleset.get("enforcement") != plan["ruleset"].get("enforcement"):
        raise FleetContractError("ruleset enforcement does not match trusted SDLC policy")
    if ruleset.get("bypass_actors") != []:
        raise FleetContractError("ruleset bypass actors are missing, redacted, or non-empty")
    if ruleset.get("conditions") != plan["ruleset"].get("conditions"):
        raise FleetContractError("ruleset target does not match trusted SDLC policy")
    actual_checks = next(
        (rule.get("parameters", {}).get("required_status_checks") for rule in ruleset.get("rules", ())
         if rule.get("type") == "required_status_checks"),
        None,
    )
    if actual_checks != required_checks(plan):
        raise FleetContractError("ruleset required checks or publishers do not match trusted SDLC policy")


def secret_actions(installed_names, installed_version, desired_version):
    names = set(installed_names)
    return {
        "SDLC_RELEASE_APP_ID": installed_version != desired_version or "SDLC_RELEASE_APP_ID" not in names,
        "SDLC_RELEASE_APP_PRIVATE_KEY": installed_version != desired_version or "SDLC_RELEASE_APP_PRIVATE_KEY" not in names,
        "SDLC_RELEASE_CREDENTIAL_VERSION": installed_version != desired_version,
    }


def attest_rulesets(plan, checks, automated, repository):
    verify_ruleset(plan, checks, repository)
    desired = plan["automated_merges"]
    for key in ("name", "target", "enforcement", "conditions", "rules", "bypass_actors"):
        actual, expected = automated.get(key), desired[key]
        if isinstance(expected, list):
            actual = sorted(actual or [], key=lambda item: json.dumps(item, sort_keys=True))
            expected = sorted(expected, key=lambda item: json.dumps(item, sort_keys=True))
        if actual != expected:
            raise FleetContractError(f"automated-merge restriction {key} differs from trusted policy")
    if automated.get("source", repository) != repository:
        raise FleetContractError("automated-merge restriction belongs to another repository")

    def bind(rule):
        try:
            updated = datetime.fromisoformat(rule["updated_at"])
            if updated.tzinfo is None:
                raise ValueError("timezone missing")
            timestamp = updated.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
        except (KeyError, ValueError, TypeError) as exc:
            raise FleetContractError("ruleset has no valid update timestamp") from exc
        return {"schema": 1, "repository": repository, "ruleset_id": rule["id"], "updated_at": timestamp, "bypass_actors": rule["bypass_actors"]}

    result = bind(checks)
    result["automated_merges"] = bind(automated)
    return result


def verify_consumer_pin(flake_lock, flake_text, expected_ref):
    try:
        node = flake_lock["nodes"]["sdlc"]["locked"]
    except (KeyError, TypeError) as exc:
        raise FleetContractError("consumer has no locked SDLC input") from exc
    if node.get("rev") != expected_ref:
        raise FleetContractError("consumer SDLC input is not the approved immutable revision")
    if not re.search(
        r"(?m)^[ \t]*packages\.sdlc[ \t]*=[ \t]*sdlc\.packages\.\$\{system\}\.sdlc[ \t]*;",
        flake_text,
    ):
        raise FleetContractError("consumer flake does not declare an SDLC package output")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("verify-check-runs", "verify-ruleset", "verify-consumer", "attest"))
    parser.add_argument("--plan")
    parser.add_argument("--repository")
    parser.add_argument("--expected-ref")
    parser.add_argument("--head-sha")
    args = parser.parse_args()
    payload = json.load(sys.stdin)
    if args.command == "verify-check-runs":
        if not args.plan:
            parser.error("--plan is required for verify-check-runs")
        plan = json.loads(args.plan)
        verify_check_runs_for_head(plan, payload, args.head_sha)
    elif args.command == "verify-ruleset":
        if not args.plan:
            parser.error("--plan is required for verify-ruleset")
        plan = json.loads(args.plan)
        verify_ruleset(plan, payload, args.repository)
    elif args.command == "attest":
        if not args.plan or not args.repository:
            parser.error("--plan and --repository are required for attest")
        print(json.dumps(attest_rulesets(json.loads(args.plan), payload["checks"], payload["automated"], args.repository)))
    else:
        verify_consumer_pin(payload["lock"], payload["flake"], args.expected_ref)


if __name__ == "__main__":
    try:
        main()
    except (FleetContractError, json.JSONDecodeError) as exc:
        print(f"fleet: {exc}", file=sys.stderr)
        raise SystemExit(1)
