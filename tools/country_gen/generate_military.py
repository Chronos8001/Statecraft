"""Génère les forces armées de départ de chaque pays : data/countries/military.json.

- Répartition des effectifs entre terre, air et mer (pas de marine pour les pays sans littoral).
- Niveau d'équipement (1 à 5) selon la dépense de défense par soldat (budget réel de 2026), remplacé par les
  valeurs saisies pour une quarantaine de grandes armées ; entraînement selon le niveau ; moral.
- Capacités spéciales (forces spéciales, missiles, cyber) en jauges 0 à 100 ; arsenaux nucléaires (SIPRI 2025).

Usage : python tools/country_gen/generate_military.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
ROOT = TOOL_DIR.parents[1]
DATA_DIR = ROOT / "data"
BILLION = 1.0e9
BRANCHES = ["land", "air", "sea"]


def clamp(value: float, low: float, high: float) -> float:
    return min(max(value, low), high)


def main() -> None:
    cfg = json.loads((TOOL_DIR / "military_config.json").read_text(encoding="utf-8"))
    countries: dict = json.loads((DATA_DIR / "countries" / "countries.json").read_text(encoding="utf-8"))
    budgets: dict = json.loads((DATA_DIR / "countries" / "budget.json").read_text(encoding="utf-8"))
    provinces: dict = json.loads((DATA_DIR / "provinces" / "provinces.json").read_text(encoding="utf-8"))
    coastal = {p.get("owner", "") for p in provinces.values() if p.get("coastal", False)}
    rule = cfg["level_rule"]
    training_rule = cfg["training_rule"]
    special_rule = cfg["special_rule"]
    out = {}
    for tag in sorted(countries):
        country = countries[tag]
        personnel = country["military"]["active_personnel"]
        defense_share = budgets[tag]["budget"]["spending"].get("defense", 0.0) / 100.0
        spend = defense_share * country["economy"]["gdp_billion_usd"] * BILLION
        per_soldier = spend / personnel if personnel > 0 else 0.0
        level = clamp(rule["base"] + rule["per_decade"] * math.log10(max(per_soldier, 1.0) / rule["reference_spend_per_soldier"]),
                      rule["min"], rule["max"]) if personnel > 0 else rule["min"]
        levels = cfg["manual_levels"].get(tag, [level, level, level])
        shares = cfg["branch_shares"]["coastal" if tag in coastal else "landlocked"]
        morale = cfg["manual_morale"].get(tag, cfg["morale_default"])
        branches = {}
        for index, branch in enumerate(BRANCHES):
            if shares[branch] <= 0.0:
                continue
            branch_level = levels[index]
            branches[branch] = {"share": shares[branch], "level": round(branch_level, 2),
                                "training": round(clamp(training_rule["base"] + training_rule["per_level"] * (branch_level - 1.0),
                                                        training_rule["min"], training_rule["max"]), 1),
                                "morale": morale}
        average = sum(b["level"] * b["share"] for b in branches.values())
        special = cfg["manual_special"].get(tag, [
            round(clamp(special_rule["special_forces_per_level"] * average, 0, 100)),
            round(clamp(special_rule["missiles_per_level"] * (average - 1.0), 0, 100)),
            round(clamp(special_rule["cyber_per_level"] * (average - 1.0), 0, 100))])
        out[tag] = {"armed_forces": {"branches": branches,
                                     "special": {"special_forces": special[0], "missiles": special[1], "cyber": special[2]},
                                     "nuclear_warheads": cfg["nuclear_warheads"].get(tag, 0)}}
    path = DATA_DIR / "countries" / "military.json"
    lines = [f'  "{k}": {json.dumps(v, ensure_ascii=False, separators=(",", ": "))}' for k, v in out.items()]
    path.write_text("{\n" + ",\n".join(lines) + "\n}\n", encoding="utf-8", newline="\n")
    print(f"{len(out)} pays")
    for tag in ["USA", "FRA", "NGA", "CHE", "MNG", "BOL", "LUX"]:
        print(tag, out[tag]["armed_forces"])


if __name__ == "__main__":
    main()
