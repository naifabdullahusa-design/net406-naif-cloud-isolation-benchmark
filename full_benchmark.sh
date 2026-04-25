#!/bin/bash

echo "=== FULL BENCHMARK SUITE ===" 
mkdir -p results

# ---- COLD START: P1 (VM) - 5 runs ----
echo "--- Cold Start P1 (VM) ---"
for i in 1 2 3 4 5; do
    pkill -f "port 9000" 2>/dev/null
    sleep 2
    START=$(date +%s%3N)
    python -m uvicorn app:app --host 0.0.0.0 --port 9000 &
    until curl -s http://localhost:9000/health > /dev/null; do sleep 0.1; done
    END=$(date +%s%3N)
    echo "P1_coldstart_run${i},$((END-START))" >> results/coldstart.csv
    echo "P1 Run $i: $((END-START)) ms"
    pkill -f "port 9000" 2>/dev/null
    sleep 2
done

# ---- COLD START: P2 (Docker) - 5 runs ----
echo "--- Cold Start P2 (Docker) ---"
for i in 1 2 3 4 5; do
    docker stop sentiment-service 2>/dev/null
    sleep 2
    START=$(date +%s%3N)
    docker start sentiment-service
    until curl -s http://localhost:8000/health > /dev/null; do sleep 0.1; done
    END=$(date +%s%3N)
    echo "P2_coldstart_run${i},$((END-START))" >> results/coldstart.csv
    echo "P2 Run $i: $((END-START)) ms"
    docker stop sentiment-service 2>/dev/null
    sleep 2
done

# ---- Restart both services ----
echo "--- Restarting both services ---"
python -m uvicorn app:app --host 0.0.0.0 --port 9000 &
sleep 3
docker start sentiment-service
sleep 3

# ---- CONCURRENCY SWEEP + S1 for P1 ----
echo "--- Concurrency Sweep P1 (VM) ---"
for c in 1 5 10 25 50; do
    echo "P1 concurrency=$c"
    locust -f locustfile.py -u $c -r $c -t 60s --headless \
        -H http://localhost:9000 \
        --csv=results/p1_c${c} 2>/dev/null
    sleep 3
done

# S1 full for P1
echo "--- S1 Steady Load P1 ---"
locust -f locustfile.py -u 10 -r 2 -t 180s --headless \
    -H http://localhost:9000 \
    --csv=results/p1_s1 2>/dev/null

# S2 burst for P1
echo "--- S2 Burst P1 ---"
pkill -f "port 9000" 2>/dev/null
sleep 2
python -m uvicorn app:app --host 0.0.0.0 --port 9000 &
sleep 3
locust -f locustfile.py -u 50 -r 50 -t 30s --headless \
    -H http://localhost:9000 \
    --csv=results/p1_s2 2>/dev/null

# ---- CONCURRENCY SWEEP + S1 for P2 ----
echo "--- Concurrency Sweep P2 (Docker) ---"
docker start sentiment-service 2>/dev/null
sleep 3
for c in 1 5 10 25 50; do
    echo "P2 concurrency=$c"
    locust -f locustfile.py -u $c -r $c -t 60s --headless \
        -H http://localhost:8000 \
        --csv=results/p2_c${c} 2>/dev/null
    sleep 3
done

# S1 full for P2
echo "--- S1 Steady Load P2 ---"
locust -f locustfile.py -u 10 -r 2 -t 180s --headless \
    -H http://localhost:8000 \
    --csv=results/p2_s1 2>/dev/null

# S2 burst for P2
echo "--- S2 Burst P2 ---"
docker stop sentiment-service
sleep 2
docker start sentiment-service
sleep 3
locust -f locustfile.py -u 50 -r 50 -t 30s --headless \
    -H http://localhost:8000 \
    --csv=results/p2_s2 2>/dev/null

echo "=== ALL DONE === Results saved in results/ folder"
