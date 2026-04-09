import re
import shutil
import tempfile
from pathlib import Path

import joblib
import numpy as np
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from scipy.sparse import hstack
from urllib.parse import urlparse

from .apk_scanner import ApkScannerError, get_apk_scanner
from .feature_engineering import extract_features
from .sms_model import predict_sms

app = FastAPI(title="SafeScan AI Backend")

BASE_DIR = Path(__file__).resolve().parent
APK_SCANNER = None

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
    url_model = joblib.load(BASE_DIR / "models" / "xgb_model_v2.pkl")
    tfidf = joblib.load(BASE_DIR / "models" / "tfidf_vectorizer.pkl")
    threshold = joblib.load(BASE_DIR / "models" / "threshold.pkl")
    numeric_columns = joblib.load(BASE_DIR / "models" / "numeric_columns.pkl")
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

    if parsed.scheme == "http":
        score += 0.2

    if len(url) > 75:
        score += 0.15
    if len(url) > 100:
        score += 0.1

    subdomains = parsed.netloc.count(".")
    if subdomains >= 3:
        score += 0.2
    elif subdomains == 2:
        score += 0.05

    if re.match(r"https?://\d+\.\d+\.\d+\.\d+", url):
        score += 0.4

    for tld in SUSPICIOUS_TLDS:
        if parsed.netloc.endswith(tld):
            score += 0.3
            break

    keyword_hits = sum(1 for kw in PHISHING_KEYWORDS if kw in url_lower)
    score += min(keyword_hits * 0.1, 0.4)

    special_chars = sum(1 for c in parsed.path if c in "@%~-_")
    if special_chars > 3:
        score += 0.1

    return min(score, 1.0)


def get_apk_scanner_instance():
    global APK_SCANNER
    if APK_SCANNER is None:
        APK_SCANNER = get_apk_scanner()
    return APK_SCANNER


# ---------- ENDPOINTS ----------
@app.get("/")
async def root():
    return {
        "service": "SafeScan AI Backend",
        "status": "ok",
        "docs": "/docs",
        "routes": ["/scan/url", "/scan/sms", "/scan/apk"],
    }


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/scan/url")
async def scan_url(request: URLRequest):
    url_input = request.url

    features_df = extract_features(url_input)

    for col in numeric_columns:
        if col not in features_df.columns:
            features_df[col] = np.nan

    features_df = features_df[numeric_columns]

    url_tfidf = tfidf.transform([url_input])

    final_input = hstack([url_tfidf, features_df])
    prob = float(url_model.predict_proba(final_input)[:, 1][0])

    web_feature_cols = [
        "LineOfCode", "LargestLineLength", "NoOfJS", "NoOfCSS",
        "NoOfImage", "NoOfiFrame", "HasFavicon", "HasPasswordField",
        "HasSubmitButton", "HasTitle"
    ]
    web_values = features_df[[c for c in web_feature_cols if c in features_df.columns]].values.flatten()
    all_web_nan = all(np.isnan(v) for v in web_values)

    if all_web_nan:
        structural = structural_risk_score(url_input)
        prob = 0.4 * prob + 0.6 * structural

    if prob > float(threshold):
        label = "danger" if prob > 0.5 else "suspicious"
        return {"status": label, "confidence": round(prob, 4), "message": "Phishing URL detected"}
    return {"status": "safe", "confidence": round(1 - prob, 4), "message": "Legitimate URL"}


@app.post("/scan/sms")
async def scan_sms(request: SMSRequest):
    sms_input = request.sms

    result = predict_sms(sms_input)

    if int(result) == 1:
        return {"status": "suspicious", "message": "Spam SMS"}
    return {"status": "safe", "message": "Legitimate SMS"}


@app.post("/scan/apk")
async def scan_apk(file: UploadFile = File(...)):
    scanner = get_apk_scanner_instance()
    temp_path = None

    try:
        suffix = Path(file.filename or "sample.apk").suffix or ".apk"
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
            shutil.copyfileobj(file.file, temp_file)
            temp_path = Path(temp_file.name)

        result = scanner.scan_file(temp_path)
        return {
            "status": result.status,
            "confidence": result.confidence,
            "probability": result.probability,
            "message": result.message,
        }
    except ApkScannerError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=400, detail=f"Unable to analyze APK: {error}") from error
    finally:
        try:
            file.file.close()
        except Exception:
            pass
        if temp_path is not None and temp_path.exists():
            temp_path.unlink(missing_ok=True)
