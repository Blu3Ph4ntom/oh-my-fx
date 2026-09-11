#!/usr/bin/env sh
# omfx installer (macOS / Linux)
set -eu

REPO="${OMFX_REPO:-blu3ph4ntom/oh-my-fx}"
INSTALL_DIR="${OMFX_INSTALL_DIR:-${HOME}/.omfx/bin}"
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

uname_s="$(uname -s)"
uname_m="$(uname -m)"
case "${uname_s}" in
  Darwin) os="darwin" ;;
  Linux) os="linux" ;;
  *)
    echo "omfx installer: unsupported OS '${uname_s}'. Build from source or use a published binary." >&2
    exit 1
    ;;
esac
case "${uname_m}" in
  x86_64|amd64) arch="x86_64" ;;
  arm64|aarch64) arch="aarch64" ;;
  *)
    echo "omfx installer: unsupported arch '${uname_m}'." >&2
    exit 1
    ;;
esac

asset="omfx-${os}-${arch}"
api="https://api.github.com/repos/${REPO}/releases/latest"

echo "Resolving latest omfx release for ${os}/${arch}..."
json="$(curl -fsSL "${api}")"
tag="$(printf '%s' "${json}" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
url="$(printf '%s' "${json}" | tr ',' '\n' | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*'"${asset}"'[^"]*\)".*/\1/p' | head -n 1)"

if [ -z "${url}" ]; then
  echo "omfx installer: no release asset matching '${asset}'." >&2
  echo "Publish a GitHub Release with that asset, or install a CI artifact manually." >&2
  echo "Repo: https://github.com/${REPO}" >&2
  exit 1
fi

echo "Downloading ${tag} (${asset})..."
archive="${TMP_DIR}/omfx.tgz"
curl -fsSL "${url}" -o "${archive}"

mkdir -p "${INSTALL_DIR}"
case "${url}" in
  *.zip)
    if command -v unzip >/dev/null 2>&1; then
      unzip -qo "${archive}" -d "${TMP_DIR}/out"
    else
      echo "omfx installer: unzip is required for zip assets." >&2
      exit 1
    fi
    ;;
  *)
    tar -xzf "${archive}" -C "${TMP_DIR}"
    mkdir -p "${TMP_DIR}/out"
    # Prefer extracted omfx binary wherever it landed.
    found="$(find "${TMP_DIR}" -type f -name omfx | head -n 1 || true)"
    if [ -n "${found}" ]; then
      cp "${found}" "${TMP_DIR}/out/omfx"
    else
      echo "omfx installer: archive did not contain an omfx binary." >&2
      exit 1
    fi
    ;;
esac

bin="$(find "${TMP_DIR}/out" -type f -name omfx | head -n 1 || true)"
if [ -z "${bin}" ]; then
  bin="$(find "${TMP_DIR}" -type f -name omfx | head -n 1 || true)"
fi
if [ -z "${bin}" ]; then
  echo "omfx installer: could not locate omfx binary in the archive." >&2
  exit 1
fi

install -m 755 "${bin}" "${INSTALL_DIR}/omfx"
echo "Installed ${INSTALL_DIR}/omfx"

case ":${PATH}:" in
  *":${INSTALL_DIR}:"*) ;;
  *)
    echo
    echo "Add omfx to your PATH:"
    echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
    ;;
esac

echo "Run: omfx --version"
