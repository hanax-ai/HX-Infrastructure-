# /opt/HX-Infrastructure-/api-gateway/gateway/src/routing/selector.py
import logging
from typing import Dict, Any, List
from .features import current_load_penalty, performance_bonus, specialization_bonus

logger = logging.getLogger(__name__)

class ModelSelectionAlgorithm:
    def score(self, model: Dict[str, Any], req_ctx: Dict[str, Any]) -> float:
        # Defensive check: ensure model is a dictionary
        if not isinstance(model, dict):
            logger.error(f"Invalid model type: expected dict, got {type(model).__name__}. Model: {model}")
            return 0.0
            
        # Capability match
        est_tokens = req_ctx.get("estimated_tokens", 512)
        complexity = max(req_ctx.get("complexity_score", 1.0), 1e-6)
        ctx_len = model.get("context_length", 8192)
        if est_tokens > ctx_len:
            # Log model rejection for debugging
            model_id = model.get("name") or model.get("id") or "unknown"
            logger.warning(f"Model rejected: {model_id} - estimated tokens ({est_tokens}) exceed context length ({ctx_len})")
            return float("-inf")
        tier = float(model.get("tier_score", 0.7))
        base = min(1.0, tier / complexity)
        
        # Dynamics - safe name extraction with defensive checks
        model_name = str(model.get("name") or model.get("id", "unknown"))
        if not model_name or model_name == "unknown":
            # Log debug and use fallback
            logger.debug(f"Model missing name/id: {model}")
            model_name = "fallback"
        
        load = current_load_penalty(model_name)
        perf = performance_bonus(model_name)
        spec = specialization_bonus(model, req_ctx.get("domain"))
        return base * (1.0 - load) + perf + spec

    def select(self, candidates: List[Dict[str, Any]], req_ctx: Dict[str, Any]) -> Dict[str, Any] | None:
        if not candidates:
            return None
        scored = [(self.score(m, req_ctx), m) for m in candidates]
        scored.sort(key=lambda t: t[0], reverse=True)
        return scored[0][1]
