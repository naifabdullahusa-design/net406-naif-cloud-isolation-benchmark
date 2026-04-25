# ============================================================
# Author: Naif (Naifa) - NAIFA-PC
# NET406 Cloud Architecture - Locust Load Test
# Tests POST /predict endpoint per assignment spec (M2, M3)
# ============================================================
from locust import HttpUser, task, between
import random

class SentimentUser(HttpUser):
    wait_time = between(0.5, 1.5)
    
    @task
    def predict(self):
        texts = [
            "This movie is absolutely wonderful",
            "I love this product very much",
            "This is the worst experience ever",
            "Not bad at all, actually quite good",
            "Absolutely terrible and disappointing",
            "Best purchase I have made this year",
            "Completely useless and broken",
            "Highly recommended to everyone"
        ]
        text = random.choice(texts)
        self.client.post("/predict", params={"text": text})
