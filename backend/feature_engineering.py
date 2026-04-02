import requests
import pandas as pd
import numpy as np
import tldextract
from bs4 import BeautifulSoup
from urllib.parse import urlparse

def extract_features(url):

    features = {}

    # -------- URL FEATURES --------
    parsed = urlparse(url)
    
    features["URLLength"] = len(url)
    features["DomainLength"] = len(parsed.netloc)
    features["IsHTTPS"] = 1 if parsed.scheme == "https" else 0
    features["NoOfSubDomain"] = parsed.netloc.count('.') - 1
    
    features["NoOfLettersInURL"] = sum(c.isalpha() for c in url)
    features["NoOfDegitsInURL"] = sum(c.isdigit() for c in url)
    features["NoOfOtherSpecialCharsInURL"] = sum(
        not c.isalnum() for c in url
    )

    total_len = len(url)
    features["LetterRatioInURL"] = features["NoOfLettersInURL"] / total_len if total_len else 0
    features["DegitRatioInURL"] = features["NoOfDegitsInURL"] / total_len if total_len else 0
    features["SpacialCharRatioInURL"] = features["NoOfOtherSpecialCharsInURL"] / total_len if total_len else 0
    
    
        # -------- WEBPAGE FEATURES --------
    try:
        response = requests.get(url, timeout=5)
        html = response.text
        soup = BeautifulSoup(html, "html.parser")

        features["LineOfCode"] = len(html.split("\n"))
        features["LargestLineLength"] = max(len(line) for line in html.split("\n"))

        features["NoOfJS"] = len(soup.find_all("script"))
        features["NoOfCSS"] = len(soup.find_all("link", rel="stylesheet"))
        features["NoOfImage"] = len(soup.find_all("img"))
        features["NoOfiFrame"] = len(soup.find_all("iframe"))
        features["NoOfPopup"] = html.lower().count("popup")

        features["HasFavicon"] = 1 if soup.find("link", rel=lambda x: x and "icon" in x.lower()) else 0
        features["HasPasswordField"] = 1 if soup.find("input", {"type": "password"}) else 0
        features["HasSubmitButton"] = 1 if soup.find("input", {"type": "submit"}) else 0

        features["HasTitle"] = 1 if soup.title else 0

    except:
        # If scraping fails, fill with NaN
        features["LineOfCode"] = np.nan
        features["LargestLineLength"] = np.nan
        features["NoOfJS"] = np.nan
        features["NoOfCSS"] = np.nan
        features["NoOfImage"] = np.nan
        features["NoOfiFrame"] = np.nan
        features["NoOfPopup"] = np.nan
        features["HasFavicon"] = np.nan
        features["HasPasswordField"] = np.nan
        features["HasSubmitButton"] = np.nan
        features["HasTitle"] = np.nan
        
    return pd.DataFrame([features])




