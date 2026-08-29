import json
import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path

from fastapi import FastAPI, WebSocket, BackgroundTasks, HTTPException, Depends, Header
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from .config import DATA_DIR, PORT, HOST, LOGS_DIR, API_KEY, MAX_GENERATIONS, MAX_SEED
from .database import init_db, get_db, save_lineage, mark_finished
from .bloom_engine import run_simulation, bloom_script_available
from .slm_advisor import advisor
from .telemetry import broadcaster

LOGS_DIR.mkdir(parents=True, exist_ok=True)
logger = logging.getLogger("omnis_v3")
logger.setLevel(logging.INFO)
_handler = RotatingFileHandler(LOGS_DIR / "omnis_v3.log", maxBytes=5_000_000, backupCount=3)
_handler.setFormatter(logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s"))
logger.addHandler(_handler)

app = FastAPI(title="OMNIS V3", version="3.1.0")

static_dir = Path(__file__).resolve().parent.parent / "frontend" / "static"
if static_dir.exists():
    app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

def require_api_key(x_api_key: str = Header(default="")):
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid or missing API key")
    return True

class SimStartRequest(BaseModel):
    seed: int = Field(..., ge=0, le=MAX_SEED)
    generations: int = Field(10, ge=1, le=MAX_GENERATIONS)
    debt_allowed: bool = True

@app.on_event("startup")
async def startup():
    init_db()
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    if not bloom_script_available():
        logger.warning("BLOOM script not found; simulations will use generated mock data.")
    status = advisor.status()
    if status["loaded"]:
        logger.info(f"VERITY advisor ready: {status}")
    else:
        logger.warning(f"VERITY advisor NOT loaded: {status}")
    logger.info(f"OMNIS V3 starting on {HOST}:{PORT}")

@app.get("/")
async def root():
    index = static_dir / "index.html"
    if index.exists():
        return FileResponse(str(index))
    return {"message": "OMNIS V3 API is running. Serve dashboard from /static/index.html"}

@app.get("/api/health")
async def health():
    return {
        "status": "ok",
        "bloom_available": bloom_script_available(),
        "advisor": advisor.status(),
    }

@app.post("/api/sim/start", dependencies=[Depends(require_api_key)])
async def start_simulation(req: SimStartRequest, background_tasks: BackgroundTasks):
    with get_db() as conn:
        cursor = conn.execute(
            "INSERT INTO simulations (seed, generations, debt_allowed, status) VALUES (?, ?, ?, 'running')",
            (req.seed, req.generations, 1 if req.debt_allowed else 0),
        )
        sim_id = cursor.lastrowid
    background_tasks.add_task(run_sim_task, req, sim_id)
    return {"status": "started", "sim_id": sim_id}

def run_sim_task(req: SimStartRequest, sim_id: int):
    try:
        output_file = run_simulation(req.seed, req.generations, req.debt_allowed, sim_id)
        with open(output_file, 'r') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                    if isinstance(data, dict) and 'id' in data:
                        save_lineage(sim_id, data)
                except json.JSONDecodeError:
                    logger.warning(f"Skipping malformed line in sim {sim_id}: {line[:80]!r}")
        mark_finished(sim_id, "completed")
        logger.info(f"Simulation {sim_id} completed.")
    except Exception as e:
        logger.error(f"Simulation {sim_id} failed: {e}")
        mark_finished(sim_id, "failed", error=str(e))

@app.get("/api/sim/latest")
async def get_latest():
    output_file = DATA_DIR / "latest.jsonl"
    if not output_file.exists():
        return {"lineages": []}
    lineages = []
    with open(output_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
                if isinstance(data, dict) and 'id' in data:
                    lineages.append(data)
            except json.JSONDecodeError:
                continue
    return {"lineages": lineages}

@app.get("/api/sim/stats")
async def get_stats():
    with get_db() as conn:
        rows = conn.execute("SELECT * FROM lineages ORDER BY gen").fetchall()
    return [dict(row) for row in rows]

@app.get("/api/sim/status/{sim_id}")
async def get_sim_status(sim_id: int):
    with get_db() as conn:
        row = conn.execute("SELECT * FROM simulations WHERE id = ?", (sim_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Simulation not found")
    return dict(row)

@app.post("/api/advisor/advise", dependencies=[Depends(require_api_key)])
async def get_advice(lineage: dict):
    return advisor.predict(lineage)

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    await broadcaster.add_connection(websocket)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=HOST, port=PORT)
