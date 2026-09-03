#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$HOME/OMNIS_V3"

DASH="frontend/static/index.html"

[ -f "$DASH" ] || {
    echo "FATAL: $DASH missing"
    exit 1
}

python3 - "$DASH" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
s = p.read_text()

# ---------------------------------------------------------
# 1. Guarantee V3 identity.
# ---------------------------------------------------------
s = re.sub(
    r'<title>.*?</title>',
    '<title>OMNIS V3 — System Command</title>',
    s,
    count=1,
    flags=re.S
)

s = s.replace("OMNIS V2", "OMNIS V3")
s = s.replace("OMNIS_V2", "OMNIS_V3")

# ---------------------------------------------------------
# 2. Add editable simulation controls if they aren't
#    already present.
# ---------------------------------------------------------
if 'id="seed"' not in s:
    control_html = r'''
<div class="panel">
<div class="title">SIMULATION CONTROLS</div>
<div class="body">
<div class="grid">
<div class="metric">
<span>SEED</span>
<input id="seed" type="number" min="0" max="2147483647"
value="42" style="width:100%;margin-top:6px">
</div>

<div class="metric">
<span>GENERATIONS</span>
<input id="generations" type="number" min="1" max="50"
value="10" style="width:100%;margin-top:6px">
</div>

<div class="metric">
<span>DEBT ALLOWED</span>
<label style="display:block;margin-top:8px">
<input id="debt_allowed" type="checkbox" checked>
 ENABLED
</label>
</div>

<div class="metric">
<span>ACTION</span>
<button class="primary" onclick="startSim()"
style="margin-top:6px">RUN SIMULATION</button>
</div>
</div>
</div>
</div>
'''
    s = s.replace("<main>", "<main>" + control_html, 1)

# ---------------------------------------------------------
# 3. Ensure a real ASK MY SYSTEM interface exists.
# ---------------------------------------------------------
if 'id="systemQuestion"' not in s:
    advisor_html = r'''
<div class="panel">
<div class="title">ASK MY SYSTEM</div>
<div class="body">

<textarea id="systemQuestion"
placeholder="Ask OMNIS about the current system, lineage, simulation state, evidence, or next decision..."></textarea>

<div class="actions">
<button class="primary" onclick="askMySystem()">
ASK MY SYSTEM
</button>
</div>

<div class="reason" id="systemAnswer">
OMNIS is ready. Ask a question grounded in the current system state.
</div>

</div>
</div>
'''
    s = s.replace("</main>", advisor_html + "</main>", 1)

# ---------------------------------------------------------
# 4. Inject authoritative V3 control logic.
# ---------------------------------------------------------
logic = r'''
<script id="omnis-v3-control-logic">
(function(){

async function omnisAPI(path, options){
    const response = await fetch(path, options || {});
    const text = await response.text();

    let data;
    try {
        data = JSON.parse(text);
    } catch {
        throw new Error("Invalid JSON response from " + path);
    }

    if (!response.ok) {
        throw new Error(
            data.detail ||
            data.error ||
            ("HTTP " + response.status)
        );
    }

    return data;
}

async function omnisKey(){
    let key = localStorage.getItem("omnis_api_key");

    if (key) return key;

    const data = await omnisAPI("/api/apikey");
    key = data.api_key;

    if (!key) {
        throw new Error("OMNIS API key unavailable");
    }

    localStorage.setItem("omnis_api_key", key);
    return key;
}

window.startSim = async function(){

    const seedEl =
        document.getElementById("seed");

    const generationsEl =
        document.getElementById("generations");

    const debtEl =
        document.getElementById("debt_allowed");

    if (!seedEl || !generationsEl || !debtEl) {
        alert("Simulation controls are unavailable.");
        return;
    }

    const seed = Number(seedEl.value);
    const generations = Number(generationsEl.value);
    const debt_allowed = debtEl.checked;

    if (!Number.isInteger(seed) ||
        seed < 0 ||
        seed > 2147483647) {

        alert("Seed must be an integer from 0 to 2147483647.");
        return;
    }

    if (!Number.isInteger(generations) ||
        generations < 1 ||
        generations > 50) {

        alert("Generations must be an integer from 1 to 50.");
        return;
    }

    try {

        const key = await omnisKey();

        const result = await omnisAPI(
            "/api/sim/start",
            {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-API-Key": key
                },
                body: JSON.stringify({
                    seed: seed,
                    generations: generations,
                    debt_allowed: debt_allowed
                })
            }
        );

        const status =
            document.getElementById("simstatus");

        const simid =
            document.getElementById("simid");

        if (status)
            status.textContent = result.status || "started";

        if (simid)
            simid.textContent =
                result.sim_id ?? "—";

        await window.refreshOMNIS();

    } catch (error) {
        alert("Simulation failed: " + error.message);
    }
};

window.askMySystem = async function(){

    const questionEl =
        document.getElementById("systemQuestion");

    const answerEl =
        document.getElementById("systemAnswer");

    if (!questionEl || !answerEl) return;

    const question =
        questionEl.value.trim();

    if (!question) {
        answerEl.textContent =
            "Enter a question for OMNIS.";
        return;
    }

    answerEl.textContent =
        "OMNIS is evaluating the current system state...";

    try {

        const [health, latest] =
            await Promise.all([
                omnisAPI("/api/health"),
                omnisAPI("/api/sim/latest")
            ]);

        /*
         * The advisor is given actual OMNIS state:
         *
         * - user question
         * - live health
         * - current advisor status
         * - current lineage
         *
         * No fabricated reasoning is generated here.
         */
        const lineage = {
            source: "OMNIS_V3_DASHBOARD",
            question: question,
            system: health,
            current_lineage: latest.lineages || []
        };

        const key = await omnisKey();

        const result = await omnisAPI(
            "/api/advisor/advise",
            {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-API-Key": key
                },
                body: JSON.stringify(lineage)
            }
        );

        if (result.advice) {
            answerEl.textContent = result.advice;
        } else if (result.reason) {
            answerEl.textContent = result.reason;
        } else if (result.error) {
            answerEl.textContent =
                "Advisor error: " + result.error;
        } else {
            answerEl.textContent =
                JSON.stringify(result, null, 2);
        }

    } catch (error) {

        answerEl.textContent =
            "System query failed: " + error.message;
    }
};

window.refreshOMNIS = async function(){

    try {

        const health =
            await omnisAPI("/api/health");

        const bloom =
            document.getElementById("bloom");

        const advisor =
            document.getElementById("advisor");

        const model =
            document.getElementById("model");

        const sys =
            document.getElementById("sys");

        const status =
            document.getElementById("status");

        if (sys)
            sys.textContent =
                health.status || "—";

        if (bloom)
            bloom.textContent =
                health.bloom_available
                    ? "AVAILABLE"
                    : "OFFLINE";

        if (advisor)
            advisor.textContent =
                health.advisor?.backend || "—";

        if (model)
            model.textContent =
                health.advisor?.model ||
                health.advisor?.model_path ||
                "—";

        if (status)
            status.textContent = "ONLINE";

    } catch {

        const status =
            document.getElementById("status");

        if (status)
            status.textContent = "OFFLINE";
    }
};

window.refreshOMNIS();

setInterval(
    window.refreshOMNIS,
    3000
);

})();
</script>
'''

# Remove our previous control block if present, then append
s = re.sub(
    r'<script id="omnis-v3-control-logic">.*?</script>',
    '',
    s,
    flags=re.S
)

s = s.replace("</body>", logic + "\n</body>")

p.write_text(s)
PY

# Make V3 startup refuse V2.
cat > scripts/start_v3.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$HOME/OMNIS_V3"

DASH="frontend/static/index.html"

[ -f "$DASH" ] || {
    echo "FATAL: V3 dashboard missing"
    exit 1
}

grep -q "OMNIS V3" "$DASH" || {
    echo "FATAL: dashboard is not V3"
    exit 1
}

if grep -qE "OMNIS V2|OMNIS_V2" "$DASH"; then
    echo "FATAL: V2 detected"
    exit 1
fi

pkill -f 'uvicorn backend\.main:app' 2>/dev/null || true
sleep 2

nohup python3 -m uvicorn backend.main:app \
    --host 0.0.0.0 \
    --port 5000 \
    > logs/uvicorn.log 2>&1 &

sleep 4

SERVED="$(curl -sS --max-time 5 http://127.0.0.1:5000/)"

echo "$SERVED" | grep -q "OMNIS V3" || {
    echo "FATAL: server is not serving V3"
    pkill -f 'uvicorn backend\.main:app' 2>/dev/null || true
    exit 1
}

echo "$SERVED" | grep -qE "OMNIS V2|OMNIS_V2" && {
    echo "FATAL: server attempted to serve V2"
    pkill -f 'uvicorn backend\.main:app' 2>/dev/null || true
    exit 1
}

echo "OMNIS V3 ONLINE"
echo "http://127.0.0.1:5000/"
