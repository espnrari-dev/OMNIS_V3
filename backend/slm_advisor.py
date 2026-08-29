import logging
from .config import VERITY_MODEL_PATH, VERITY_CTX_SIZE, VERITY_MAX_TOKENS, VERITY_THREADS

logger = logging.getLogger("omnis_v3")

class SLMAdvisor:
    """
    Wraps your trained VERITY GGUF model via llama.cpp bindings.
    This replaces the earlier placeholder that loaded a nonexistent
    models/slm_model.pt with torch.load and returned random choices.
    """

    def __init__(self):
        self.llm = None
        self.backend = "none"
        self.model_path = str(VERITY_MODEL_PATH) if VERITY_MODEL_PATH else None

        if VERITY_MODEL_PATH is None:
            logger.warning(
                "No VERITY .gguf model found. Set VERITY_MODEL_PATH to your "
                "trained checkpoint (e.g. export VERITY_MODEL_PATH=~/VERITY_fixed3.gguf) "
                "and restart. Falling back to stub responses until then."
            )
            return

        try:
            from llama_cpp import Llama
        except ImportError:
            logger.warning(
                "llama-cpp-python is not installed, so VERITY (%s) cannot be loaded. "
                "Install it with: pip install llama-cpp-python. Falling back to stub responses.",
                self.model_path,
            )
            return

        try:
            self.llm = Llama(
                model_path=self.model_path,
                n_ctx=VERITY_CTX_SIZE,
                n_threads=VERITY_THREADS,
                verbose=False,
            )
            self.backend = "verity-llama.cpp"
            logger.info(f"VERITY model loaded from {self.model_path}")
        except Exception as e:
            logger.warning(f"Failed to load VERITY model from {self.model_path}: {e}")
            self.llm = None

    def status(self) -> dict:
        return {
            "backend": self.backend,
            "model_path": self.model_path,
            "loaded": self.llm is not None,
        }

    def predict(self, lineage_data: dict) -> dict:
        if self.llm is None:
            return {
                "action": "hold",
                "confidence": 0.5,
                "reason": "VERITY model not loaded — set VERITY_MODEL_PATH and install llama-cpp-python.",
                "backend": self.backend,
            }

        capital = lineage_data.get("capital", 0) or 0
        prompt = (
            "You are VERITY, an advisor reviewing a simulated lineage.\n"
            f"Lineage id: {lineage_data.get('id')}\n"
            f"Generation: {lineage_data.get('gen')}\n"
            f"Total: {lineage_data.get('total')}\n"
            f"Lifespan: {lineage_data.get('lifespan')}\n"
            f"Capital: {capital}\n"
            "Give one short piece of advice for this lineage:\n"
        )

        try:
            result = self.llm(
                prompt,
                max_tokens=VERITY_MAX_TOKENS,
                stop=["\n\n"],
                echo=False,
            )
            text = result["choices"][0]["text"].strip()
        except Exception as e:
            logger.error(f"VERITY inference failed: {e}")
            return {
                "action": "hold",
                "confidence": 0.0,
                "reason": f"VERITY inference error: {e}",
                "backend": self.backend,
            }

        # This is a 10M-parameter model — it produces free text, not structured
        # JSON, so 'action' is a simple heuristic derived from the lineage's
        # own numbers rather than something the model is asked to classify.
        action = "increase debt" if capital < 0 else "reduce debt" if capital > 2 else "hold"

        return {
            "action": action,
            "confidence": None,
            "reason": text or "(VERITY returned an empty response)",
            "backend": self.backend,
        }

advisor = SLMAdvisor()
