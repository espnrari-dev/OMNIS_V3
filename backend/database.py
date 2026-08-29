import sqlite3
from contextlib import contextmanager
from .config import DATA_DIR

DB_PATH = DATA_DIR / "omnis_v3.db"

@contextmanager
def get_db():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH), timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

def init_db():
    with get_db() as conn:
        conn.execute('''
            CREATE TABLE IF NOT EXISTS simulations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                seed INTEGER NOT NULL,
                generations INTEGER NOT NULL,
                debt_allowed INTEGER NOT NULL,
                status TEXT NOT NULL DEFAULT 'running',
                error TEXT,
                started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                finished_at TIMESTAMP
            )
        ''')
        conn.execute('''
            CREATE TABLE IF NOT EXISTS lineages (
                id TEXT PRIMARY KEY,
                sim_id INTEGER NOT NULL,
                gen INTEGER,
                total REAL,
                lifespan INTEGER,
                capital REAL,
                FOREIGN KEY (sim_id) REFERENCES simulations(id)
            )
        ''')
        conn.execute('CREATE INDEX IF NOT EXISTS idx_lineages_sim ON lineages(sim_id)')

def save_lineage(sim_id, lineage):
    with get_db() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO lineages (id, sim_id, gen, total, lifespan, capital) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (lineage['id'], sim_id, lineage.get('gen'), lineage.get('total'),
             lineage.get('lifespan'), lineage.get('capital'))
        )

def mark_finished(sim_id, status, error=None):
    with get_db() as conn:
        conn.execute(
            "UPDATE simulations SET finished_at = CURRENT_TIMESTAMP, status = ?, error = ? WHERE id = ?",
            (status, error, sim_id)
        )
