"""
Patch v2rayN active Whitelist routing rules in guiNDB.db so Anthropic/Claude
and extended Google/AI domains are explicitly forced to `proxy` BEFORE
`geoip:cn` / `geosite:cn` direct rules.

Usage (close v2rayN first so it does not overwrite guiNDB.db, then reopen v2rayN):
    python patch_v2rayn_routing.py --db "D:\\Tools\\v2rayN\\guiConfigs\\guiNDB.db"
"""
import argparse
import json
import os
import shutil
import sqlite3
from datetime import datetime
from pathlib import Path

FORCE_PROXY_RULE_ID = "9900112233445566778"
FORCE_PROXY_DOMAINS = [
    "domain:anthropic.com",
    "domain:claude.ai",
    "domain:claude.com",
    "domain:claudeusercontent.com",
    "domain:anthropic.engineering",
    "domain:statsigapi.net",
    "domain:statsig.com",
    "domain:sentry.io",
    "domain:intercom.io",
    "domain:intercomcdn.com",
    "domain:datadoghq.com",
    "domain:segment.io",
    "domain:segment.com",
    "domain:stripe.com",
    "domain:antigravity.google",
    "domain:deepmind.google",
    "domain:deepmind.com",
    "domain:ai.dev",
    "domain:withgoogle.com",
    "domain:pki.goog",
    "domain:googleapis.com",
    "domain:gstatic.com",
    "domain:googleusercontent.com",
    "domain:gvt1.com",
    "domain:gvt2.com",
]


def resolve_db_path(cli_db: str | None) -> Path:
    if cli_db:
        return Path(cli_db)
    env_db = os.environ.get("V2RAYN_DB_PATH")
    if env_db:
        return Path(env_db)
    candidates = [
        Path.cwd() / "guiConfigs" / "guiNDB.db",
        Path.cwd() / "guiNDB.db",
    ]
    for c in candidates:
        if c.exists():
            return c
    raise FileNotFoundError(
        "Please pass --db <path-to-guiNDB.db> or set V2RAYN_DB_PATH."
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Force AI domains to proxy in v2rayN guiNDB.db")
    parser.add_argument("--db", help="Path to v2rayN guiConfigs/guiNDB.db")
    args = parser.parse_args()

    db_path = resolve_db_path(args.db)
    if not db_path.exists():
        raise FileNotFoundError(f"v2rayN database not found: {db_path}")

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = db_path.with_name(f"{db_path.stem}.backup_{ts}{db_path.suffix}")
    shutil.copy2(db_path, backup_path)
    print(f"Backed up DB to: {backup_path}")

    conn = sqlite3.connect(db_path)
    try:
        rows = conn.execute(
            "SELECT id, remarks, isActive, ruleSet FROM RoutingItem WHERE isActive = 1"
        ).fetchall()
        if not rows:
            raise RuntimeError("No active RoutingItem found in guiNDB.db")

        for row_id, remarks, _, rule_set_raw in rows:
            rules = json.loads(rule_set_raw)
            rules = [r for r in rules if r.get("Id") != FORCE_PROXY_RULE_ID]

            new_rule = {
                "Id": FORCE_PROXY_RULE_ID,
                "OutboundTag": "proxy",
                "Domain": FORCE_PROXY_DOMAINS,
                "Enabled": True,
                "Remarks": "Force AI/Claude/Google domains via proxy",
            }

            insert_idx = 0
            for idx, r in enumerate(rules):
                if r.get("OutboundTag") == "direct":
                    insert_idx = idx
                    break
                insert_idx = idx + 1

            rules.insert(insert_idx, new_rule)
            new_raw = json.dumps(rules, ensure_ascii=False)
            conn.execute(
                "UPDATE RoutingItem SET ruleSet = ?, ruleNum = ? WHERE id = ?",
                (new_raw, len(rules), row_id),
            )
            print(f"Updated RoutingItem '{remarks}' ({row_id}): total rules = {len(rules)}")

        conn.commit()
    finally:
        conn.close()


if __name__ == "__main__":
    main()
