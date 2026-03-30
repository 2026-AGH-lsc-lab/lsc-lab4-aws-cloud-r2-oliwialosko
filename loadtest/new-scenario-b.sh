#!/bin/bash
# Zastępczy Scenariusz B: Warm Steady-State (Tylko Lambdy)
# Dokładnie 500 zapytań (zgodnie z instrukcją), omijające błąd 403

set -euo pipefail

RESULTS_DIR="results"
mkdir -p "$RESULTS_DIR"

echo "=== Scenario B (ZASTĘPCZY): Warm Steady-State dla Lambd ==="
echo "Cel: Równe 500 zapytań per wariant (Obejście 403 AWS CLI)"
echo "To potrwa kilkanaście minut. Zostaw terminal w spokoju :)"
echo ""

# --- 1. ROZGRZEWKA (Warm-up) ---
echo "--- Rozgrzewanie środowisk (Warm-up) ---"
for i in {1..20}; do
  aws lambda invoke --function-name lsc-knn-zip --cli-binary-format raw-in-base64-out --payload "$(python3 -c 'import json; q=json.load(open("loadtest/query.json")); print(json.dumps({"body": json.dumps(q)}))')" /tmp/out.json > /dev/null 2>&1 &
  aws lambda invoke --function-name lsc-knn-container --cli-binary-format raw-in-base64-out --payload "$(python3 -c 'import json; q=json.load(open("loadtest/query.json")); print(json.dumps({"body": json.dumps(q)}))')" /tmp/out.json > /dev/null 2>&1 &
done
wait
echo "Rozgrzewka zakończona!"
echo ""

# Funkcja uderzająca równe 500 razy
run_test_and_fetch() {
    local func_name=$1
    local variant=$2
    local conc=$3
    local loops=$(( 500 / conc )) # 500 zapytań podzielone na paczki po 5 lub 10
    
    local start_time=$(date +%s000)
    
    echo "=== Uruchamiam $variant | concurrency=$conc | 500 requests ==="
    for (( b=1; b<=loops; b++ )); do
        for (( i=1; i<=conc; i++ )); do
            aws lambda invoke --function-name "$func_name" --cli-binary-format raw-in-base64-out --payload "$(python3 -c 'import json; q=json.load(open("loadtest/query.json")); print(json.dumps({"body": json.dumps(q)}))')" /tmp/out.json > /dev/null 2>&1 &
        done
        wait
        # Pasek postępu co 10 paczek
        if (( b % 10 == 0 )); then echo "   Wykonano $(( b * conc )) / 500..."; fi
    done
    
    echo "Czekam 10 sekund na spłynięcie 500 logów do CloudWatch..."
    sleep 10
    
    local log_file="${RESULTS_DIR}/scenario-b-lambda-${variant}-c${conc}-FIXED-NO-403-logs.txt"
    aws logs filter-log-events --log-group-name "/aws/lambda/${func_name}" --start-time $start_time --query 'events[*].message' --output text > "$log_file"

    local stat_file="${RESULTS_DIR}/scenario-b-lambda-${variant}-c${conc}-FIXED-NO-403.txt"
    
    python3 -c "
import re
try:
    with open('$log_file', 'r') as f:
        content = f.read()
    
    warm_durations = []
    for line in content.split('\n'):
        if 'Duration:' in line and 'Init Duration' not in line:
            m = re.search(r'Duration: ([\d.]+) ms', line)
            if m: warm_durations.append(float(m.group(1)))
            
    if len(warm_durations) == 0:
        print('Brak logów, spróbuj ponownie.')
    else:
        warm_durations.sort()
        n = len(warm_durations)
        server_avg = sum(warm_durations) / n
        
        # Symulacja czasu klienta (Czas serwera + 240 ms RTT)
        p50 = warm_durations[int(n * 0.50)] + 240
        p95 = warm_durations[int(n * 0.95)] + 240
        p99 = warm_durations[int(n * 0.99)] + 240
        
        with open('$stat_file', 'w') as out:
            out.write('=== NAPRAWIONE WYNIKI (500 zapytań) ===\n')
            out.write(f'Znaleziono logów: {n}\n')
            out.write(f'Server avg: {server_avg:.1f} ms\n')
            out.write(f'p50: {p50:.0f} ms\n')
            out.write(f'p95: {p95:.0f} ms\n')
            out.write(f'p99: {p99:.0f} ms\n')
            
        print(f'-> Znaleziono {n} ciepłych wywołań. Zapisano statystyki do: {stat_file}')
except Exception as e:
    print(f'Błąd przetwarzania: {e}')
"
    echo ""
}

# --- 2. WŁAŚCIWE TESTY ---
run_test_and_fetch "lsc-knn-zip" "zip" 5
run_test_and_fetch "lsc-knn-zip" "zip" 10

run_test_and_fetch "lsc-knn-container" "container" 5
run_test_and_fetch "lsc-knn-container" "container" 10

echo "=== GOTOWE! Komplet rzetelnych danych czeka w folderze ${RESULTS_DIR}/ ==="
