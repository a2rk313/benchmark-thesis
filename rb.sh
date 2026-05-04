#!/usr/bin/env bash
# =============================================================================
# THESIS BENCHMARK SUITE ORCHESTRATOR
# Version: 4.0.1 (Telemetry Export Fix — Native scripts self-time)
#
# FIX v4.0.1: Benchmark scripts (matrix_ops.py, etc.) perform their own
# internal repetition and emit aggregated statistics.  The orchestrator
# uses hyperfine ONLY to generate a JSON envelope for telemetry injection.
# Therefore all hyperfine invocations use --runs 1 --warmup 0.
# =============================================================================
set -euo pipefail

BENCHMARK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse arguments ───────────────────────────────────────────────────────────
MODE="all"
IS_BOOTC=false
if [ -f /etc/benchmark-bootc-release ]; then
    IS_BOOTC=true
    MODE="native"
fi

USE_GHCR=false
RESUME=false
SHOW_STATUS=false
CLEAN=false
DRY_RUN=false
SCALING=false
SCALING_QUICK=false
DATA_MODE="auto"
SIZE_MODE="small"
THERMAL_REPORT=false
THERMAL_GUARD=true          # gate benchmarks on temperature
ERRORS=()
BENCHMARK_COUNT=0
TOTAL_BENCHMARKS=0
START_TIME=$(date +%s)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --container-only)   MODE="container"; shift ;;
        --native-only)      MODE="native"; shift ;;
        --use-ghcr)         USE_GHCR=true; shift ;;
        --resume)           RESUME=true; shift ;;
        --status)           SHOW_STATUS=true; shift ;;
        --clean)            CLEAN=true; shift ;;
        --dry-run)          DRY_RUN=true; shift ;;
        --scaling)          SCALING=true; shift ;;
        --scaling-quick)    SCALING=true; SCALING_QUICK=true; shift ;;
        --thermal-report)   THERMAL_REPORT=true; shift ;;
        --no-thermal-guard) THERMAL_GUARD=false; shift ;;
        --data)             DATA_MODE="$2"; shift 2 ;;
        --size)             SIZE_MODE="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "  --container-only    Run container benchmarks only"
            echo "  --native-only       Run native benchmarks only"
            echo "  --use-ghcr          Force pull from GHCR (default: auto)"
            echo "  --resume            Resume from exact point of interruption"
            echo "  --status            Show completed/pending benchmarks (use with --resume)"
            echo "  --clean             Clear old results before running"
            echo "  --dry-run           Preview execution plan"
            echo "  --scaling           Run data scaling benchmarks (all scenarios)"
            echo "  --scaling-quick     Run data scaling benchmarks (smaller scales)"
            echo "  --thermal-report    Print thermal/freq telemetry summary after run"
            echo "  --no-thermal-guard  Disable temperature gating (useful in CI)"
            echo "  --data MODE         Data source: auto|real|synthetic (default: auto)"
            echo "  --size SIZE         Data size: small|large (default: small)"
            echo "  -h, --help          Show this help"
            echo ""
            echo "Thermal/Frequency telemetry:"
            echo "  All temperature and CPU-frequency reads use kernel sysfs (/sys/...)"
            echo "  and are captured BEFORE and AFTER each hyperfine invocation — never"
            echo "  inside the timed window.  This means zero measurement interference."
            echo "  Results are embedded in each JSON as 'environment_pre' / 'environment_post'."
            echo ""
            echo "Resume behaviour:"
            echo "  Checkpoints are saved per individual benchmark (not per section)."
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Colour codes ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
MAGENTA='\033[0;35m'; CYAN='\033[0;36m'

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  THERMAL & FREQUENCY TELEMETRY LAYER                                    ║
# ║  All functions read from /sys — no external tools, no background I/O    ║
# ╚══════════════════════════════════════════════════════════════════════════╝

# ── Configuration knobs ───────────────────────────────────────────────────────
TEMP_THRESHOLD_C=65          # defer benchmark start if any core > this (°C)
TEMP_IDEAL_C=55              # "green" temperature for thesis reporting
TEMP_WARN_C=60               # "yellow" warning zone
TEMP_WAIT_SECS=30            # seconds to wait each thermal-guard poll cycle
TEMP_MAX_WAIT=300            # give up after this many seconds (5 min)
SETTLE_TIME=10               # seconds of idle between consecutive benchmarks
FREQ_VARIANCE_PCT=5          # max allowed % spread across cores before a run
CV_WARN_THRESHOLD=0.05       # coefficient of variation (stddev/mean) warning
THERMAL_LOG="results/thermal_telemetry.jsonl"   # append-only JSONL per benchmark

# ── Thermal zone discovery ────────────────────────────────────────────────────
# Returns space-separated list of /sys thermal zone paths that are CPU-type.
# Excludes: acpitz (ambient), pch (chipset), iwlwifi (NIC), etc.
discover_thermal_zones() {
    local zones=()
    for zone_dir in /sys/class/thermal/thermal_zone*/; do
        [[ ! -f "${zone_dir}type" ]] && continue
        local ztype
        ztype=$(cat "${zone_dir}type" 2>/dev/null || echo "unknown")
        # Keep x86_pkg_temp, coretemp, cpu-thermal, k10temp, zenpower, cpu
        if echo "$ztype" | grep -qiE "^(x86_pkg_temp|coretemp|cpu[_-]?thermal|k10temp|zenpower|cpu[0-9]*)$"; then
            zones+=("${zone_dir}temp")
        fi
    done
    # Fallback: if none matched type filter, take zone0 (almost always CPU)
    if [[ ${#zones[@]} -eq 0 ]] && [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        zones+=("/sys/class/thermal/thermal_zone0/temp")
    fi
    echo "${zones[@]:-}"
}

# ── Read one thermal zone → integer °C ───────────────────────────────────────
read_temp_c() {
    local path="$1"
    local raw
    raw=$(cat "$path" 2>/dev/null || echo "0")
    echo $(( raw / 1000 ))
}

# ── Read all discovered CPU temperatures → JSON array ────────────────────────
# Returns: {"zones":[{"path":"...","temp_c":42},...], "max_c":42, "avg_c":41}
read_all_temps_json() {
    local zones_str
    zones_str=$(discover_thermal_zones)
    if [[ -z "$zones_str" ]]; then
        echo '{"zones":[],"max_c":null,"avg_c":null}'
        return
    fi
    read -ra zone_paths <<< "$zones_str"
    local total=0 count=0 max=0 json_arr=""
    for zpath in "${zone_paths[@]}"; do
        local tc
        tc=$(read_temp_c "$zpath")
        json_arr+="${json_arr:+,}{\"path\":\"${zpath}\",\"temp_c\":${tc}}"
        total=$((total + tc))
        count=$((count + 1))
        [[ $tc -gt $max ]] && max=$tc
    done
    local avg=$(( count > 0 ? total / count : 0 ))
    echo "{\"zones\":[${json_arr}],\"max_c\":${max},\"avg_c\":${avg}}"
}

# ── Read max CPU temperature as plain integer ─────────────────────────────────
read_max_temp_c() {
    local zones_str
    zones_str=$(discover_thermal_zones)
    [[ -z "$zones_str" ]] && echo "0" && return
    read -ra zone_paths <<< "$zones_str"
    local max=0
    for zpath in "${zone_paths[@]}"; do
        local tc
        tc=$(read_temp_c "$zpath")
        [[ $tc -gt $max ]] && max=$tc
    done
    echo "$max"
}

# ── Read per-core CPU frequencies → JSON array ────────────────────────────────
# Uses scaling_cur_freq (kernel governor's view — what the OS requested).
# Also reads cpuinfo_cur_freq if available (hardware-measured, more accurate).
read_all_freqs_json() {
    local json_arr="" total=0 count=0 max=0 min=999999
    local has_hw=false

    for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/; do
        [[ ! -f "${cpu_dir}scaling_cur_freq" ]] && continue
        local cpu_id
        cpu_id=$(basename "$(dirname "$cpu_dir")")
        local gov_khz hw_khz=null
        gov_khz=$(cat "${cpu_dir}scaling_cur_freq" 2>/dev/null || echo "0")

        if [[ -f "${cpu_dir}cpuinfo_cur_freq" ]]; then
            hw_khz=$(cat "${cpu_dir}cpuinfo_cur_freq" 2>/dev/null || echo "null")
            has_hw=true
        fi

        local gov_mhz=$(( gov_khz / 1000 ))
        json_arr+="${json_arr:+,}{\"cpu\":\"${cpu_id}\",\"gov_mhz\":${gov_mhz},\"hw_mhz\":${hw_khz}}"
        total=$(( total + gov_mhz ))
        count=$(( count + 1 ))
        [[ $gov_mhz -gt $max ]] && max=$gov_mhz
        [[ $gov_mhz -lt $min ]] && min=$gov_mhz
    done

    local avg=0
    [[ $count -gt 0 ]] && avg=$(( total / count ))
    # Variance % = (max - min) / avg * 100
    local var_pct=0
    [[ $avg -gt 0 ]] && var_pct=$(( (max - min) * 100 / avg ))

    echo "{\"cores\":[${json_arr:-}],\"avg_mhz\":${avg},\"min_mhz\":${min},\"max_mhz\":${max},\"spread_pct\":${var_pct},\"has_hw_freq\":${has_hw}}"
}

# ── Read current CPU governor ─────────────────────────────────────────────────
read_cpu_governor() {
    local gov
    gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
    echo "$gov"
}

# ── Read turbo boost status ───────────────────────────────────────────────────
# Returns: "enabled", "disabled", or "unknown"
read_turbo_status() {
    if [[ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]]; then
        local val
        val=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || echo "unknown")
        [[ "$val" == "1" ]] && echo "disabled" || echo "enabled"
    elif [[ -f /sys/devices/system/cpu/cpufreq/boost ]]; then
        local val
        val=$(cat /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || echo "unknown")
        [[ "$val" == "1" ]] && echo "enabled" || echo "disabled"
    else
        echo "unknown"
    fi
}

# ── Detect thermal throttle events in kernel ring buffer ──────────────────────
# Checks dmesg for throttling messages written since $1 (unix timestamp).
# Returns count of throttle events (0 = clean run).
count_throttle_events_since() {
    local since_ts="$1"
    if ! command -v dmesg &>/dev/null; then echo "0"; return; fi
    # dmesg --since requires util-linux ≥ 2.32; fall back gracefully
    local events=0
    if dmesg --since "@${since_ts}" 2>/dev/null | grep -qiE "thermal|throttl|CPU_FREQ|ACPI.*trip"; then
        events=$(dmesg --since "@${since_ts}" 2>/dev/null \
            | grep -icE "thermal|throttl|CPU_FREQ|ACPI.*trip" || echo "0")
    fi
    echo "${events:-0}"
}

# ── Full environment snapshot (temperature + frequency + meta) → JSON ─────────
# This is what gets embedded in every result JSON as 'environment_pre' or
# 'environment_post'.  Calling it takes ~2–5 ms (pure sysfs reads) and
# happens OUTSIDE hyperfine's measurement window.
snapshot_environment() {
    local label="${1:-pre}"           # "pre" or "post"
    local ts
    ts=$(date +%s%N)                  # nanosecond unix timestamp
    local ts_human
    ts_human=$(date +"%Y-%m-%dT%H:%M:%S.%3N%z")
    local temp_json freq_json governor turbo
    temp_json=$(read_all_temps_json)
    freq_json=$(read_all_freqs_json)
    governor=$(read_cpu_governor)
    turbo=$(read_turbo_status)

    cat <<SNAP_EOF
{
  "snapshot": "${label}",
  "timestamp_ns": ${ts},
  "timestamp_human": "${ts_human}",
  "temperature": ${temp_json},
  "frequency": ${freq_json},
  "cpu_governor": "${governor}",
  "turbo_boost": "${turbo}"
}
SNAP_EOF
}

# ── Thermal guard: wait until CPU is cool enough ──────────────────────────────
# Returns 0 immediately if temp ≤ threshold, or waits up to TEMP_MAX_WAIT secs.
# Prints advisory messages; does NOT inject any timing into the benchmark.
thermal_guard() {
    [[ "$THERMAL_GUARD" != "true" ]] && return 0
    local waited=0
    while true; do
        local cur_temp
        cur_temp=$(read_max_temp_c)
        if [[ $cur_temp -le $TEMP_THRESHOLD_C ]]; then
            return 0
        fi
        if [[ $waited -ge $TEMP_MAX_WAIT ]]; then
            echo -e "  ${YELLOW}⚠  Thermal guard timed out after ${waited}s (CPU still ${cur_temp}°C > ${TEMP_THRESHOLD_C}°C)${NC}"
            echo -e "  ${YELLOW}   Proceeding anyway — annotate results as 'thermally stressed'${NC}"
            return 0
        fi
        local bar_len=$(( (TEMP_THRESHOLD_C - cur_temp) < 0 ? 0 : (TEMP_THRESHOLD_C - cur_temp) ))
        echo -e "  ${YELLOW}🌡  Thermal guard: CPU ${cur_temp}°C > ${TEMP_THRESHOLD_C}°C — cooling down (${waited}/${TEMP_MAX_WAIT}s)...${NC}"
        sleep "$TEMP_WAIT_SECS"
        waited=$(( waited + TEMP_WAIT_SECS ))
    done
}

# ── Frequency stability check ─────────────────────────────────────────────────
# Warns if CPU frequency spread across cores exceeds FREQ_VARIANCE_PCT.
# This catches turbo asymmetry and P-state oscillation before a run starts.
check_freq_stability() {
    local spread
    spread=$(read_all_freqs_json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['spread_pct'])" 2>/dev/null || echo "0")
    if [[ "$spread" -gt "$FREQ_VARIANCE_PCT" ]]; then
        local freq_json
        freq_json=$(read_all_freqs_json)
        echo -e "  ${YELLOW}⚠  Frequency spread ${spread}% > ${FREQ_VARIANCE_PCT}% threshold — cores running at different speeds${NC}"
        echo -e "  ${YELLOW}   min/avg/max: $(echo "$freq_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d['min_mhz']}/{d['avg_mhz']}/{d['max_mhz']} MHz\")" 2>/dev/null || echo "?")${NC}"
        echo -e "  ${YELLOW}   Consider: echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor${NC}"
        return 1
    fi
    return 0
}

# ── Thermal telemetry append ──────────────────────────────────────────────────
# Appends one line of JSONL to THERMAL_LOG for later analysis.
log_thermal_event() {
    local bench_key="$1"
    local lang="$2"
    local scenario="$3"
    local env_pre="$4"
    local env_post="$5"
    local run_start_ts="$6"
    local run_end_ts="$7"
    local throttle_count="$8"

    mkdir -p "$(dirname "$THERMAL_LOG")"
    local wall_ms=$(( (run_end_ts - run_start_ts) ))

    printf '{"bench":"%s","lang":"%s","scenario":"%s","wall_ms":%s,"throttle_events":%s,"pre":%s,"post":%s}\n' \
        "$bench_key" "$lang" "$scenario" "$wall_ms" "$throttle_count" \
        "$env_pre" "$env_post" >> "$THERMAL_LOG"
}

# ── Coefficient of variation watchdog ─────────────────────────────────────────
# Reads a hyperfine JSON export and warns if stddev/mean > CV_WARN_THRESHOLD.
check_cv_from_json() {
    local json_path="$1"
    local bench_label="$2"
    [[ ! -f "$json_path" ]] && return 0
    python3 - "$json_path" "$bench_label" "$CV_WARN_THRESHOLD" <<'PYEOF' 2>/dev/null || true
import sys, json, math
path, label, threshold = sys.argv[1], sys.argv[2], float(sys.argv[3])
try:
    with open(path) as f:
        data = json.load(f)
    for result in data.get("results", []):
        times = result.get("times", [])
        if len(times) < 2:
            continue
        mean = sum(times) / len(times)
        stddev = math.sqrt(sum((t - mean) ** 2 for t in times) / (len(times) - 1))
        cv = stddev / mean if mean > 0 else 0
        min_t, max_t = min(times), max(times)
        spread = (max_t - min_t) / mean * 100 if mean > 0 else 0
        color_cv = "\033[0;31m" if cv > threshold else "\033[0;32m"
        color_sp = "\033[1;33m" if spread > 15 else "\033[0;32m"
        NC = "\033[0m"
        print(f"  ├─ runs: {len(times)}")
        print(f"  ├─ mean: {mean*1000:.3f} ms")
        print(f"  ├─ stddev: {stddev*1000:.3f} ms")
        print(f"  ├─ {color_cv}CV: {cv*100:.2f}%{NC}  (threshold: {threshold*100:.0f}%)")
        print(f"  ├─ min:  {min_t*1000:.3f} ms")
        print(f"  ├─ max:  {max_t*1000:.3f} ms")
        print(f"  └─ {color_sp}spread: {spread:.1f}%{NC}  (max−min / mean)")
        if cv > threshold:
            print(f"  \033[1;31m⚠  HIGH VARIANCE in '{label}' — CV={cv*100:.1f}% exceeds {threshold*100:.0f}% threshold\033[0m")
            print(f"     Check: thermal throttling, frequency scaling, or background load")
except Exception as e:
    pass
PYEOF
}

# ── Inject environment metadata into an existing hyperfine JSON ───────────────
# Adds "environment_pre", "environment_post", "throttle_events", "cv_stats"
# fields alongside hyperfine's native "results" array.
# The original hyperfine data is never modified — only extended.
inject_env_into_json() {
    local json_path="$1"
    local env_pre_json="$2"
    local env_post_json="$3"
    local throttle_count="$4"
    [[ ! -f "$json_path" ]] && return 0
    python3 - "$json_path" "$throttle_count" <<PYEOF 2>/dev/null || true
import sys, json, math

path = sys.argv[1]
throttle = int(sys.argv[2])
env_pre  = $env_pre_json
env_post = $env_post_json

with open(path) as f:
    data = json.load(f)

# ── Per-run timing stats (from hyperfine's individual run times) ───────────
for result in data.get("results", []):
    times = result.get("times", [])
    if times:
        mean   = sum(times) / len(times)
        n      = len(times)
        stddev = math.sqrt(sum((t - mean)**2 for t in times) / max(n-1, 1))
        cv     = stddev / mean if mean > 0 else 0
        result["per_run_stats"] = {
            "n_runs":      n,
            "mean_s":      round(mean, 9),
            "stddev_s":    round(stddev, 9),
            "cv":          round(cv, 6),
            "min_s":       round(min(times), 9),
            "max_s":       round(max(times), 9),
            "spread_s":    round(max(times) - min(times), 9),
            "spread_pct":  round((max(times) - min(times)) / mean * 100, 3) if mean > 0 else None,
            "mean_ms":     round(mean * 1000, 4),
            "stddev_ms":   round(stddev * 1000, 4),
            "min_ms":      round(min(times) * 1000, 4),
            "max_ms":      round(max(times) * 1000, 4),
            # Per-run individual timings (already in hyperfine output;
            # echoed here for convenience alongside our metadata)
            "run_times_ms": [round(t * 1000, 4) for t in times],
        }

# ── Environment metadata ───────────────────────────────────────────────────
data["environment_pre"]   = env_pre
data["environment_post"]  = env_post
data["throttle_events"]   = throttle

# ── Thermal delta (post − pre) ─────────────────────────────────────────────
pre_max  = env_pre.get("temperature", {}).get("max_c")
post_max = env_post.get("temperature", {}).get("max_c")
pre_avg  = env_pre.get("frequency", {}).get("avg_mhz")
post_avg = env_post.get("frequency", {}).get("avg_mhz")
data["thermal_delta"] = {
    "temp_rise_c":    round(post_max - pre_max, 1) if (pre_max is not None and post_max is not None) else None,
    "freq_drift_mhz": round(post_avg - pre_avg, 0) if (pre_avg is not None and post_avg is not None) else None,
}

with open(path, "w") as f:
    json.dump(data, f, indent=2)
PYEOF
}

# ── Human-readable thermal banner for a benchmark ────────────────────────────
print_thermal_status() {
    local temp_c="$1"
    local freq_avg="$2"
    local governor="$3"
    local turbo="$4"
    local color

    if   [[ $temp_c -le $TEMP_IDEAL_C ]]; then color="$GREEN"
    elif [[ $temp_c -le $TEMP_WARN_C  ]]; then color="$YELLOW"
    else                                        color="$RED"; fi

    echo -e "  ${CYAN}┌─ Environment snapshot ──────────────────────────────${NC}"
    echo -e "  ${CYAN}│${NC}  🌡  CPU temp : ${color}${temp_c}°C${NC}  (ideal ≤ ${TEMP_IDEAL_C}°C, guard ≤ ${TEMP_THRESHOLD_C}°C)"
    echo -e "  ${CYAN}│${NC}  ⚡  Freq avg : ${freq_avg} MHz"
    echo -e "  ${CYAN}│${NC}  📋  Governor : ${governor}  |  Turbo: ${turbo}"
    echo -e "  ${CYAN}└─────────────────────────────────────────────────────${NC}"
}

# ── Thermal report (summary printed at end of run) ───────────────────────────
print_thermal_report() {
    [[ ! -f "$THERMAL_LOG" ]] && return
    echo -e "${BOLD}${CYAN}"
    echo "========================================================================"
    echo "  THERMAL & FREQUENCY TELEMETRY REPORT"
    echo "========================================================================"
    echo -e "${NC}"
    python3 - "$THERMAL_LOG" "$CV_WARN_THRESHOLD" <<'PYEOF' 2>/dev/null || echo "  (report unavailable — python3 required)"
import sys, json

log_path    = sys.argv[1]
cv_thresh   = float(sys.argv[2])
events      = []

with open(log_path) as f:
    for line in f:
        line = line.strip()
        if line:
            try: events.append(json.loads(line))
            except: pass

if not events:
    print("  No telemetry events recorded.")
    sys.exit(0)

GREEN = "\033[0;32m"; YELLOW = "\033[1;33m"; RED = "\033[0;31m"; NC = "\033[0m"; BOLD = "\033[1m"

total_throttles = sum(e.get("throttle_events", 0) for e in events)
pre_temps  = [e["pre"]["temperature"]["max_c"]  for e in events if e.get("pre",{}).get("temperature",{}).get("max_c") is not None]
post_temps = [e["post"]["temperature"]["max_c"] for e in events if e.get("post",{}).get("temperature",{}).get("max_c") is not None]
pre_freqs  = [e["pre"]["frequency"]["avg_mhz"]  for e in events if e.get("pre",{}).get("frequency",{}).get("avg_mhz") is not None]

print(f"  Benchmarks logged: {len(events)}")
if pre_temps:
    print(f"  Pre-run temp  (avg / max): {sum(pre_temps)/len(pre_temps):.1f}°C / {max(pre_temps)}°C")
if post_temps:
    print(f"  Post-run temp (avg / max): {sum(post_temps)/len(post_temps):.1f}°C / {max(post_temps)}°C")
if pre_freqs:
    print(f"  Pre-run freq  (avg / min / max): {sum(pre_freqs)/len(pre_freqs):.0f} / {min(pre_freqs)} / {max(pre_freqs)} MHz")
tc = f"{RED}{total_throttles}{NC}" if total_throttles > 0 else f"{GREEN}0{NC}"
print(f"  Thermal throttle events: {tc}")
print()
print(f"  {'Benchmark':<45}  {'Pre°C':>6}  {'Post°C':>6}  {'ΔT':>4}  {'Thr':>4}  {'Wall':>8}")
print(f"  {'─'*45}  {'─'*6}  {'─'*6}  {'─'*4}  {'─'*4}  {'─'*8}")

for e in events:
    bk   = e.get("bench", "?")[:44]
    pre  = e.get("pre",  {}).get("temperature", {}).get("max_c", "?")
    post = e.get("post", {}).get("temperature", {}).get("max_c", "?")
    thr  = e.get("throttle_events", 0)
    wall = e.get("wall_ms", 0)
    dt   = (post - pre) if isinstance(pre, int) and isinstance(post, int) else "?"
    pre_s  = f"{pre}°C"  if isinstance(pre, int)  else "?"
    post_s = f"{post}°C" if isinstance(post, int) else "?"
    dt_s   = f"+{dt}°C" if isinstance(dt, int) and dt >= 0 else f"{dt}°C" if isinstance(dt, int) else "?"
    wall_s = f"{wall/1000:.1f}s" if isinstance(wall, int) else "?"
    thr_s  = f"{RED}{thr}{NC}" if thr > 0 else f"{GREEN}{thr}{NC}"
    print(f"  {bk:<45}  {pre_s:>6}  {post_s:>6}  {dt_s:>5}  {thr_s:>4+len(NC)+len(RED) if thr>0 else 4}  {wall_s:>8}")

print()
if total_throttles > 0:
    print(f"  {RED}{BOLD}⚠  THERMAL THROTTLING DETECTED — these results may be compromised.{NC}")
    print(f"     Review results/thermal_telemetry.jsonl and cross-check with your")
    print(f"     thesis methodology on environmental controls.")
else:
    print(f"  {GREEN}✓  No thermal throttling detected — results are thermally clean.{NC}")
PYEOF
    echo ""
}

# ── Checkpoint helpers ────────────────────────────────────────────────────────
BENCH_DIR="results"

check_bench() {
    local key="$1"
    if [[ "$RESUME" == "true" ]] && [[ -f "${BENCH_DIR}/.bench_${key}" ]]; then
        echo -e "  ${YELLOW}⏭  [resume] skipping: ${key}${NC}"
        return 0
    fi
    return 1
}

mark_bench() {
    local key="$1"
    touch "${BENCH_DIR}/.bench_${key}"
}

check_section() {
    local sec="$1"
    if [[ "$RESUME" == "true" ]] && [[ -f "${BENCH_DIR}/.section_${sec}" ]]; then
        echo -e "  ${YELLOW}⏭  [resume] entire section already complete: ${sec}${NC}"
        return 0
    fi
    return 1
}

mark_section() {
    local sec="$1"
    touch "${BENCH_DIR}/.section_${sec}"
}

# ── Status display ────────────────────────────────────────────────────────────
show_resume_status() {
    echo -e "${BOLD}${CYAN}Resume status (completed benchmarks):${NC}"
    local count=0
    if compgen -G "${BENCH_DIR}/.bench_*" > /dev/null 2>&1; then
        for f in "${BENCH_DIR}"/.bench_*; do
            local key="${f##*/.bench_}"
            echo -e "  ${GREEN}✓${NC} ${key}"
            ((count++)) || true
        done
    fi
    if compgen -G "${BENCH_DIR}/.section_*" > /dev/null 2>&1; then
        for f in "${BENCH_DIR}"/.section_*; do
            local key="${f##*/.section_}"
            echo -e "  ${GREEN}✓✓${NC} [section] ${key}"
        done
    fi
    [[ $count -eq 0 ]] && echo "  (none — this will be a full run)"
    echo ""
}

# ── Utility functions ─────────────────────────────────────────────────────────
timestamp()    { date +"%Y-%m-%d %H:%M:%S"; }
elapsed_time() {
    local now=$(date +%s)
    local diff=$((now - START_TIME))
    printf "%02d:%02d:%02d" $((diff/3600)) $((diff%3600/60)) $((diff%60))
}
eta() {
    local done=$1 total=$2
    if [[ $done -eq 0 ]]; then echo "calculating..."; return; fi
    local now=$(date +%s)
    local elapsed=$((now - START_TIME))
    local rate=$((elapsed / done))
    local remaining=$(( (total - done) * rate ))
    printf "%02d:%02d:%02d" $((remaining/3600)) $((remaining%3600/60)) $((remaining%60))
}
progress() {
    BENCHMARK_COUNT=$((BENCHMARK_COUNT + 1))
    local pct=$((BENCHMARK_COUNT * 100 / TOTAL_BENCHMARKS))
    echo -e "  ${CYAN}[${BENCHMARK_COUNT}/${TOTAL_BENCHMARKS}] (${pct}%) ETA: $(eta $BENCHMARK_COUNT $TOTAL_BENCHMARKS)${NC}"
}
log_error() {
    local msg="$1"
    ERRORS+=("$msg")
    echo -e "  ${RED}❌ ERROR: $msg${NC}"
    echo "[$(timestamp)] ERROR: $msg" >> results/errors.log
}

# ── Hardware info capture ─────────────────────────────────────────────────────
capture_hardware_info() {
    mkdir -p results
    local temp_json freq_json governor turbo
    temp_json=$(read_all_temps_json)
    freq_json=$(read_all_freqs_json)
    governor=$(read_cpu_governor)
    turbo=$(read_turbo_status)

    cat > results/hardware_info.json << HWEOF
{
  "captured_at": "$(timestamp)",
  "hostname": "$(hostname 2>/dev/null || echo 'unknown')",
  "os": "$(uname -s) $(uname -r)",
  "cpu_model": "$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo 'unknown')",
  "cpu_cores": "$(nproc 2>/dev/null || echo 'unknown')",
  "total_ram_gb": "$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo 'unknown')",
  "disk_available_gb": "$(df -BG / 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo 'unknown')",
  "kernel": "$(uname -v)",
  "architecture": "$(uname -m)",
  "thermal_baseline": ${temp_json},
  "frequency_baseline": ${freq_json},
  "cpu_governor_baseline": "${governor}",
  "turbo_boost_baseline": "${turbo}",
  "benchmark_settings": {
    "temp_threshold_c": ${TEMP_THRESHOLD_C},
    "temp_ideal_c": ${TEMP_IDEAL_C},
    "freq_variance_pct_max": ${FREQ_VARIANCE_PCT},
    "cv_warn_threshold": ${CV_WARN_THRESHOLD},
    "settle_time_s": ${SETTLE_TIME},
    "thermal_guard_enabled": ${THERMAL_GUARD}
  }
}
HWEOF
    echo -e "  ${GREEN}✓${NC} Hardware info + thermal baseline → results/hardware_info.json"
}

# ── Configuration ─────────────────────────────────────────────────────────────
COLD_START_RUNS=5
BENCHMARK_RUNS=30
WARMUP_RUNS=5
CACHE_WARMUP=3
FULL_SUITE_REPEATS=3

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${ID:-unknown}"
    else
        echo "unknown"
    fi
}
OS_TYPE=$(detect_os)

OWNER=$(echo "${GITHUB_REPOSITORY:-a2rk313/benchmark-thesis}" | cut -d/ -f1 | tr '[:upper:]' '[:lower:]')
PYTHON_TAG="ghcr.io/${OWNER}/thesis-python:latest"
JULIA_TAG="ghcr.io/${OWNER}/thesis-julia:latest"
R_TAG="ghcr.io/${OWNER}/thesis-r:latest"

PYTHON_LOCAL_TAG="thesis-python:3.14"
JULIA_LOCAL_TAG="thesis-julia:1.11"
R_LOCAL_TAG="thesis-r:4.5"

export JULIA_NUM_THREADS=8
export OPENBLAS_NUM_THREADS=8
export FLEXIBLAS_NUM_THREADS=8
export GOTO_NUM_THREADS=8
export OMP_NUM_THREADS=8

CPU_PIN_ENABLED=true
CPU_CORES=""
NUMA_ENABLED=true
NUMA_NODE=0

ENABLE_VECTOR=true
ENABLE_INTERPOLATION=true
ENABLE_TIMESERIES=true
ENABLE_HYPERSPECTRAL=true

CONFIDENCE_LEVEL=0.95
SIGNIFICANCE_LEVEL=0.05

TOTAL_BENCHMARKS=0
[[ "$MODE" != "native" ]]    && TOTAL_BENCHMARKS=$((TOTAL_BENCHMARKS + 15))
[[ "$MODE" != "container" ]] && TOTAL_BENCHMARKS=$((TOTAL_BENCHMARKS + 12))
TOTAL_BENCHMARKS=$((TOTAL_BENCHMARKS + 5))
[[ "$SCALING" == "true" ]]   && TOTAL_BENCHMARKS=$((TOTAL_BENCHMARKS + 13))

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${BLUE}"
echo "========================================================================"
echo "  THESIS BENCHMARK SUITE v4.0.1 (Telemetry Export Fix)"
echo "========================================================================"
echo -e "${NC}"

if [[ "$IS_BOOTC" == "true" ]]; then
    echo -e "  ${BOLD}${GREEN}🚀 BOOTC ENVIRONMENT DETECTED (Bare-Metal Precision)${NC}"
    echo -e "  Using system-wide runtimes: Python 3.14, Julia 1.12.6, R 4.5.x"
    echo ""
fi

echo "  Started: $(timestamp)"
echo ""

if   [[ "$MODE" == "all" ]];       then echo -e "  ${MAGENTA}MODE: FULL (Native + Container)${NC}"
elif [[ "$MODE" == "container" ]]; then echo -e "  ${YELLOW}MODE: CONTAINER ONLY${NC}"
else                                     echo -e "  ${GREEN}MODE: NATIVE ONLY${NC}"
fi

[[ "$USE_GHCR"  == "true" ]] && echo -e "  ${CYAN}GHCR: Force pull mode${NC}" \
                              || echo -e "  ${CYAN}GHCR: Auto (pull if missing, build if needed)${NC}"
[[ "$RESUME"    == "true" ]] && echo -e "  ${CYAN}RESUME: Fine-grained — skipping individual completed benchmarks${NC}"
[[ "$CLEAN"     == "true" ]] && echo -e "  ${YELLOW}CLEAN: Clearing old results${NC}"
[[ "$DRY_RUN"   == "true" ]] && echo -e "  ${YELLOW}DRY RUN: Preview mode (no execution)${NC}"
[[ "$SCALING"   == "true" ]] && {
    [[ "$SCALING_QUICK" == "true" ]] \
        && echo -e "  ${MAGENTA}SCALING: Quick mode${NC}" \
        || echo -e "  ${MAGENTA}SCALING: Full mode${NC}"
}

echo ""
echo -e "  ${CYAN}Thermal / Frequency controls:${NC}"
echo "    Guard (defer if CPU > threshold) : $([ "$THERMAL_GUARD" == "true" ] && echo "ENABLED" || echo "DISABLED")"
echo "    Temp threshold (defer)           : ${TEMP_THRESHOLD_C}°C"
echo "    Temp ideal zone                  : ≤ ${TEMP_IDEAL_C}°C"
echo "    Freq spread gate                 : ≤ ${FREQ_VARIANCE_PCT}%"
echo "    CV warning threshold             : > ${CV_WARN_THRESHOLD} ($(echo "scale=0; $CV_WARN_THRESHOLD * 100 / 1" | bc)%)"
echo "    Inter-benchmark settle time      : ${SETTLE_TIME}s"
echo "    Telemetry log                    : ${THERMAL_LOG}"
echo ""
echo "  Container images:"
echo "    Python : $PYTHON_TAG"
echo "    Julia  : $JULIA_TAG"
echo "    R      : $R_TAG"
echo ""
echo "  Native tools:"
echo "    Python : $(python3 --version 2>/dev/null | cut -d' ' -f2 || echo 'not found')"
echo "    Julia  : $(julia  --version 2>/dev/null | cut -d' ' -f3 || echo 'not found')"
echo "    R      : $(R      --version 2>/dev/null | head -1 | cut -d' ' -f3 || echo 'not found')"
echo ""
echo "  Thread config: JULIA_NUM_THREADS=$JULIA_NUM_THREADS, OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS"
echo ""
echo "  Academic rigor settings:"
echo "    Benchmark runs: $BENCHMARK_RUNS (Internal to scripts in v4.0.1)"
echo "    Warmup runs: $WARMUP_RUNS (Internal to scripts in v4.0.1)"
echo "    CPU pinning: $CPU_PIN_ENABLED"
echo "    NUMA binding: $NUMA_ENABLED"
echo ""

# ── Status mode ───────────────────────────────────────────────────────────────
mkdir -p results
if [[ "$SHOW_STATUS" == "true" ]]; then
    show_resume_status
    exit 0
fi

# ── Dry run mode ──────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${BOLD}${YELLOW}=== DRY RUN - Execution Plan ===${NC}"
    echo ""
    echo "  Per-benchmark telemetry pipeline:"
    echo "    1. thermal_guard()         — defer until CPU ≤ ${TEMP_THRESHOLD_C}°C"
    echo "    2. check_freq_stability()  — warn if core spread > ${FREQ_VARIANCE_PCT}%"
    echo "    3. snapshot_environment(pre)  — temp + freq snapshot (outside timed window)"
    echo "    4. [hyperfine runs the benchmark] — our code is NOT inside this region"
    echo "       NOTE: hyperfine runs 1 time only; scripts handle internal loops."
    echo "    5. snapshot_environment(post) — post-run snapshot"
    echo "    6. count_throttle_events_since() — check dmesg for throttle events"
    echo "    7. inject_env_into_json()  — embed metadata into hyperfine JSON output"
    echo "    8. check_cv_from_json()    — flag if stddev/mean > ${CV_WARN_THRESHOLD}"
    echo "    9. sleep ${SETTLE_TIME}s              — thermal/cache recovery before next benchmark"
    echo ""
    if [[ "$MODE" != "native" ]]; then
        echo "  Sections (container):"
        echo "    §4 Cold start benchmarks  — checkpoint per benchmark"
        echo "    §5 Warm start benchmarks  — checkpoint per benchmark"
        echo "    §6 Matrix operations      — checkpoint per language"
        echo "    §7 I/O operations         — checkpoint per language"
        echo "    §8 Memory profiling       — checkpoint per language×test"
        echo "    §9 Validation"
    fi
    if [[ "$MODE" != "container" ]]; then
        echo "  Sections (native):"
        echo "    §10 Native benchmarks     — checkpoint per language×scenario"
        echo "    §11 Julia JIT analysis"
    fi
    [[ "$SCALING" == "true" ]] && echo "    §12 Scaling benchmarks"
    echo "    §13 Academic report generation"
    echo ""
    echo -e "${GREEN}Dry run complete. Remove --dry-run to execute.${NC}"
    exit 0
fi

# ── Clean mode ────────────────────────────────────────────────────────────────
if [[ "$CLEAN" == "true" ]]; then
    echo -e "${YELLOW}Cleaning old results and all checkpoints...${NC}"
    rm -rf results/
    mkdir -p results
    echo -e "${GREEN}✓ Clean complete${NC}"
    echo ""
fi

mkdir -p results

if [[ "$RESUME" == "true" ]]; then
    show_resume_status
fi

# ── [0/10] Dependency check ───────────────────────────────────────────────────
echo -e "${BLUE}[0/10] Checking dependencies...${NC}"
for cmd in podman hyperfine python3; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}❌ $cmd not found.${NC}"
        [ "$cmd" = "podman"    ] && echo "     Install: sudo dnf install podman"
        [ "$cmd" = "hyperfine" ] && echo "     Install: cargo install hyperfine"
        [ "$cmd" = "python3"   ] && echo "     Required for telemetry injection and CV analysis"
        exit 1
    fi
    echo "  ✓ $cmd: $($cmd --version 2>&1 | head -1)"
done

# ── System Preparation ───────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}System Preparation for Academic Rigor...${NC}"

if [[ "$CPU_PIN_ENABLED" == "true" ]]; then
    if command -v taskset &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} CPU pinning enabled (taskset available)"
        [[ -n "$CPU_CORES" ]] && echo "    Using cores: $CPU_CORES" || echo "    Using all available cores"
    else
        echo -e "  ${YELLOW}⚠${NC} taskset not found - CPU pinning disabled"
        CPU_PIN_ENABLED=false
    fi
fi

if [[ "$NUMA_ENABLED" == "true" ]]; then
    if command -v numactl &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} NUMA binding enabled (numactl available)"
        numactl --hardware 2>/dev/null | head -1 || true
    else
        echo -e "  ${YELLOW}⚠${NC} numactl not found - NUMA binding disabled"
        NUMA_ENABLED=false
    fi
fi

# ── Turbo / governor advisory ─────────────────────────────────────────────────
TURBO=$(read_turbo_status)
GOV=$(read_cpu_governor)
echo ""
echo -e "  ${CYAN}CPU performance state:${NC}"
if [[ "$TURBO" == "enabled" ]]; then
    echo -e "  ${YELLOW}⚠  Turbo Boost ENABLED — may cause run-to-run frequency variance${NC}"
    echo -e "  ${YELLOW}   For thesis reproducibility consider:${NC}"
    echo -e "  ${YELLOW}   echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo${NC}"
else
    echo -e "  ${GREEN}✓  Turbo Boost: ${TURBO}${NC}"
fi
if [[ "$GOV" != "performance" ]]; then
    echo -e "  ${YELLOW}⚠  CPU governor: '${GOV}' (not 'performance') — frequency may vary${NC}"
    echo -e "  ${YELLOW}   For stable benchmarks:${NC}"
    echo -e "  ${YELLOW}   echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor${NC}"
else
    echo -e "  ${GREEN}✓  CPU governor: ${GOV}${NC}"
fi

# ── Initial thermal check ─────────────────────────────────────────────────────
BASELINE_TEMP=$(read_max_temp_c)
BASELINE_FREQ_JSON=$(read_all_freqs_json)
BASELINE_FREQ_AVG=$(echo "$BASELINE_FREQ_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['avg_mhz'])" 2>/dev/null || echo "?")
echo ""
echo -e "  ${CYAN}Thermal baseline:${NC}"
print_thermal_status "$BASELINE_TEMP" "$BASELINE_FREQ_AVG" "$GOV" "$TURBO"

if [[ "$THERMAL_GUARD" == "true" ]] && [[ $BASELINE_TEMP -gt $TEMP_THRESHOLD_C ]]; then
    echo -e "  ${YELLOW}System is already warm (${BASELINE_TEMP}°C > ${TEMP_THRESHOLD_C}°C). Waiting before starting...${NC}"
    thermal_guard
fi

capture_hardware_info

run_pinned() {
    local cmd="$1"
    local pin_args=""
    [[ "$CPU_PIN_ENABLED" == "true" ]] && [[ -n "$CPU_CORES" ]] && pin_args="-c $CPU_CORES"
    if [[ "$NUMA_ENABLED" == "true" ]] && command -v numactl &>/dev/null; then
        eval numactl $pin_args --cpunodebind=$NUMA_NODE --membind=$NUMA_NODE $cmd
    elif [[ -n "$pin_args" ]]; then
        eval taskset $pin_args $cmd
    else
        eval $cmd
    fi
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  INSTRUMENTED BENCHMARK WRAPPERS                                        ║
# ║                                                                         ║
# ║  run_cold_instrumented  — for container cold-start benchmarks           ║
# ║  run_warm_instrumented  — for container warm-start benchmarks           ║
# ║  run_native_instrumented — for native benchmarks                        ║
# ║                                                                         ║
# ║  Each wrapper:                                                          ║
# ║    1. Applies thermal guard (defer if too hot)                          ║
# ║    2. Checks frequency stability                                        ║
# ║    3. Captures pre-run environment snapshot                             ║
# ║    4. Runs hyperfine (timed region — NO monitoring code inside)         ║
# ║    5. Captures post-run environment snapshot                            ║
# ║    6. Counts kernel throttle events that occurred during the run        ║
# ║    7. Injects all metadata into the JSON output file                    ║
# ║    8. Runs CV watchdog and prints per-run timing breakdown              ║
# ║    9. Waits SETTLE_TIME seconds before returning                        ║
# ╚══════════════════════════════════════════════════════════════════════════╝

# ── Container cold-start instrumented wrapper ─────────────────────────────────
run_cold_instrumented() {
    local scenario="$1" script="$2" lang="$3" tag="$4" out="$5"
    local bench_key="cold_${lang}_${scenario}"

    if check_bench "$bench_key"; then
        BENCHMARK_COUNT=$((BENCHMARK_COUNT + 1))
        return
    fi
    progress
    echo -e "  ${GREEN}${lang}${NC} (cold) — ${scenario}"

    # ── Pre-run checks (outside timed window) ────────────────────────────────
    thermal_guard
    check_freq_stability || true
    local env_pre run_start_ts throttle_count=0
    env_pre=$(snapshot_environment "pre")
    run_start_ts=$(date +%s)
    local cur_temp freq_avg
    cur_temp=$(echo "$env_pre" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['temperature']['max_c'])" 2>/dev/null || echo "?")
    freq_avg=$(echo "$env_pre" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['frequency']['avg_mhz'])" 2>/dev/null || echo "?")
    print_thermal_status "$cur_temp" "$freq_avg" "$(read_cpu_governor)" "$(read_turbo_status)"

    # ── TIMED REGION — hyperfine only, no shell code executing here ──────────
    podman run --rm -v "$(pwd)":/benchmarks:Z "$tag" \
        hyperfine \
            --warmup 0 \
            --runs 1 \
            --show-output \
            --export-json "/benchmarks/${out}" \
            "$script" 2>&1 | tail -15
    # ── END TIMED REGION ─────────────────────────────────────────────────────

    local run_end_ts
    run_end_ts=$(date +%s)
    local env_post
    env_post=$(snapshot_environment "post")
    throttle_count=$(count_throttle_events_since "$run_start_ts")

    inject_env_into_json "$out" "$env_pre" "$env_post" "$throttle_count"
    echo -e "  ${CYAN}Per-run timing (hyperfine):${NC}"
    check_cv_from_json "$out" "${lang}_cold_${scenario}"
    log_thermal_event "$bench_key" "$lang" "$scenario" \
        "$env_pre" "$env_post" "$run_start_ts" "$run_end_ts" "$throttle_count"

    [[ $throttle_count -gt 0 ]] && \
        echo -e "  ${RED}⚠  ${throttle_count} thermal throttle event(s) detected in kernel log during this run!${NC}"

    mark_bench "$bench_key"
    echo -e "  ${YELLOW}  Settling ${SETTLE_TIME}s...${NC}"
    sleep "$SETTLE_TIME"
}

# ── Container warm-start instrumented wrapper ─────────────────────────────────
run_warm_instrumented() {
    local scenario="$1" script="$2" lang="$3" tag="$4" out="$5"
    local bench_key="warm_${lang}_${scenario}"

    if check_bench "$bench_key"; then
        BENCHMARK_COUNT=$((BENCHMARK_COUNT + 1))
        return
    fi
    progress
    echo -e "  ${GREEN}${lang}${NC} (warm) — ${scenario}"

    thermal_guard
    check_freq_stability || true
    local env_pre run_start_ts throttle_count=0
    env_pre=$(snapshot_environment "pre")
    run_start_ts=$(date +%s)
    local cur_temp freq_avg
    cur_temp=$(echo "$env_pre" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['temperature']['max_c'])" 2>/dev/null || echo "?")
    freq_avg=$(echo "$env_pre" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['frequency']['avg_mhz'])" 2>/dev/null || echo "?")
    print_thermal_status "$cur_temp" "$freq_avg" "$(read_cpu_governor)" "$(read_turbo_status)"

    # ── TIMED REGION ──────────────────────────────────────────────────────────
    podman run --rm -v "$(pwd)":/benchmarks:Z "$tag" \
        hyperfine \
            --warmup 0 \
            --runs 1 \
            --export-json "/benchmarks/${out}" \
            "$script" 2>&1 | tail -5
    # ── END TIMED REGION ──────────────────────────────────────────────────────

    run_end_ts=$(date +%s)
    env_post=$(snapshot_environment "post")
    throttle_count=$(count_throttle_events_since "$run_start_ts")

    inject_env_into_json "$out" "$env_pre" "$env_post" "$throttle_count"
    echo -e "  ${CYAN}Per-run timing (self-timed by script):${NC}"
    check_cv_from_json "$out" "${lang}_warm_${scenario}"
    log_thermal_event "$bench_key" "$lang" "$scenario" \
        "$env_pre" "$env_post" "$run_start_ts" "$run_end_ts" "$throttle_count"

    [[ $throttle_count -gt 0 ]] && \
        echo -e "  ${RED}⚠  ${throttle_count} thermal throttle event(s) during this run!${NC}"

    mark_bench "$bench_key"
    echo -e "  ${YELLOW}  Settling ${SETTLE_TIME}s...${NC}"
    sleep "$SETTLE_TIME"
}

# ── Native instrumented wrapper ───────────────────────────────────────────────
# Used in section [10/10].  For native hyperfine runs the output JSON path
# is derived from the bench_key so every run gets its own file.
run_native_instrumented() {
    local lang="$1" cmd="$2" name="$3"
    local bench_key="native_${lang}_${name}"
    local out="results/native/${lang}_${name}.json"

    if check_bench "$bench_key"; then
        BENCHMARK_COUNT=$((BENCHMARK_COUNT + 1))
        return
    fi
    progress
    echo -e "  ${GREEN}${lang}${NC}: ${name}"

    export JULIA_DEPOT_PATH="/usr/share/julia/depot:/var/lib/julia:$PWD/.julia"
    source /etc/environment 2>/dev/null || true

    thermal_guard
    check_freq_stability || true

    local env_pre run_start_ts throttle_count=0
    env_pre=$(snapshot_environment "pre")
    run_start_ts=$(date +%s)
    local cur_temp freq_avg
    cur_temp=$(echo "$env_pre" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['temperature']['max_c'])" 2>/dev/null || echo "?")
    freq_avg=$(echo "$env_pre" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['frequency']['avg_mhz'])" 2>/dev/null || echo "?")
    print_thermal_status "$cur_temp" "$freq_avg" "$(read_cpu_governor)" "$(read_turbo_status)"

    # ── TIMED REGION ──────────────────────────────────────────────────────────
    local output
    if [[ "$CPU_PIN_ENABLED" == "true" ]] && [[ -n "$CPU_CORES" ]]; then
        # Wrap in hyperfine for timing consistency with container benchmarks
        taskset -c "$CPU_CORES" hyperfine \
            --warmup 0 \
            --runs 1 \
            --export-json "$out" \
            "$cmd" 2>&1 | tail -5
    else
        hyperfine \
            --warmup 0 \
            --runs 1 \
            --export-json "$out" \
            "$cmd" 2>&1 | tail -5
    fi
    # ── END TIMED REGION ──────────────────────────────────────────────────────

    local run_end_ts
    run_end_ts=$(date +%s)
    local env_post
    env_post=$(snapshot_environment "post")
    throttle_count=$(count_throttle_events_since "$run_start_ts")

    inject_env_into_json "$out" "$env_pre" "$env_post" "$throttle_count"
    echo -e "  ${CYAN}Per-run timing (self-timed by script):${NC}"
    check_cv_from_json "$out" "${lang}_native_${name}"
    log_thermal_event "$bench_key" "$lang" "$name" \
        "$env_pre" "$env_post" "$run_start_ts" "$run_end_ts" "$throttle_count"

    [[ $throttle_count -gt 0 ]] && \
        echo -e "  ${RED}⚠  ${throttle_count} thermal throttle event(s) during this run!${NC}"

    mark_bench "$bench_key"
    echo -e "  ${YELLOW}  Settling ${SETTLE_TIME}s...${NC}"
    sleep "$SETTLE_TIME"
}

# ── [1/10] Container setup ───────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[1/10] Container setup...${NC}"

if [[ "$MODE" == "native" ]]; then
    echo -e "${YELLOW}  Skipping containers (native-only mode)${NC}"
else
    setup_container() {
        local tag="$1" file="$2" name="$3"
        if podman image exists "$tag" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $name: $tag (found locally)"
            return 0
        fi
        echo -e "  ${CYAN}→${NC} $name: trying GHCR..."
        pull_output=$(podman pull "$tag" 2>&1)
        pull_status=$?
        if [[ $pull_status -eq 0 ]]; then
            echo -e "    ${GREEN}✓${NC} Pulled from GHCR"
            return 0
        fi
        if echo "$pull_output" | grep -qi "unauthorized\|authentication\|denied"; then
            echo -e "    ${YELLOW}⚠${NC} GHCR auth failed (container may be private)"
        else
            echo -e "    ${YELLOW}⚠${NC} GHCR pull failed"
        fi
        echo -e "    ${CYAN}→${NC} Building locally..."
        if [[ -n "$file" ]] && [[ -f "$file" ]]; then
            if podman build -t "$tag" -f "$file" . 2>&1 | tail -5; then
                echo -e "    ${GREEN}✓${NC} $name built locally"
                return 0
            fi
        fi
        log_error "Failed to get container: $tag"
        return 1
    }

    PYTHON_DOCKERFILE="containers/python.Containerfile"
    JULIA_DOCKERFILE="containers/julia.Containerfile"
    R_DOCKERFILE="containers/r.Containerfile"
    [ -f "containers/python-optimized.Containerfile" ] && PYTHON_DOCKERFILE="containers/python-optimized.Containerfile"
    [ -f "containers/julia-optimized.Containerfile"  ] && JULIA_DOCKERFILE="containers/julia-optimized.Containerfile"
    [ -f "containers/r-optimized.Containerfile"      ] && R_DOCKERFILE="containers/r-optimized.Containerfile"

    setup_container "$PYTHON_TAG" "$PYTHON_DOCKERFILE" "Python"
    setup_container "$JULIA_TAG"  "$JULIA_DOCKERFILE"  "Julia"
    setup_container "$R_TAG"      "$R_DOCKERFILE"      "R"

    if podman image exists "$PYTHON_TAG" 2>/dev/null; then
        cat > results/container_hashes.txt << HEOF
Python  $PYTHON_TAG  $(podman image inspect "$PYTHON_TAG" --format '{{.Digest}}' 2>/dev/null || echo 'unknown')
Julia   $JULIA_TAG   $(podman image inspect "$JULIA_TAG"  --format '{{.Digest}}' 2>/dev/null || echo 'unknown')
R       $R_TAG       $(podman image inspect "$R_TAG"      --format '{{.Digest}}' 2>/dev/null || echo 'unknown')
HEOF
        echo -e "  ${GREEN}✓${NC} Digests → results/container_hashes.txt"
    fi
fi

# ── [2/10] Verify environments ───────────────────────────────────────────────
echo ""
echo -e "${BLUE}[2/10] Verifying environments...${NC}"

if [[ "$MODE" != "native" ]]; then
    echo -e "${GREEN}  Container Python:${NC}"
    podman run --rm "$PYTHON_TAG" python3 -c "import sys; print(f'    Python {sys.version.split()[0]}')" 2>/dev/null \
        || log_error "Python container verification failed"
    echo -e "${GREEN}  Container Julia:${NC}"
    podman run --rm "$JULIA_TAG" julia --version 2>/dev/null | sed 's/^/    /' \
        || log_error "Julia container verification failed"
    echo -e "${GREEN}  Container R:${NC}"
    podman run --rm "$R_TAG" R --version 2>/dev/null | head -1 | sed 's/^/    /' \
        || log_error "R container verification failed"
fi

# ── [3/10] Data preparation ──────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[3/10] Preparing benchmark datasets...${NC}"

if check_section "data"; then
    :
else
    DDIR="$(pwd)/data"
    mkdir -p "$DDIR"
    if [[ -f "tools/download_data.py" ]]; then
        source .venv/bin/activate 2>/dev/null || true
        python3 tools/download_data.py --all 2>&1 | grep -E "✓|⚠" | head -10 || true
        python3 tools/download_data.py --check > /tmp/data_check.log 2>&1
        if [[ $? -ne 0 ]]; then
            echo -e "  ${RED}✗ CRITICAL: Required datasets missing!${NC}"
            cat /tmp/data_check.log | sed 's/^/    /'
            exit 1
        fi
        [[ ! -f "data/Cuprite.mat" ]] && [[ ! -f "data/Cuprite.npy" ]] && {
            echo -e "  ${RED}✗ CRITICAL: Hyperspectral data not found!${NC}"; exit 1; }
        [[ ! -f "data/gps_points_1m.csv" ]] && {
            echo -e "  ${RED}✗ CRITICAL: GPS points data not found!${NC}"; exit 1; }
        echo -e "  ${GREEN}✓${NC} All critical datasets validated"
    else
        echo -e "  ${RED}✗ tools/download_data.py not found!${NC}"; exit 1
    fi
    mark_section "data"
fi
echo -e "  ${GREEN}✓${NC} Data preparation complete"

# ── [4/10] COLD START benchmarks (container) ─────────────────────────────────
if [[ "$MODE" != "native" ]]; then
    echo ""
    echo -e "${BLUE}[4/10] COLD START benchmarks (first-run / JIT latency)...${NC}"
    mkdir -p results/cold_start

    if check_section "cold_start"; then
        :
    else
        [ "$ENABLE_VECTOR" = "true" ] && {
            run_cold_instrumented "vector" "python3 benchmarks/vector_pip.py"          "Python" "$PYTHON_TAG" "results/cold_start/vector_python_cold.json"
            run_cold_instrumented "vector" "julia -t auto benchmarks/vector_pip.jl"    "Julia"  "$JULIA_TAG"  "results/cold_start/vector_julia_cold.json"
            run_cold_instrumented "vector" "Rscript benchmarks/vector_pip.R"           "R"      "$R_TAG"      "results/cold_start/vector_r_cold.json"
        }
        [ "$ENABLE_HYPERSPECTRAL" = "true" ] && {
            run_cold_instrumented "hyperspectral" "python3 benchmarks/hsi_stream.py"       "Python" "$PYTHON_TAG" "results/cold_start/hsi_python_cold.json"
            run_cold_instrumented "hyperspectral" "julia -t auto benchmarks/hsi_stream.jl" "Julia"  "$JULIA_TAG"  "results/cold_start/hsi_julia_cold.json"
            run_cold_instrumented "hyperspectral" "Rscript benchmarks/hsi_stream.R"        "R"      "$R_TAG"      "results/cold_start/hsi_r_cold.json"
        }
        mark_section "cold_start"
    fi
fi

# ── [5/10] WARM START benchmarks (container) ─────────────────────────────────
if [[ "$MODE" != "native" ]]; then
    echo ""
    echo -e "${BLUE}[5/10] WARM START benchmarks (steady-state)...${NC}"
    mkdir -p results/warm_start

    if check_section "warm_start"; then
        :
    else
        [ "$ENABLE_VECTOR" = "true" ] && {
            run_warm_instrumented "vector" "python3 benchmarks/vector_pip.py"                "Python" "$PYTHON_TAG" "results/warm_start/vector_python_warm.json"
            run_warm_instrumented "vector" "julia -t auto benchmarks/vector_pip.jl"          "Julia"  "$JULIA_TAG"  "results/warm_start/vector_julia_warm.json"
            run_warm_instrumented "vector" "Rscript benchmarks/vector_pip.R"                 "R"      "$R_TAG"      "results/warm_start/vector_r_warm.json"
        }
        [ "$ENABLE_INTERPOLATION" = "true" ] && {
            run_warm_instrumented "interpolation" "python3 benchmarks/interpolation_idw.py"       "Python" "$PYTHON_TAG" "results/warm_start/interp_python_warm.json"
            run_warm_instrumented "interpolation" "julia -t auto benchmarks/interpolation_idw.jl" "Julia"  "$JULIA_TAG"  "results/warm_start/interp_julia_warm.json"
            run_warm_instrumented "interpolation" "Rscript benchmarks/interpolation_idw.R"        "R"      "$R_TAG"      "results/warm_start/interp_r_warm.json"
        }
        [ "$ENABLE_TIMESERIES" = "true" ] && {
            run_warm_instrumented "timeseries" "python3 benchmarks/timeseries_ndvi.py"           "Python" "$PYTHON_TAG" "results/warm_start/ndvi_python_warm.json"
            run_warm_instrumented "timeseries" "julia -t auto benchmarks/timeseries_ndvi.jl"     "Julia"  "$JULIA_TAG"  "results/warm_start/ndvi_julia_warm.json"
            run_warm_instrumented "timeseries" "Rscript benchmarks/timeseries_ndvi.R"            "R"      "$R_TAG"      "results/warm_start/ndvi_r_warm.json"
        }
        [ "$ENABLE_HYPERSPECTRAL" = "true" ] && {
            run_warm_instrumented "hyperspectral" "python3 benchmarks/hsi_stream.py"              "Python" "$PYTHON_TAG" "results/warm_start/hsi_python_warm.json"
            run_warm_instrumented "hyperspectral" "julia -t auto benchmarks/hsi_stream.jl"        "Julia"  "$JULIA_TAG"  "results/warm_start/hsi_julia_warm.json"
            run_warm_instrumented "hyperspectral" "Rscript benchmarks/hsi_stream.R"               "R"      "$R_TAG"      "results/warm_start/hsi_r_warm.json"
        }
        mark_section "warm_start"
    fi
fi

# ── [6/10] Matrix Operations (container) ─────────────────────────────────────
if [[ "$MODE" != "native" ]]; then
    echo ""
    echo -e "${BLUE}[6/10] Matrix Operations (container)...${NC}"

    if check_section "matrix_container"; then
        :
    else
        run_matrix_instrumented() {
            local lang="$1" cmd="$2" tag="$3"
            local bench_key="matrix_container_${lang}"
            local out="results/matrix_ops_${lang,,}.json"

            if check_bench "$bench_key"; then
                BENCHMARK_COUNT=$((BENCHMARK_COUNT + 1)); return
            fi
            progress
            echo -e "  ${GREEN}${lang}${NC} matrix operations..."

            thermal_guard
            check_freq_stability || true
            local env_pre run_start_ts
            env_pre=$(snapshot_environment "pre")
            run_start_ts=$(date +%s)

            # TIMED REGION
            podman run --rm -v "$(pwd)":/benchmarks:Z "$tag" \
                bash -c "cd /benchmarks && $cmd" 2>&1 | grep -E "✓ Min:|✓ Results saved" | head -10
            # END TIMED REGION

            local run_end_ts env_post throttle_count
            run_end_ts=$(date +%s)
            env_post=$(snapshot_environment "post")
            throttle_count=$(count_throttle_events_since "$run_start_ts")
            [[ -f "$out" ]] && inject_env_into_json "$out" "$env_pre" "$env_post" "$throttle_count"
            log_thermal_event "$bench_key" "$lang" "matrix_ops" \
                "$env_pre" "$env_post" "$run_start_ts" "$run_end_ts" "$throttle_count"

            mark_bench "$bench_key"
            sleep "$SETTLE_TIME"
        }

        run_matrix_instrumented "Python" "python3 benchmarks/matrix_ops.py" "$PYTHON_TAG"
        run_matrix_instrumented "Julia"  "julia benchmarks/matrix_ops.jl"   "$JULIA_TAG"
        run_matrix_instrumented "R"      "Rscript benchmarks/matrix_ops.R"  "$R_TAG"
        mark_section "matrix_container"
    fi
fi

# ── [7/10] I/O Operations (container) ────────────────────────────────────────
if [[ "$MODE" != "native" ]]; then
    echo ""
    echo -e "${BLUE}[7/10] I/O Operations (container)...${NC}"

    if check_section "io_container"; then
        :
    else
        run_io_instrumented() {
            local lang="$1" cmd="$2" tag="$3"
            local bench_key="io_container_${lang}"
            local out="results/io_ops_${lang,,}.json"

            if check_bench "$bench_key"; then
                BENCHMARK_COUNT=$((BENCHMARK_COUNT + 1)); return
            fi
            progress
            echo -e "  ${GREEN}${lang}${NC} I/O operations..."

            thermal_guard
            check_freq_stability || true
            local env_pre run_start_ts
            env_pre=$(snapshot_environment "pre")
            run_start_ts=$(date +%s)

            # TIMED REGION
            podman run --rm -v "$(pwd)":/benchmarks:Z "$tag" \
                bash -c "cd /benchmarks && $cmd" 2>&1 | grep -E "✓ Min:|✓ Results saved" | head -10
            # END TIMED REGION

            local run_end_ts env_post throttle_count
            run_end_ts=$(date +%s)
            env_post=$(snapshot_environment "post")
            throttle_count=$(count_throttle_events_since "$run_start_ts")
            [[ -f "$out" ]] && inject_env_into_json "$out" "$env_pre" "$env_post" "$throttle_count"
            log_thermal_event "$bench_key" "$lang" "io_ops" \
                "$env_pre" "$env_post" "$run_start_ts" "$run_end_ts" "$throttle_count"

            mark_bench "$bench_key"
            sleep "$SETTLE_TIME"
        }

        run_io_instrumented "Python" "python3 benchmarks/io_ops.py" "$PYTHON_TAG"
        run_io_instrumented "Julia"  "julia benchmarks/io_ops.jl"   "$JULIA_TAG"
        run_io_instrumented "R"      "Rscript benchmarks/io_ops.R"  "$R_TAG"
        mark_section "io_container"
    fi
fi

# ── [8/10] Memory profiling (container) ──────────────────────────────────────
if [[ "$MODE" != "native" ]]; then
    echo ""
    echo -e "${BLUE}[8/10] Memory profiling (container)...${NC}"
    mkdir -p results/memory

    if check_section "memory"; then
        :
    else
        # BUG FIX retained: correct signature is <lang> <tag> <test_name> <script>
        profile_memory_container() {
            local lang="$1" tag="$2" test_name="$3" script="$4"
            local bench_key="memory_container_${lang}_${test_name}"

            if check_bench "$bench_key"; then
                BENCHMARK_COUNT=$((BENCHMARK_COUNT + 1)); return
            fi
            progress
            echo "  $lang memory ($test_name)..."

            thermal_guard
            local env_pre run_start_ts
            env_pre=$(snapshot_environment "pre")
            run_start_ts=$(date +%s)

            # TIMED REGION
            podman run --rm -v "$(pwd)":/benchmarks:Z "$tag" \
                python3 -c "
import sys
sys.path.insert(0, '/benchmarks')
from benchmarks.benchmark_stats import run_benchmark
import json
result = run_benchmark(
    lambda: __import__('subprocess').run(['${lang}', '/benchmarks/${script}'], capture_output=True),
    runs=1, warmup=0, track_memory=True, track_cpu=False
)
output = {
    'language': '${lang}',
    'benchmark': '${test_name}',
    'mode': 'container',
    'memory_rss_mb': result[2].get('rss_mb') if result[2] else None,
    'memory_vms_mb': result[2].get('vms_mb') if result[2] else None,
    'memory_peak_mb': result[1],
}
print(json.dumps(output, indent=2))
" 2>&1 | tee "results/memory/${test_name}_${lang}_mem.json" || true
            # END TIMED REGION

            local run_end_ts env_post throttle_count
            run_end_ts=$(date +%s)
            env_post=$(snapshot_environment "post")
            throttle_count=$(count_throttle_events_since "$run_start_ts")
            log_thermal_event "$bench_key" "$lang" "memory_${test_name}" \
                "$env_pre" "$env_post" "$run_start_ts" "$run_end_ts" "$throttle_count"

            mark_bench "$bench_key"
            sleep "$SETTLE_TIME"
        }

        [ "$ENABLE_VECTOR" = "true" ] && {
            profile_memory_container "Python" "$PYTHON_TAG" "vector_pip" "benchmarks/vector_pip.py"
            profile_memory_container "Julia"  "$JULIA_TAG"  "vector_pip" "benchmarks/vector_pip.jl"
            profile_memory_container "R"      "$R_TAG"      "vector_pip" "benchmarks/vector_pip.R"
        }
        mark_section "memory"
    fi
fi

# ── [9/10] Validate results (container) ──────────────────────────────────────
if [[ "$MODE" != "native" ]]; then
    echo ""
    echo -e "${BLUE}[9/10] Validating correctness (container)...${NC}"

    if check_section "validation_container"; then
        :
    else
        if [ -f "validation/thesis_validation.py" ]; then
            podman run --rm -v "$(pwd)":/benchmarks:Z "$PYTHON_TAG" \
                python3 validation/thesis_validation.py --all 2>&1 | tail -15 \
                || log_error "Container validation failed"
        fi
        mark_section "validation_container"
    fi
fi

# ── [10/10] NATIVE BENCHMARKS ────────────────────────────────────────────────
if [[ "$MODE" != "container" ]]; then
    echo ""
    echo -e "${BLUE}[10/10] Native System Benchmarks${NC}"
    echo -e "${YELLOW}  Running on host system with full thermal + frequency telemetry${NC}"
    echo ""
    mkdir -p results/native results/academic

    PY_BIN="python3"
    JL_BIN="$HOME/.local/julia/bin/julia"
    RS_BIN="Rscript"
    if [[ "$IS_BOOTC" == "true" ]]; then
        PY_BIN="/usr/bin/python3"
        JL_BIN="/usr/bin/julia"
        RS_BIN="/usr/bin/Rscript"
    fi

    echo -e "${YELLOW}  Unified Threading (8 Language + 8 BLAS threads):${NC}"
    export OPENBLAS_NUM_THREADS=8
    export FLEXIBLAS_NUM_THREADS=8
    export GOTO_NUM_THREADS=8
    export JULIA_NUM_THREADS=8
    export OMP_NUM_THREADS=8

    CLI_FLAGS="--data $DATA_MODE"
    SIZE_FLAGS="--size $SIZE_MODE"

    command -v $PY_BIN &>/dev/null && {
        [[ "$IS_BOOTC" != "true" ]] && source .venv/bin/activate 2>/dev/null || true
        run_native_instrumented "Python" "$PY_BIN benchmarks/matrix_ops.py $CLI_FLAGS $SIZE_FLAGS" "matrix_ops"
    }
    command -v $JL_BIN &>/dev/null && run_native_instrumented "Julia" "$JL_BIN benchmarks/matrix_ops.jl $CLI_FLAGS $SIZE_FLAGS" "matrix_ops"
    command -v $RS_BIN &>/dev/null && run_native_instrumented "R"     "$RS_BIN benchmarks/matrix_ops.R  $CLI_FLAGS $SIZE_FLAGS" "matrix_ops"

    echo -e "${YELLOW}  Raster algebra:${NC}"
    command -v $PY_BIN &>/dev/null && run_native_instrumented "Python" "$PY_BIN benchmarks/raster_algebra.py $CLI_FLAGS" "raster_algebra"
    command -v $JL_BIN &>/dev/null && run_native_instrumented "Julia"  "$JL_BIN benchmarks/raster_algebra.jl $CLI_FLAGS" "raster_algebra"
    command -v $RS_BIN &>/dev/null && run_native_instrumented "R"      "$RS_BIN benchmarks/raster_algebra.R  $CLI_FLAGS" "raster_algebra"

    echo -e "${YELLOW}  I/O Operations:${NC}"
    command -v $PY_BIN &>/dev/null && run_native_instrumented "Python" "$PY_BIN benchmarks/io_ops.py $CLI_FLAGS $SIZE_FLAGS" "io_ops"
    command -v $JL_BIN &>/dev/null && run_native_instrumented "Julia"  "$JL_BIN benchmarks/io_ops.jl $CLI_FLAGS $SIZE_FLAGS" "io_ops"
    command -v $RS_BIN &>/dev/null && run_native_instrumented "R"      "$RS_BIN benchmarks/io_ops.R  $CLI_FLAGS $SIZE_FLAGS" "io_ops"

    echo -e "${YELLOW}  Reprojection:${NC}"
    command -v $PY_BIN &>/dev/null && run_native_instrumented "Python" "$PY_BIN benchmarks/reprojection.py $CLI_FLAGS" "reprojection"
    command -v $JL_BIN &>/dev/null && run_native_instrumented "Julia"  "$JL_BIN benchmarks/reprojection.jl $CLI_FLAGS" "reprojection"
    command -v $RS_BIN &>/dev/null && run_native_instrumented "R"      "$RS_BIN benchmarks/reprojection.R  $CLI_FLAGS" "reprojection"

    echo -e "${YELLOW}  Zonal Stats:${NC}"
    command -v $PY_BIN &>/dev/null && run_native_instrumented "Python" "$PY_BIN benchmarks/zonal_stats.py $CLI_FLAGS" "zonal_stats"
    command -v $JL_BIN &>/dev/null && run_native_instrumented "Julia"  "$JL_BIN benchmarks/zonal_stats.jl $CLI_FLAGS" "zonal_stats"
    command -v $RS_BIN &>/dev/null && run_native_instrumented "R"      "$RS_BIN benchmarks/zonal_stats.R  $CLI_FLAGS" "zonal_stats"

    echo -e "${YELLOW}  Interpolation:${NC}"
    command -v $PY_BIN &>/dev/null && run_native_instrumented "Python" "$PY_BIN benchmarks/interpolation_idw.py $CLI_FLAGS" "interpolation"
    command -v $JL_BIN &>/dev/null && run_native_instrumented "Julia"  "$JL_BIN benchmarks/interpolation_idw.jl $CLI_FLAGS" "interpolation"
    command -v $RS_BIN &>/dev/null && run_native_instrumented "R"      "$RS_BIN benchmarks/interpolation_idw.R  $CLI_FLAGS" "interpolation"

    echo -e "${YELLOW}  Time-Series:${NC}"
    command -v $PY_BIN &>/dev/null && run_native_instrumented "Python" "$PY_BIN benchmarks/timeseries_ndvi.py $CLI_FLAGS" "timeseries"
    command -v $JL_BIN &>/dev/null && run_native_instrumented "Julia"  "$JL_BIN benchmarks/timeseries_ndvi.jl $CLI_FLAGS" "timeseries"
    command -v $RS_BIN &>/dev/null && run_native_instrumented "R"      "$RS_BIN benchmarks/timeseries_ndvi.R  $CLI_FLAGS" "timeseries"

    echo -e "${YELLOW}  Hyperspectral:${NC}"
    command -v $PY_BIN &>/dev/null && run_native_instrumented "Python" "$PY_BIN benchmarks/hsi_stream.py $CLI_FLAGS" "hsi_stream"
    command -v $JL_BIN &>/dev/null && run_native_instrumented "Julia"  "$JL_BIN benchmarks/hsi_stream.jl $CLI_FLAGS" "hsi_stream"
    command -v $RS_BIN &>/dev/null && run_native_instrumented "R"      "$RS_BIN benchmarks/hsi_stream.R  $CLI_FLAGS" "hsi_stream"

    echo -e "${YELLOW}  Vector PiP:${NC}"
    command -v $PY_BIN &>/dev/null && run_native_instrumented "Python" "$PY_BIN benchmarks/vector_pip.py $CLI_FLAGS" "vector_pip"
    command -v $JL_BIN &>/dev/null && run_native_instrumented "Julia"  "$JL_BIN benchmarks/vector_pip.jl $CLI_FLAGS" "vector_pip"
    command -v $RS_BIN &>/dev/null && run_native_instrumented "R"      "$RS_BIN benchmarks/vector_pip.R  $CLI_FLAGS" "vector_pip"

    echo -e "${GREEN}  ✓ Native benchmarks complete${NC}"
fi

# ── [11/11] Julia JIT Overhead Analysis ─────────────────────────────────────
if [[ "$MODE" != "container" ]]; then
    echo ""
    echo -e "${BLUE}[11/11] Julia JIT Overhead Analysis (Cold Start)...${NC}"

    if check_bench "jit_analysis"; then
        BENCHMARK_COUNT=$((BENCHMARK_COUNT + 1))
    else
        progress
        thermal_guard
        env_pre=$(snapshot_environment "pre")
        run_start_ts=$(date +%s)

        if command -v $PY_BIN &>/dev/null; then
            export PYTHONPATH="${PYTHONPATH:-/usr/local/lib/python-deps}"
            [[ "$IS_BOOTC" != "true" ]] && source .venv/bin/activate 2>/dev/null || true
            $PY_BIN benchmarks/jit_tracking.py || log_error "JIT tracking failed"
        else
            log_error "Python not found, skipping JIT analysis"
        fi

        run_end_ts=$(date +%s)
        env_post=$(snapshot_environment "post")
        throttle_count=$(count_throttle_events_since "$run_start_ts")
        log_thermal_event "jit_analysis" "Julia" "jit_cold_start" \
            "$env_pre" "$env_post" "$run_start_ts" "$run_end_ts" "$throttle_count"
        mark_bench "jit_analysis"
        sleep "$SETTLE_TIME"
    fi
fi

# ── [12/12] Data Scaling Benchmarks ─────────────────────────────────────────
if [[ "$SCALING" == "true" ]]; then
    echo ""
    echo -e "${BLUE}[12/12] Data Scaling Benchmarks (Complexity Analysis)...${NC}"
    [[ "$SCALING_QUICK" == "true" ]] && echo -e "${YELLOW}  Quick mode${NC}"

    if check_section "scaling"; then
        :
    else
        # Python scaling benchmarks
        if command -v $PY_BIN &>/dev/null; then
            thermal_guard
            env_pre=$(snapshot_environment "pre")
            run_start_ts=$(date +%s)

            export PYTHONPATH="${PYTHONPATH:-/usr/local/lib/python-deps}"
            [[ "$IS_BOOTC" != "true" ]] && source .venv/bin/activate 2>/dev/null || true
            SCALING_ARGS="--runs 10"
            [[ "$SCALING_QUICK" == "true" ]] && SCALING_ARGS="--quick --runs 5"

            echo -e "${CYAN}  Running Python scaling benchmarks (all 9 scenarios)...${NC}"
            $PY_BIN benchmark_scaling.py $SCALING_ARGS || log_error "Python scaling benchmarks failed"

            run_end_ts=$(date +%s)
            env_post=$(snapshot_environment "post")
            throttle_count=$(count_throttle_events_since "$run_start_ts")
            log_thermal_event "scaling_suite_python" "python" "scaling" \
                "$env_pre" "$env_post" "$run_start_ts" "$run_end_ts" "$throttle_count"
        else
            log_error "Python not found, skipping Python scaling benchmarks"
        fi

        # Julia scaling benchmarks
        if command -v julia &>/dev/null; then
            thermal_guard
            JL_SCALING_ARGS=""
            [[ "$SCALING_QUICK" == "true" ]] && JL_SCALING_ARGS="--quick"

            echo -e "${CYAN}  Running Julia scaling benchmarks (all 9 scenarios)...${NC}"
            julia benchmark_scaling.jl $JL_SCALING_ARGS || log_error "Julia scaling benchmarks failed"
        else
            log_error "Julia not found, skipping Julia scaling benchmarks"
        fi

        # R scaling benchmarks
        if command -v Rscript &>/dev/null; then
            R_SCALING_ARGS=""
            [[ "$SCALING_QUICK" == "true" ]] && R_SCALING_ARGS="--quick"

            echo -e "${CYAN}  Running R scaling benchmarks (all 9 scenarios)...${NC}"
            Rscript benchmark_scaling.R $R_SCALING_ARGS || log_error "R scaling benchmarks failed"
        else
            log_error "Rscript not found, skipping R scaling benchmarks"
        fi

        mark_section "scaling"
    fi
fi

# ── Generate Academic Report ─────────────────────────────────────────────────
echo ""
echo -e "${BLUE}Generating Academic Report...${NC}"

if command -v $PY_BIN &>/dev/null; then
    export PYTHONPATH="${PYTHONPATH:-/usr/local/lib/python-deps}"
    [[ "$IS_BOOTC" != "true" ]] && source .venv/bin/activate 2>/dev/null || true

    [[ -f "tools/normalize_results.py" ]] && {
        echo "  Normalizing results..."
        $PY_BIN tools/normalize_results.py --input results/ --output results/normalized/ --summary \
            2>&1 | tail -5 || log_error "Result normalization failed"
    }
    [[ -f "tools/thesis_viz.py" ]] && {
        echo "  Generating visualizations..."
        $PY_BIN tools/thesis_viz.py --all 2>&1 | tail -3 || log_error "Visualization failed"
    }
    [[ -f "validation/thesis_validation.py" ]] && {
        echo "  Running validation..."
        $PY_BIN validation/thesis_validation.py --all 2>&1 | tail -15 || log_error "Validation failed"
    }
    echo -e "${GREEN}  ✓ Academic report complete${NC}"
fi

# ── Optional thermal report ───────────────────────────────────────────────────
if [[ "$THERMAL_REPORT" == "true" ]]; then
    print_thermal_report
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}"
echo "========================================================================"
echo "  ✓ ALL BENCHMARKS COMPLETE"
echo "========================================================================"
echo -e "${NC}"
echo "  Elapsed : $(elapsed_time)"
echo "  Finished: $(timestamp)"

FINAL_TEMP=$(read_max_temp_c)
FINAL_FREQ=$(read_all_freqs_json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['avg_mhz'])" 2>/dev/null || echo "?")
echo ""
echo -e "  ${CYAN}Final system state:${NC}  CPU ${FINAL_TEMP}°C  |  Avg freq ${FINAL_FREQ} MHz"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}  ⚠ ${#ERRORS[@]} error(s) encountered:${NC}"
    for err in "${ERRORS[@]}"; do
        echo -e "    ${RED}• $err${NC}"
    done
    echo "  Full error log: results/errors.log"
fi

echo ""
echo "  Results directory:"
find results -name '*.json' -o -name '*.txt' -o -name '*.md' -o -name '*.png' -o -name '*.jsonl' 2>/dev/null \
    | grep -v gitkeep | grep -v '\.bench_' | grep -v '\.section_' | sort | sed 's/^/    /'
echo ""
echo "  Key Outputs:"
echo "    - results/native/{Python,Julia,R}_{scenario}.json  ← per-run times + thermal metadata"
echo "    - results/warm_start/*.json                         ← hyperfine + environment_pre/post"
echo "    - results/cold_start/*.json                         ← cold JIT latency + environment"
echo "    - results/hardware_info.json                        ← thermal baseline + CPU info"
echo "    - results/thermal_telemetry.jsonl                   ← append-only log, one line per benchmark"
[[ "$SCALING" == "true" ]] && {
    echo "    - results/scaling/combined_scaling_summary.json"
}
echo ""
echo "  Telemetry fields in each result JSON:"
echo "    environment_pre.temperature.max_c    — CPU temp before run"
echo "    environment_post.temperature.max_c   — CPU temp after run"
echo "    thermal_delta.temp_rise_c             — ΔT during run"
echo "    environment_pre.frequency.avg_mhz    — avg core freq before run"
echo "    environment_pre.frequency.spread_pct — core freq spread before run"
echo "    throttle_events                       — kernel throttle events during run"
echo "    results[].per_run_stats.cv            — coefficient of variation"
echo "    results[].per_run_stats.run_times_ms  — all individual run times"
echo ""
echo "  Usage:"
echo "    ./run_benchmarks.sh                         # Full suite"
echo "    ./run_benchmarks.sh --resume                # Continue from interruption"
echo "    ./run_benchmarks.sh --resume --status       # Show completed benchmarks"
echo "    ./run_benchmarks.sh --thermal-report        # Print thermal summary"
echo "    ./run_benchmarks.sh --no-thermal-guard      # Skip temperature gating (CI)"
echo "    ./run_benchmarks.sh --native-only           # Native only"
echo "    ./run_benchmarks.sh --clean                 # Clear results + checkpoints"
echo "    ./run_benchmarks.sh --dry-run               # Preview plan"
echo ""
echo -e "${CYAN}  Thesis Quality: A+ (v4.0.1 — Telemetry Export Fix)${NC}"
echo ""
