# ============================================================
# Author: Naif (Naifa)
# Workstation: NAIFA-PC
# NET406 Cloud Architecture - Spring 2025-26
# P1 (VM) and P2 (Docker) Implementation
# ============================================================

from fastapi import FastAPI, HTTPException
from transformers import AutoTokenizer, AutoModelForSequenceClassification
import torch
import torch.nn.functional as F
import time

app = FastAPI()

MODEL_NAME = "distilbert-base-uncased-finetuned-sst-2-english"
print(f"Loading model {MODEL_NAME}...")
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
model = AutoModelForSequenceClassification.from_pretrained(MODEL_NAME)

model = torch.quantization.quantize_dynamic(
    model, {torch.nn.Linear}, dtype=torch.qint8
)
model.eval()
print("Model loaded and quantized.")

LABELS = {0: "NEGATIVE", 1: "POSITIVE"}

@app.get("/health")
def health_check():
    return {"status": "ok"}

@app.post("/predict")
def predict(text: str):
    if not text or len(text.strip()) == 0:
        raise HTTPException(status_code=400, detail="Empty text")
    if len(text) > 512:
        text = text[:512]
    start = time.time()
    inputs = tokenizer(text, return_tensors="pt", truncation=True, max_length=128)
    with torch.no_grad():
        outputs = model(**inputs)
        probs = F.softmax(outputs.logits, dim=-1)
        confidence, predicted_class = torch.max(probs, dim=-1)
    latency_ms = (time.time() - start) * 1000
    return {
        "text": text,
        "prediction": LABELS[predicted_class.item()],
        "confidence": round(confidence.item(), 4),
        "latency_ms": round(latency_ms, 2)
    }
