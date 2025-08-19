# /opt/HX-Infrastructure-/api-gateway/gateway/src/routing/selector.py
from typing import Dict, Any, List
from .features import current_load_penalty, performance_bonus, specialization_bonus

class ModelSelectionAlgorithm:
    def score(self, model: Dict[str, Any], req_ctx: Dict[str, Any]) -> float:
        # Capability match
        est_tokens = req_ctx.get("estimated_tokens", 512)
        complexity = max(req_ctx.get("complexity_score", 1.0), 1e-6)
        ctx_len = model.get("context_length", 8192)
        if est_tokens > ctx_len:
            return 0.0
        tier = float(model.get("tier_score", 0.7))
        base = min(1.0, tier / complexity)
        # Dynamics
        load = current_load_penalty(model["name"])
        perf = performance_bonus(model["name"])
        spec = specialization_bonus(model, req_ctx.get("domain"))
        return base * (1.0 - load) + perf + spec

    def select(self, candidates: List[Dict[str, Any]], req_ctx: Dict[str, Any]) -> Dict[str, Any] | None:
        if not candidates:
            return None
        scored = [(self.score(m, req_ctx), m) for m in candidates]
        scored.sort(key=lambda t: t[0], reverse=True)
        return scored[0][1]
