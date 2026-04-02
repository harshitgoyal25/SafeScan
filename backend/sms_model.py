import joblib

model = joblib.load("models/sms_model.pkl")

def predict_sms(text):
    return model.predict([text])[0]