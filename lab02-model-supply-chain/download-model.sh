#!/usr/bin/env bash
# Download and verify the Lab 02 GGUF model used by model-verify.yaml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="${SCRIPT_DIR}/models"
DEST_FILE="${DEST_DIR}/model.gguf"

# Confirmed against Hugging Face LFS pointer and local lab checksum.
MODEL_URL="${MODEL_URL:-https://huggingface.co/unsloth/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-Q4_K_M.gguf}"
EXPECTED_SHA256="${EXPECTED_SHA256:-ed5fa30c487b282ec156c29062f1222e5c20875a944ac98289dbd242e947f747}"

mkdir -p "${DEST_DIR}"

if [[ -f "${DEST_FILE}" ]]; then
  current_sha="$(shasum -a 256 "${DEST_FILE}" | awk '{print $1}')"
  if [[ "${current_sha}" == "${EXPECTED_SHA256}" ]]; then
    echo "Model already present and checksum matches:"
    echo "  ${DEST_FILE}"
    echo "  sha256:${EXPECTED_SHA256}"
    exit 0
  fi
  echo "Existing file checksum mismatch; re-downloading." >&2
  echo "  expected: ${EXPECTED_SHA256}" >&2
  echo "  actual:   ${current_sha}" >&2
  rm -f "${DEST_FILE}"
fi

tmp_file="$(mktemp "${DEST_DIR}/model.gguf.XXXXXX")"
cleanup() {
  rm -f "${tmp_file}"
}
trap cleanup EXIT

echo "Downloading model..."
echo "  URL: ${MODEL_URL}"
echo "  Dest: ${DEST_FILE}"

if command -v curl >/dev/null 2>&1; then
  curl -fL --retry 3 --retry-delay 2 -o "${tmp_file}" "${MODEL_URL}"
elif command -v wget >/dev/null 2>&1; then
  wget -O "${tmp_file}" "${MODEL_URL}"
else
  echo "ERROR: need curl or wget to download the model." >&2
  exit 1
fi

actual_sha="$(shasum -a 256 "${tmp_file}" | awk '{print $1}')"
if [[ "${actual_sha}" != "${EXPECTED_SHA256}" ]]; then
  echo "ERROR: SHA-256 mismatch after download." >&2
  echo "  expected: ${EXPECTED_SHA256}" >&2
  echo "  actual:   ${actual_sha}" >&2
  exit 1
fi

mv "${tmp_file}" "${DEST_FILE}"
trap - EXIT

echo "Download OK."
echo "  ${DEST_FILE}"
echo "  sha256:${EXPECTED_SHA256}"
