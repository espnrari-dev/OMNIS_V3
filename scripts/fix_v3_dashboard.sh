#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$HOME/OMNIS_V3"

DASH="frontend/static/index.html"

[ -f "$DASH" ] || {
    echo "FATAL: V3 dashboard missing"
    exit 1
}

python3 - "$DASH" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text()

# V3 identity — permanently remove V2 identity from served dashboard.
s = re.sub(
    r'<title>.*?</title>',
    '<title>OMNIS V3 — System Command</title>',
    s, count=1, flags=re.S
)
s = s.replace("OMNIS V2", "OMNIS V3")
s = s.replace("OMNIS_V2", "OMNIS_V3")

# Remove any previous repair block so this is idempotent.
s = re.sub(
    r'<div id="omnis-v3-controls">.*?</div>\s*</div>',
    '',
    s, flags=re.S
)
s = re.sub(
    r'<script id="omnis-v3-runtime">.*?</script>',
    '',
    s, flags=re.S
)

controls = r'''
<div id="omnis-v3-controls" class="panel">
<div class="title">V3 SIMULATION CONTROLS</div>
<div class="body">
<div class="grid">

<div class="metric">
<span>SEED</span>
<input id="seed" type="number"
min="0" max="2147483647" value="42"
style="width:100%;margin-top:6px">
</div>

<div class="metric">
<span>GENERATIONS</span>
<input id="generations" type="number"
min="1" max="1000" value="10"
style="width:100%;margin-top:6px">
</div>

<div class="metric">
<span>DEBT ALLOWED</span>
<label style="display:block;margin-top:8px">
<input id="debt_allowed" type="checkbox" checked>
ENABLED
</label>
</div>

<div class="metric">
<span>SIMULATION</span>
<button class="primary" id="runSimulation"
style="margin-top:6px;width:100%">
RUN SIMULATION
</button>
</div>

</div>

<div class="reason" id="simResult" style="margin-top:10px">
Ready — V3 controls are live.
</div>

</div>
</div>

<div class="panel" id="omnis-ask-panel">
<div class="title">ASK MY SYSTEM</div>
<div class="body">

<textarea id="systemQuestion"
placeholder="Ask OMNIS about the current system, simulation, lineage, evidence, state, or next decision..."></textarea>

<div class="actions">
<button class="primary" id="askSystem">
ASK MY SYSTEM
</button>
</div>

<div class="reason" id="systemAnswer">
Ask a question. OMNIS will evaluate it against the live V3 system state and current simulation lineage.
</div>

</div>
</div>
'''

# Put controls immediately after <main>.
if 'id="omnis-v3-controls"' not in s:
    s = s.replace("<main>", "<main>\n" + controls, 1)

runtime = r'''
<script id="omnis-v3-runtime">
(function(){

async function api(path, options = {}) {
    const r = await fetch(path, options);
    const text = await r.text();

    let data = {};
    try { data = JSON.parse(text); }
    catch (_) { throw new Error("Invalid response from " + path); }

    if (!r.ok) {
        throw new Error(
            data.detail || data.error || ("HTTP " + r.status)
        );
    }

    return data;
}

async function key() {
    let k = localStorage.getItem("omnis_api_key");

    if (k) return k;

    const data = await api("/api/apikey");

    if (!data.api_key)
        throw new Error("OMNIS API key unavailable");

    localStorage.setItem("omnis_api_key", data.api_key);
    return data.api_key;
}

async function runSimulation() {
    const seed = Number(document.getElementById("seed").value);
    const generations =
        Number(document.getElementById("generations").value);
    const debt_allowed =
        document.getElementById("debt_allowed").checked;

    const result =
        document.getElementById("simResult");

    if (!Number.isInteger(seed) || seed < 0 || seed > 2147483647) {
        result.textContent =
            "Invalid seed. Use an integer from 0 to 2147483647.";
        return;
    }

    if (!Number.isInteger(generations) ||
        generations < 1 || generations > 1000) {
        result.textContent =
            "Invalid generations. Use an integer from 1 to 1000.";
        return;
    }

    result.textContent = "Starting V3 simulation...";

    try {
        const k = await key();

        const data = await api("/api/sim/start", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-API-Key": k
            },
            body: JSON.stringify({
                seed,
                generations,
                debt_allowed
            })
        });

        result.textContent =
            "Simulation started. " +
            "ID: " + (data.sim_id ?? "—") +
            " | Status: " + (data.status ?? "started");

        await refresh();
    } catch (e) {
        result.textContent = "Simulation failed: " + e.message;
    }
}

async function askSystem() {
    const q =
        document.getElementById("systemQuestion").value.trim();

    const answer =
        document.getElementById("systemAnswer");

    if (!q) {
        answer.textContent = "Enter a question for OMNIS.";
        return;
    }

    answer.textContent =
        "Evaluating the live V3 system state...";

    try {
        const [health, latest] = await Promise.all([
            api("/api/health"),
            api("/api/sim/latest")
        ]);

        const k = await key();

        const lineage = {
            source: "OMNIS_V3_LIVE_SYSTEM",
            question: q,
            system_health: health,
            simulation: latest
        };

        const result = await api("/api/advisor/advise", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-API-Key": k
            },
            body: JSON.stringify(lineage)
        });

        if (result.advice)
            answer.textContent = result.advice;
        else if (result.reason)
            answer.textContent = result.reason;
        else if (result.error)
            answer.textContent = "Advisor error: " + result.error;
        else
            answer.textContent =
                JSON.stringify(result, null, 2);

    } catch (e) {
        answer.textContent =
            "System query failed: " + e.message;
    }
}

async function refresh() {
    try {
        const h = await api("/api/health");

        const status = document.getElementById("status");
        if (status)
            status.textContent =
                h.status === "ok" ? "ONLINE" : "OFFLINE";

        const advisor = document.getElementById("advisor");
        if (advisor)
            advisor.textContent =
                h.advisor?.backend || "—";

        const model = document.getElementById("model");
        if (model)
            model.textContent =
                h.advisor?.model ||
                h.advisor?.model_path ||
                "—";

        const bloom = document.getElementById("bloom");
        if (bloom)
            bloom.textContent =
                h.bloom_available ? "AVAILABLE" : "OFFLINE";

    } catch (_) {
        const status = document.getElementById("status");
        if (status) status.textContent = "OFFLINE";
    }
}

document.getElementById("runSimulation")
    ?.addEventListener("click", runSimulation);

document.getElementById("askSystem")
    ?.addEventListener("click", askSystem);

refresh();
setInterval(refresh, 3000);

})();
</script>
'''

s = s.replace("</body>", runtime + "\n</body>", 1)

p.write_text(s)
PY

cat > scripts/start_v3.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$HOME/OMNIS_V3"

DASH="frontend/static/index.html"

[ -f "$DASH" ] || exit 1

grep -q 'OMNIS V3' "$DASH"
! grep -qE 'OMNIS V2|OMNIS_V2' "$DASH"

grep -q 'id="seed"' "$DASH"
grep -q 'id="generations"' "$DASH"
grep -q 'id="debt_allowed"' "$DASH"
grep -q 'id="systemQuestion"' "$DASH"
grep -q 'id="omnis-v3-runtime"' "$DASH"

pkill -f 'uvicorn backend\.main:app' 2>/dev/null || true
sleep 2

nohup python3 -m uvicorn backend.main:app \
    --host 0.0.0.0 \
    --port 5000 \
    > logs/uvicorn.log 2>&1 &

sleep 4

PAGE="$(curl -sS --max-time 5 http://127.0.0.1:5000/)"

echo "$PAGE" | grep -q 'OMNIS V3'
! echo "$PAGE" | grep -qE 'OMNIS V2|OMNIS_V2'
echo "$PAGE" | grep -q 'id="seed"'
echo "$PAGE" | grep -q 'id="generations"'
echo "$PAGE" | grep -q 'id="debt_allowed"'
echo "$PAGE" | grep -q 'id="systemQuestion"'

echo "======================================"
echo "OMNIS V3 — LOCKED AND RUNNING"
echo "======================================"
echo
echo "Dashboard:"
echo "http://127.0.0.1:5000/"
echo
echo "Health:"
curl -sS --max-time 5 http://127.0.0.1:5000/api/health
echo
