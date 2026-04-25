#!/bin/bash
# ============================================================
# Author: Naif (Naifa) - NAIFA-PC
# Cold-start measurement script for P1 (VM) and P2 (Docker)
# ============================================================

OUTPUT="results/coldstart.csv"
echo "platform,run,latency_ms" > $OUTPUT

# ----- P1 (VM) cold-start -----
echo "Measuring P1 (VM) cold starts..."
for i in 1 2 3 4 5; do
    # Kill any running uvicorn on port 9000
    pkill -9 -f "uvicorn.*9000" 2>/dev/null
    sleep 3
    
    # Start uvicorn in background and capture start time
    START=$(date +%s%N)
    nohup python -m uvicorn app:app --host 0.0.0.0 --port 9000 > /tmp/p1_$i.log 2>&1 &
    
    # Poll /health until it returns 200
    while true; do
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:9000/health 2>/dev/null | grep -q "200"; then
            END=$(date +%s%N)
            LATENCY=$(( (END - START) / 1000000 ))
            echo "P1 run $i: ${LATENCY} ms"
            echo "P1_VM,$i,$LATENCY" >> $OUTPUT
            break
        fi
        sleep 0.1
    done
done

# Kill P1 after measurements
pkill -9 -f "uvicorn.*9000" 2>/dev/null
sleep 2

# ----- P2 (Docker) cold-start -----
echo "Measuring P2 (Docker) cold starts..."
for i in 1 2 3 4 5; do
    # Stop and remove existing container
    docker stop sentiment-service 2>/dev/null
    docker rm sentiment-service 2>/dev/null
    sleep 2
    
    # Start container and capture start time
    START=$(date +%s%N)
    docker run -d -p 8000:8000 --name sentiment-service sentiment-api:latest > /dev/null
    
    # Poll /health until it returns 200
    while true; do
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health 2>/dev/null | grep -q "200"; then
            END=$(date +%s%N)
            LATENCY=$(( (END - START) / 1000000 ))
            echo "P2 run $i: ${LATENCY} ms"
            echo "P2_Docker,$i,$LATENCY" >> $OUTPUT
            break
        fi
        sleep 0.1
    done
done

echo ""
echo "=== Cold-start results ==="
cat $OUTPUT
