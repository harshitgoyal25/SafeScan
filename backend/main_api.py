import os
import shutil
import tempfile
from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import joblib
import numpy as np
from scipy.sparse import hstack
from urllib.parse import urlparse
import re
from feature_engineering import extract_features
from sms_model import predict_sms
from apk_scanner import extract_apk_features

app = FastAPI(title="SafeScan AI Backend")

# ---------- CORS ----------
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------- LOAD MODELS ----------
try:
    url_model = joblib.load("models/xgb_model_v2.pkl")
    tfidf = joblib.load("models/tfidf_vectorizer.pkl")
    threshold = joblib.load("models/threshold.pkl")
    numeric_columns = joblib.load("models/numeric_columns.pkl")
    
    # APK Models
    apk_chi2 = joblib.load("models/chi2_selector.pkl")
    apk_feature_indices = joblib.load("models/feature_indices.pkl")
    apk_lgbm = joblib.load("models/lgbm_model.pkl")
except Exception as e:
    print(f"Error loading models: {e}")

# ---------- REQUEST MODELS ----------
class URLRequest(BaseModel):
    url: str

class SMSRequest(BaseModel):
    sms: str

# ---------- STRUCTURAL URL HEURISTICS ----------
PHISHING_KEYWORDS = [
    "login", "verify", "secure", "account", "update", "confirm",
    "banking", "paypal", "amazon", "apple", "microsoft", "google",
    "signin", "password", "credential", "suspend", "alert", "wallet",
    "free", "winner", "prize", "claim", "lucky", "reward"
]

SUSPICIOUS_TLDS = [".ru", ".tk", ".ml", ".ga", ".cf", ".gq", ".xyz", ".top", ".click", ".work"]

def structural_risk_score(url: str) -> float:
    """
    Returns a 0.0 - 1.0 risk score using URL structure alone.
    Used as a fallback when web scraping features are all NaN.
    """
    score = 0.0
    parsed = urlparse(url)
    url_lower = url.lower()

    # HTTP (not HTTPS) is risky
    if parsed.scheme == "http":
        score += 0.2

    # Long URLs are more suspicious
    if len(url) > 75:
        score += 0.15
    if len(url) > 100:
        score += 0.1

    # Many subdomains
    subdomains = parsed.netloc.count(".")
    if subdomains >= 3:
        score += 0.2
    elif subdomains == 2:
        score += 0.05

    # IP address instead of domain
    if re.match(r"https?://\d+\.\d+\.\d+\.\d+", url):
        score += 0.4

    # Suspicious TLD
    for tld in SUSPICIOUS_TLDS:
        if parsed.netloc.endswith(tld):
            score += 0.3
            break

    # Phishing keywords in URL
    keyword_hits = sum(1 for kw in PHISHING_KEYWORDS if kw in url_lower)
    score += min(keyword_hits * 0.1, 0.4)

    # Special chars in path (common in phishing)
    special_chars = sum(1 for c in parsed.path if c in "@%~-_")
    if special_chars > 3:
        score += 0.1

    return min(score, 1.0)


# ---------- ENDPOINTS ----------

@app.post("/scan/url")
async def scan_url(request: URLRequest):
    url_input = request.url

    # 1. Extract numeric features
    features_df = extract_features(url_input)

    for col in numeric_columns:
        if col not in features_df.columns:
            features_df[col] = np.nan

    features_df = features_df[numeric_columns]

    # 2. TF-IDF
    url_tfidf = tfidf.transform([url_input])

    # 3. Combine and predict
    final_input = hstack([url_tfidf, features_df])
    prob = float(url_model.predict_proba(final_input)[:,1][0])

    # 4. Check if web features are all NaN (page was unreachable)
    web_feature_cols = [
        "LineOfCode", "LargestLineLength", "NoOfJS", "NoOfCSS",
        "NoOfImage", "NoOfiFrame", "HasFavicon", "HasPasswordField",
        "HasSubmitButton", "HasTitle"
    ]
    web_values = features_df[[c for c in web_feature_cols if c in features_df.columns]].values.flatten()
    all_web_nan = all(np.isnan(v) for v in web_values)

    # 5. If page was unreachable, blend ML prob with structural heuristics
    if all_web_nan:
        structural = structural_risk_score(url_input)
        # Give 60% weight to structural score, 40% to ML when page is dead
        prob = 0.4 * prob + 0.6 * structural

    if prob > float(threshold):
        label = "danger" if prob > 0.5 else "suspicious"
        return {"status": label, "confidence": round(prob, 4), "message": "Phishing URL detected"}
    else:
        return {"status": "safe", "confidence": round(1 - prob, 4), "message": "Legitimate URL"}


@app.post("/scan/sms")
async def scan_sms(request: SMSRequest):
    sms_input = request.sms

    result = predict_sms(sms_input)

    # The original ML model returns 1 for Spam and 0 for Legitimate
    if int(result) == 1:
        return {"status": "suspicious", "message": "Spam SMS"}
    else:
        return {"status": "safe", "message": "Legitimate SMS"}

@app.post("/scan/apk")
async def scan_apk(file: UploadFile = File(...)):
    if not file.filename.endswith(".apk"):
        return {"status": "error", "message": "File must be an Android APK"}

    # Save to temporary file safely
    try:
        fd, temp_path = tempfile.mkstemp(suffix=".apk")
        os.close(fd)
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        features = extract_apk_features(temp_path)
    finally:
        if 'temp_path' in locals() and os.path.exists(temp_path):
            os.remove(temp_path)

    if features is None:
        return {"status": "error", "message": "Invalid APK structure or failed to parse."}
        
    # 1. Chi2 Feature Selection
    reduced_features = apk_chi2.transform(features)
    
    # 2. Select top 2000 indices
    final_features = reduced_features[:, apk_feature_indices]
    
    # 3. Predict ML Probabilities (LightGBM)
    prob_malicious = float(apk_lgbm.predict_proba(final_features)[:, 1][0])
    
    if prob_malicious > 0.5:
        label = "danger" if prob_malicious > 0.75 else "suspicious"
        msg = "Malware detected in APK"
    else:
        label = "safe"
        msg = "Legitimate APK"
        
    return {"status": label, "confidence": round(prob_malicious, 4), "message": msg}

