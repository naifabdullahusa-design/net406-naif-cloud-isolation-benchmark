# NET406 — Cloud Compute Isolation Benchmarking

**Author:** Naif Abdullah  - faisal abdo

**Workstation:** NAIFA-PC  
**Course:** NET406 Cloud Architecture, Spring 2025-26  
**Institution:** Canadian University Dubai

This repository contains the implementation, benchmark scripts, and results for the NET406 research assignment on benchmarking cloud compute isolation technologies for AI inference workloads.

## Research Question

Which compute isolation technology — VM, Container, or AWS Lambda — best balances cold-start latency, throughput, resource overhead, and cost for a cloud-native AI inference service under variable load?

## Microservice

A FastAPI sentiment analysis service running **DistilBERT** (`distilbert-base-uncased-finetuned-sst-2-english`) with 8-bit dynamic quantization for CPU deployment, as specified in the assignment brief.

Endpoints:
- `GET /health` — Readiness check used for cold-start measurement
- `POST /predict?text=...` — Sentiment classification (POSITIVE / NEGATIVE)

## Platforms Benchmarked

| Platform | Description | Done by |
|---|---|---|
| **P1 — VM** | Direct Python/Uvicorn process on Ubuntu 24.04 EC2 t2.small | Naif Abdullah |
| **P2 — Docker** | Same service in a `python:3.11-slim` container, model pre-baked | Naif Abdullah |
| **P3 — AWS Lambda** | Container image deployed via Lambda Function URL | Faisal |

## Task Distribution

- **Naif Abdullah** — P1 (VM) and P2 (Docker): EC2 setup, FastAPI service with quantized DistilBERT, Dockerfile, Locust load tests, and M1–M5 metric collection for S1 and S2.
- **Faisal** — P3 (AWS Lambda) implementation and benchmarking.

## Repository Layout

.
├── app.py                       # FastAPI service with quantized DistilBERT
├── Dockerfile                   # Container build (model pre-baked into image)
├── requirements.txt             # Python dependencies (CPU torch + transformers)
├── locustfile.py                # Locust load test against POST /predict
├── measure_coldstart.sh         # Cold-start measurement helper
├── results/                     # Raw benchmark outputs (CSVs)
│   ├── coldstart.csv            # M1: 5 cold-start runs per platform
│   ├── p1_c{1,5,10,25,50}*.csv # P1 throughput sweep (M2/M3)
│   ├── p2_c{1,5,10,25,50}.csv # P2 throughput sweep (M2/M3)
│   ├── p1_s1_.csv, p2_s1_.csv # Scenario S1 (steady load 180s @ c=10)
│   ├── p1_s2_.csv, p2_s2_*.csv # Scenario S2 (burst 50 @ 30s)
│   ├── m4_resource_overhead.csv # M4: idle and peak CPU/memory
│   └── m5_cost_proxy.csv        # M5: cost per 1000 inferences (USD)
└── README.md

## How to Reproduce

### Prerequisites
- AWS EC2 instance: Ubuntu 24.04 LTS, t2.small (2 vCPU, 2 GiB RAM), us-east-1
- Disk: 30 GiB EBS volume (PyTorch + DistilBERT image needs the headroom)
- Inbound security group rules: TCP 22 (your IP), TCP 8000, TCP 9000 (anywhere)

### 1. Clone and prepare the host

```bash
git clone https://github.com/naifabdullahusa-design/net406-naif-cloud-isolation-benchmark.git
cd net406-naif-cloud-isolation-benchmark

sudo apt update
sudo apt install -y python3.12-venv docker.io
sudo usermod -aG docker $USER   # log out and back in for this to take effect
```

### 2. Build and run P1 (VM)

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python -m uvicorn app:app --host 0.0.0.0 --port 9000
```

### 3. Build and run P2 (Docker)

```bash
docker build -t sentiment-api:latest .
docker run -d -p 8000:8000 --name sentiment-service sentiment-api:latest
```

### 4. Run benchmarks

```bash
# M1 cold-start (handled in measure_coldstart.sh / manual loop)

# M2 / M3 throughput + tail latency sweep
for c in 1 5 10 25 50; do
  locust -f locustfile.py -u $c -r $c -t 60s --headless \
    -H http://localhost:9000 --csv=results/p1_c${c}
  locust -f locustfile.py -u $c -r $c -t 60s --headless \
    -H http://localhost:8000 --csv=results/p2_c${c}
done

# S1 steady load (180s @ c=10)
locust -f locustfile.py -u 10 -r 10 -t 180s --headless \
  -H http://localhost:9000 --csv=results/p1_s1
locust -f locustfile.py -u 10 -r 10 -t 180s --headless \
  -H http://localhost:8000 --csv=results/p2_s1

# S2 burst (30s @ c=50)
locust -f locustfile.py -u 50 -r 50 -t 30s --headless \
  -H http://localhost:9000 --csv=results/p1_s2
locust -f locustfile.py -u 50 -r 50 -t 30s --headless \
  -H http://localhost:8000 --csv=results/p2_s2
```

## Headline Results (P1 + P2)

| Metric | P1 VM | P2 Container |
|---|---|---|
| Cold-start mean | 11.69 s | 10.01 s |
| Throughput @ c=10 | 9.90 RPS | 9.80 RPS |
| Throughput @ c=50 | 44.12 RPS | 44.20 RPS |
| p99 latency @ c=50 | 840 ms | 970 ms |
| Idle / peak memory | 802.8 / 801.5 MB | 720.7 / 719.5 MB |
| Peak CPU | 45 % | 41 % |
| Cost / 1000 reqs (S1) | $0.000661 | $0.000658 |

Lambda (P3) numbers are pending and indicated as `???` in the final report.

## Hardware / Software Environment

- **EC2 instance:** t2.small (2 vCPU, 2 GiB RAM), us-east-1
- **OS:** Ubuntu 24.04.4 LTS, kernel 6.17.0-1012-aws
- **Python:** 3.12.3 (host) / 3.11-slim (container)
- **PyTorch:** 2.2.0+cpu
- **Transformers:** 4.40.0
- **Locust:** 2.43.4
- **Docker:** legacy builder


## Engineering Notes

Brief notes on key engineering decisions and challenges encountered during the experiments:

- **Disk capacity**: The default 8 GiB EBS volume on t2.small was insufficient for PyTorch + Transformers + DistilBERT. The volume was expanded to 30 GiB to accommodate both the host venv and the Docker image with the model pre-baked.
- **CPU-only PyTorch**: The standard `torch==2.2.0` wheel pulls in ~3 GiB of CUDA libraries that are unused on a CPU-only t2.small. Switching to `torch==2.2.0+cpu` from PyTorch's CPU index reduced the Docker image size significantly and eliminated build-time disk pressure.
- **Model pre-baking in container**: Initial Docker runs hung because each fresh container would re-download the DistilBERT weights from HuggingFace at startup, often silently. Resolved by adding a `RUN python -c "...from_pretrained(...)"` step to the Dockerfile so the model weights are baked into the image layer. This made P2 cold-starts both faster and more reproducible.
- **Cold-start measurement**: Cold-starts were measured by killing the existing service and timing from the start command to the first successful `/health` 200 response, polling every 100 ms. Five independent runs per platform.
- **Resource sampling**: M4 peak measurements were captured at 25 seconds into a 60-second concurrency-25 Locust run, after ramp-up but before shutdown. Idle samples were taken with the service warm but no load.
- **Locust focus**: The load script targets `POST /predict` only, since `/health` is a readiness probe (used for cold-start timing in M1) rather than the inference endpoint being benchmarked in M2/M3.

## Final Report

See `NET406_Research_Report.docx` for the full IEEE-format paper with all tables, figures, and discussion.

## AI Use Declaration

An AI assistant was used for grammar checking, document formatting, and command-syntax help, per the assignment's permitted-use policy. All experimental setup, raw measurements, interpretation, and final responsibility for the submitted work belong to the author.
