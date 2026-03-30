#!/bin/bash

source loadtest/endpoints.sh

echo -e "\n=== 1. MIERZYMY CZYSTE OPÓŹNIENIE SIECIOWE (NETWORK RTT) ==="
RTT=$(curl -s -w '%{time_connect}\n' -o /dev/null "${LAMBDA_ZIP_URL}")
echo "Szacowany czas sieciowy (Network RTT): $RTT sek" | tee results/assignment-2-rtt.txt

echo -e "\n=== 2. BUDZIMY LAMBDĘ ZIP (AWS LAMBDA INVOKE) ==="
echo "Wysyłam 30 zapytań..."
echo "--- LAMBDA ZIP ---" > results/assignment-2-client-times.txt

for i in {1..30}; do
  start=$(date +%s%3N)
  # Zapisujemy odpowiedź do pliku tymczasowego, żeby wyświetlić status
  STATUS=$(aws lambda invoke --function-name lsc-knn-zip --cli-binary-format raw-in-base64-out --payload "$(python3 -c 'import json; q=json.load(open("loadtest/query.json")); print(json.dumps({"body": json.dumps(q)}))')" /tmp/out.json --query 'StatusCode' --output text 2>/dev/null)
  end=$(date +%s%3N)
  
  echo "Zapytanie $i: czas = $((end-start)) ms | Status: $STATUS" | tee -a results/assignment-2-client-times.txt
  sleep 1
done

echo -e "\n=== GOTOWE DLA ZIP. POBIERAM LOGI ==="
aws logs filter-log-events --log-group-name "/aws/lambda/lsc-knn-zip" --filter-pattern "Init Duration" --start-time $(date -d '30 minutes ago' +%s000) --query 'events[*].message' --output text > results/assignment-2-server-logs-zip.txt

echo -e "\n=== ZAMRAŻANIE ŚRODOWISKA: ODLICZANIE 20 MINUT ==="
echo "Aby przetestować środowisko Container sprawiedliwie, musimy poczekać aż wystygnie."
sleep 1200

echo -e "\n=== BUDZIMY LAMBDĘ CONTAINER (AWS LAMBDA INVOKE) ==="
echo "Wysyłam 30 zapytań..."
echo "--- LAMBDA CONTAINER ---" >> results/assignment-2-client-times.txt

for i in {1..30}; do
  start=$(date +%s%3N)
  # Zapisujemy odpowiedź, uderzając w lsc-knn-container
  STATUS=$(aws lambda invoke --function-name lsc-knn-container --cli-binary-format raw-in-base64-out --payload "$(python3 -c 'import json; q=json.load(open("loadtest/query.json")); print(json.dumps({"body": json.dumps(q)}))')" /tmp/out.json --query 'StatusCode' --output text 2>/dev/null)
  end=$(date +%s%3N)
  
  echo "Zapytanie $i: czas = $((end-start)) ms | Status: $STATUS" | tee -a results/assignment-2-client-times.txt
  sleep 1
done

echo -e "\n=== GOTOWE DLA CONTAINER. POBIERAM LOGI ==="
aws logs filter-log-events --log-group-name "/aws/lambda/lsc-knn-container" --filter-pattern "Init Duration" --start-time $(date -d '30 minutes ago' +%s000) --query 'events[*].message' --output text > results/assignment-2-server-logs-container.txt

echo -e "\nMamy to! Komplet danych do Zadania 2 czeka w folderze results/."
