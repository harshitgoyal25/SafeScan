import pandas as pd
import re
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.svm import LinearSVC
from sklearn.pipeline import Pipeline, FeatureUnion
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics import classification_report
import joblib

# Load
df = pd.read_csv("data/sms_spam.csv")

# Encode labels
df['label'] = df['label'].map({'ham': 0, 'spam': 1})

# Clean text
def clean_text(text):
    text = text.lower()
    text = re.sub(r'http\S+', ' url ', text)
    text = re.sub(r'\d+', ' num ', text)
    return text

X = df['message'].apply(clean_text)
y = df['label']

# TF-IDF
word_tfidf = TfidfVectorizer(ngram_range=(1,2), max_features=3000)
char_tfidf = TfidfVectorizer(analyzer='char', ngram_range=(3,6), max_features=3000)

combined = FeatureUnion([
    ("word", word_tfidf),
    ("char", char_tfidf)
])

model = Pipeline([
    ("tfidf", combined),
    ("svm", LinearSVC(C=0.5, class_weight='balanced', random_state=42))
])

# Split
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, stratify=y, random_state=42
)

# Train
model.fit(X_train, y_train)

# Evaluate
y_pred = model.predict(X_test)
print(classification_report(y_test, y_pred))

# CV
print("CV Accuracy:", cross_val_score(model, X, y, cv=5).mean())

# Save
joblib.dump(model, "models/sms_model.pkl")