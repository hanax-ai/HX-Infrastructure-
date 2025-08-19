# /opt/HX-Infrastructure-/api-gateway/gateway/src/routing/features.py
from typing import Dict, Any

def current_load_penalty(model_name: str) -> float:
    # TODO: integrate Prometheus / Redis; return 0..1
    return 0.0

def performance_bonus(model_name: str) -> float:
    # TODO: ingest perf baselines; return -1..+1
    return 0.0

def specialization_bonus(model: Dict[str, Any], domain: str | None) -> float:
    if not domain:
        return 0.0
    specs = set(model.get("specializations", []))
    return 0.3 if domain in specs else 0.0
