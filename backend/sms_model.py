from pathlib import Path

import joblib

MODEL_PATH = Path(__file__).resolve().parent / "models" / "sms_model.pkl"

model = joblib.load(MODEL_PATH)

def predict_sms(text):
    return model.predict([text])[0]