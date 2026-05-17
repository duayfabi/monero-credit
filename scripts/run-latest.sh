#!/usr/bin/env bash
# Télécharge le dernier binaire publié sur la release `nightly` du repo
# duayfabi/monero-credit, vérifie son SHA256, puis l'exécute.
#
# Conçu pour être lancé par SemaphoreUI (ou tout autre orchestrateur).
# Le script n'embarque AUCUN secret : toutes les variables sensibles
# (MONERO_ADDRESS, USER_AGENT, GOTIFY_*, SUCCESS_MSG) doivent être
# fournies via l'environnement par l'appelant.
#
# Variables optionnelles :
#   GH_REPO          défaut: duayfabi/monero-credit
#   GH_TAG           défaut: nightly
#   GH_TOKEN         requis uniquement si le repo est privé
#   INSTALL_DIR      défaut: ${XDG_CACHE_HOME:-$HOME/.cache}/monero-gotify
#                    (chemin writable par l'utilisateur du runner Semaphore)
#   ASSET_NAME       défaut: monero-gotify-x86_64-linux-musl

set -euo pipefail

GH_REPO="${GH_REPO:-duayfabi/monero-credit}"
GH_TAG="${GH_TAG:-nightly}"
INSTALL_DIR="${INSTALL_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/monero-gotify}"
ASSET_NAME="${ASSET_NAME:-monero-gotify-x86_64-linux-musl}"

mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

CURL_AUTH=()
if [[ -n "${GH_TOKEN:-}" ]]; then
  CURL_AUTH=(-H "Authorization: Bearer ${GH_TOKEN}")
fi

BASE_URL="https://github.com/${GH_REPO}/releases/download/${GH_TAG}"

echo ">> Téléchargement de ${ASSET_NAME} depuis ${BASE_URL}"
curl -fsSL "${CURL_AUTH[@]}" -o "${ASSET_NAME}.new" "${BASE_URL}/${ASSET_NAME}"
curl -fsSL "${CURL_AUTH[@]}" -o "${ASSET_NAME}.sha256.new" "${BASE_URL}/${ASSET_NAME}.sha256"

echo ">> Vérification du SHA256"
EXPECTED_SHA="$(awk '{print $1}' "${ASSET_NAME}.sha256.new")"
ACTUAL_SHA="$(sha256sum "${ASSET_NAME}.new" | awk '{print $1}')"
if [[ "${EXPECTED_SHA}" != "${ACTUAL_SHA}" ]]; then
  echo "!! SHA256 mismatch : attendu ${EXPECTED_SHA}, obtenu ${ACTUAL_SHA}" >&2
  rm -f "${ASSET_NAME}.new" "${ASSET_NAME}.sha256.new"
  exit 1
fi

mv "${ASSET_NAME}.new" "${ASSET_NAME}"
mv "${ASSET_NAME}.sha256.new" "${ASSET_NAME}.sha256"
chmod +x "${ASSET_NAME}"

echo ">> Exécution"
exec "./${ASSET_NAME}"
