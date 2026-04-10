from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import joblib
import numpy as np
from androguard.misc import AnalyzeAPK


@dataclass(frozen=True)
class ApkScanResult:
    status: str
    confidence: float
    message: str
    probability: float


class ApkScannerError(Exception):
    pass


class ApkScanner:
    def __init__(self, artifact_dir: Path):
        self.artifact_dir = artifact_dir
        self.feature_names = self._load_artifact("feature_names.pkl")
        self.chi2_selector = self._load_artifact("chi2_selector.pkl")
        self.feature_indices = self._load_artifact("feature_indices.pkl")
        self.lgbm_model = self._load_artifact("lgbm_model.pkl")
        self.xgb_model = self._load_artifact("xgb_model.pkl")
        self.feature_index_map = {
            str(name): index for index, name in enumerate(self.feature_names)
        }
        self.threshold = 0.3
        self.danger_threshold = 0.5

    @classmethod
    def load_default(cls) -> "ApkScanner":
        backend_dir = Path(__file__).resolve().parent
        artifact_dir = backend_dir / "models"
        if not artifact_dir.exists():
            raise ApkScannerError(
                f"APK artifacts were not found at {artifact_dir}."
            )
        return cls(artifact_dir)

    def _load_artifact(self, filename: str):
        path = self.artifact_dir / filename
        if not path.exists():
            raise ApkScannerError(f"Missing APK artifact: {path}")
        return joblib.load(path)

    def scan_file(self, apk_path: Path) -> ApkScanResult:
        apk, _, analysis = AnalyzeAPK(str(apk_path))
        if apk is None or analysis is None:
            raise ApkScannerError("Unable to parse the APK file.")

        feature_vector = self._build_feature_vector(apk, analysis)
        reduced_vector = self.chi2_selector.transform(feature_vector.reshape(1, -1))
        selected_vector = reduced_vector[:, self.feature_indices]

        lgbm_probability = float(self.lgbm_model.predict_proba(selected_vector)[0, 1])
        xgb_probability = float(self.xgb_model.predict_proba(selected_vector)[0, 1])
        probability = 0.7 * lgbm_probability + 0.3 * xgb_probability

        if probability >= self.danger_threshold:
            status = "danger"
            message = "Malicious APK detected"
        elif probability >= self.threshold:
            status = "suspicious"
            message = "Suspicious APK detected"
        else:
            status = "safe"
            message = "No malware indicators found"

        confidence = probability if status != "safe" else 1.0 - probability
        return ApkScanResult(
            status=status,
            confidence=round(confidence, 4),
            message=message,
            probability=round(probability, 4),
        )

    def _build_feature_vector(self, apk, analysis) -> np.ndarray:
        features = np.zeros(len(self.feature_names), dtype=np.uint8)

        self._mark_permissions(features, apk.get_permissions())
        self._mark_intents(features, apk.get_activities(), lambda name: apk.get_intent_filters("activity", name))
        self._mark_intents(features, apk.get_services(), lambda name: apk.get_intent_filters("service", name))
        self._mark_intents(features, apk.get_receivers(), lambda name: apk.get_intent_filters("receiver", name))
        self._mark_api_calls(features, analysis)

        return features

    def _mark_permissions(self, features: np.ndarray, permissions: Iterable[str]) -> None:
        for permission in permissions:
            feature_name = f"Permission::{self._normalize_permission(permission)}"
            self._set_feature(features, feature_name)

    def _mark_intents(self, features: np.ndarray, names: Iterable[str], resolver) -> None:
        for name in names:
            try:
                filters = resolver(name)
            except Exception:
                continue
            for raw_value in filters.get("action", []):
                self._set_feature(features, f"Intent::{self._normalize_intent(raw_value)}")
            for raw_value in filters.get("category", []):
                self._set_feature(features, f"Intent::{self._normalize_intent(raw_value)}")

    def _mark_api_calls(self, features: np.ndarray, analysis) -> None:
        for caller_method in analysis.get_methods():
            for _, callee_method, _ in caller_method.get_xref_to():
                class_name, method_name = self._extract_method_parts(callee_method)
                if not class_name or not method_name:
                    continue
                if not class_name.startswith("Landroid/"):
                    continue
                if method_name.startswith("<"):
                    continue
                feature_name = self._normalize_api_call(class_name, method_name)
                self._set_feature(features, feature_name)

    @staticmethod
    def _extract_method_parts(method_obj) -> tuple[str | None, str | None]:
        # Androguard may return either MethodAnalysis or EncodedMethod.
        try:
            encoded_method = method_obj.get_method() if hasattr(method_obj, "get_method") else method_obj
            class_name = encoded_method.get_class_name() if hasattr(encoded_method, "get_class_name") else None
            method_name = encoded_method.get_name() if hasattr(encoded_method, "get_name") else None
            return class_name, method_name
        except Exception:
            return None, None

    def _set_feature(self, features: np.ndarray, feature_name: str) -> None:
        index = self.feature_index_map.get(feature_name)
        if index is not None:
            features[index] = 1

    @staticmethod
    def _normalize_permission(permission: str) -> str:
        return permission.rsplit(".", 1)[-1].strip()

    @staticmethod
    def _normalize_intent(intent_value: str) -> str:
        value = intent_value.strip()
        if value.startswith("android.intent.category."):
            return f"CATEGORY_{value.rsplit('.', 1)[-1]}"
        if value.startswith("android.intent.action."):
            return value.rsplit(".", 1)[-1]
        if value.startswith("android."):
            return value.rsplit(".", 1)[-1]
        return value.rsplit(".", 1)[-1]

    @staticmethod
    def _normalize_api_call(class_name: str, method_name: str) -> str:
        normalized_class = class_name[:-1] if class_name.endswith(";") else class_name
        return f"APICall::{normalized_class}.{method_name}()"


_scanner_instance: ApkScanner | None = None


def get_apk_scanner() -> ApkScanner:
    global _scanner_instance
    if _scanner_instance is None:
        _scanner_instance = ApkScanner.load_default()
    return _scanner_instance
