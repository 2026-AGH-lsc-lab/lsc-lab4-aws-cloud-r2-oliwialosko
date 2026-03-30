#!/bin/bash

# Wczytujemy adresy
source loadtest/endpoints.sh

echo "=== ODLICZANIE 20 MINUT (ZAMRAŻANIE ŚRODOWISKA) ==="
echo "Zostaw terminal w spokoju. Skrypt sam ruszy po 20 minutach..."
sleep 1200

echo -e "\n=== 1. FARGATE I EC2 (200 zapytań, współbieżność 50) ==="
# Używamy oha, bo dla tych adresów działa idealnie i nie wymaga SigV4
oha -n 200 -c 50 -m POST -T application/json -d @loadtest/query.json "$FARGATE_URL/search" > results/scenario-c-fargate.txt
oha -n 200 -c 50 -m POST -T application/json -d @loadtest/query.json "$EC2_URL/search" > results/scenario-c-ec2.txt
echo "Gotowe! Wyniki dla EC2 i Fargate zapisano do plików."

echo -e "\n=== 2. LAMBDA ZIP (200 zapytań, współbieżność 10) ==="
> results/scenario-c-zip-times.txt
# Wysyłamy 20 paczek po 10 zapytań naraz (w tle)
for b in {1..20}; do
  for i in {1..10}; do
    (
      start=$(date +%s%3N)
      aws lambda invoke --function-name lsc-knn-zip --cli-binary-format raw-in-base64-out --payload "$(python3 -c 'import json; q=json.load(open("loadtest/query.json")); print(json.dumps({"body": json.dumps(q)}))')" /tmp/out.json > /dev/null 2>&1
      end=$(date +%s%3N)
      echo "$((end-start))" >> results/scenario-c-zip-times.txt
    ) &
  done
  wait # Czekamy, aż paczka 10 zapytań się skończy
  echo "Paczka ZIP $b/20 ukończona..."
done

echo -e "\nStatystyki LAMBDA ZIP:" > results/scenario-c-lambda-stats.txt
python3 -c 'import sys; times=sorted([int(x) for x in sys.stdin if x.strip()]); print(f"p50: {times[int(len(times)*0.5)]} ms | p95: {times[int(len(times)*0.95)]} ms | p99: {times[int(len(times)*0.99)]} ms | Max: {times[-1]} ms")' < results/scenario-c-zip-times.txt | tee -a results/scenario-c-lambda-stats.txt

echo -e "\n=== 3. LAMBDA CONTAINER (200 zapytań, współbieżność 10) ==="
> results/scenario-c-container-times.txt
for b in {1..20}; do
  for i in {1..10}; do
    (
      start=$(date +%s%3N)
      aws lambda invoke --function-name lsc-knn-container --cli-binary-format raw-in-base64-out --payload "$(python3 -c 'import json; q=json.load(open("loadtest/query.json")); print(json.dumps({"body": json.dumps(q)}))')" /tmp/out.json > /dev/null 2>&1
      end=$(date +%s%3N)
      echo "$((end-start))" >> results/scenario-c-container-times.txt
    ) &
  done
  wait
  echo "Paczka Container $b/20 ukończona..."
done

echo -e "\nStatystyki LAMBDA CONTAINER:" >> results/scenario-c-lambda-stats.txt
python3 -c 'import sys; times=sorted([int(x) for x in sys.stdin if x.strip()]); print(f"p50: {times[int(len(times)*0.5)]} ms | p95: {times[int(len(times)*0.95)]} ms | p99: {times[int(len(times)*0.99)]} ms | Max: {times[-1]} ms")' < results/scenario-c-container-times.txt | tee -a results/scenario-c-lambda-stats.txt

echo -e "\n=== 4. POBIERANIE LOGÓW O ZIMNYCH STARTACH ==="
aws logs filter-log-events --log-group-name "/aws/lambda/lsc-knn-zip" --filter-pattern "Init Duration" --start-time $(date -d '10 minutes ago' +%s000) --query 'events[*].message' --output text > results/scenario-c-server-logs-zip.txt
aws logs filter-log-events --log-group-name "/aws/lambda/lsc-knn-container" --filter-pattern "Init Duration" --start-time $(date -d '10 minutes ago' +%s000) --query 'events[*].message' --output text > results/scenario-c-server-logs-container.txt

echo -e "\nWSZYSTKO GOTOWE! Komplet wyników znajdziesz w folderze results/."
