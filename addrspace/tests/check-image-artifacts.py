#!/usr/bin/env python3
"""Read-only GHCR checks for the immutable application artifacts in this PR."""

import json
import re
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import yaml


GHCR = "https://ghcr.io"
ACCEPT = ", ".join(
    (
        "application/vnd.oci.image.index.v1+json",
        "application/vnd.oci.image.manifest.v1+json",
        "application/vnd.docker.distribution.manifest.list.v2+json",
        "application/vnd.docker.distribution.manifest.v2+json",
    )
)
WAIT_SECONDS = 30 * 60
POLL_SECONDS = 30


def token_for(repository):
    query = urlencode({"scope": f"repository:{repository}:pull", "service": "ghcr.io"})
    with urlopen(f"{GHCR}/token?{query}", timeout=15) as response:
        token = json.load(response).get("token")
    if not token:
        raise RuntimeError(f"GHCR returned no anonymous pull token for {repository}")
    return token


def manifest_digest(repository, reference, token):
    request = Request(
        f"{GHCR}/v2/{repository}/manifests/{reference}",
        headers={"Authorization": f"Bearer {token}", "Accept": ACCEPT},
    )
    with urlopen(request, timeout=20) as response:
        digest = response.headers.get("Docker-Content-Digest")
    if not digest:
        raise RuntimeError(f"GHCR omitted Docker-Content-Digest for {repository}:{reference}")
    return digest


def wait_for_manifest(repository, reference, token, expected_digest=None):
    deadline = time.monotonic() + WAIT_SECONDS
    last_error = "not checked yet"
    token_refreshes = 0
    while time.monotonic() < deadline:
        try:
            digest = manifest_digest(repository, reference, token)
            if expected_digest and digest != expected_digest:
                raise RuntimeError(
                    f"{repository}:{reference} resolves to {digest}, expected {expected_digest}"
                )
            return digest
        except HTTPError as error:
            if error.code == 401:
                if token_refreshes >= 2:
                    raise RuntimeError(f"GHCR denied anonymous pull access to {repository}:{reference}") from error
                token = token_for(repository)
                token_refreshes += 1
                continue
            if error.code not in (404, 429) and error.code < 500:
                raise RuntimeError(f"GHCR rejected {repository}:{reference}: HTTP {error.code}") from error
            last_error = f"HTTP {error.code}"
        except (URLError, TimeoutError) as error:
            last_error = str(error)
        print(f"Waiting for public GHCR artifact {repository}:{reference} ({last_error})", flush=True)
        time.sleep(POLL_SECONDS)
    raise RuntimeError(
        f"Timed out after {WAIT_SECONDS // 60} minutes waiting for {repository}:{reference} ({last_error})"
    )


def main():
    with open("addrspace/apps/anvil/kustomization.yaml", encoding="utf-8") as stream:
        anvil = yaml.safe_load(stream)
    with open("addrspace/apps/dojo/overlays/staging/kustomization.yaml", encoding="utf-8") as stream:
        dojo = yaml.safe_load(stream)

    base_match = re.search(r"ref=([a-f0-9]{40})$", anvil["resources"][0])
    if not base_match:
        raise RuntimeError("Anvil base must be pinned to a full immutable Git commit SHA")
    anvil_sha = base_match.group(1)
    anvil_tags = {
        image["name"]: image.get("newTag")
        for image in anvil.get("images", [])
        if image["name"] in ("ghcr.io/blogle/anvil", "ghcr.io/blogle/anvil-sandbox")
    }
    expected_anvil_tag = f"sha-{anvil_sha}"
    if anvil_tags != {
        "ghcr.io/blogle/anvil": expected_anvil_tag,
        "ghcr.io/blogle/anvil-sandbox": expected_anvil_tag,
    }:
        raise RuntimeError("Anvil base and both immutable image tags must use the same commit SHA")

    dojo_ref = re.search(r"ref=(v[0-9]+\.[0-9]+\.[0-9]+)$", dojo["resources"][0])
    if not dojo_ref:
        raise RuntimeError("Dojo staging base must be pinned to a semantic release tag")
    dojo_version = dojo_ref.group(1)
    dojo_images = [image for image in dojo.get("images", []) if image.get("name") == "ghcr.io/blogle/dojo2"]
    if len(dojo_images) != 1:
        raise RuntimeError("Dojo staging must declare one versioned release image")
    dojo_image = dojo_images[0]
    dojo_digest = dojo_image.get("digest", "")
    if dojo_image.get("newTag") != dojo_version or not re.fullmatch(r"sha256:[a-f0-9]{64}", dojo_digest):
        raise RuntimeError("Dojo staging base, semantic image version, and digest must be pinned together")

    anvil_token = token_for("blogle/anvil")
    dojo_token = token_for("blogle/dojo2")
    for image in ("ghcr.io/blogle/anvil", "ghcr.io/blogle/anvil-sandbox"):
        repository = image.removeprefix("ghcr.io/")
        digest = wait_for_manifest(repository, expected_anvil_tag, anvil_token)
        print(f"Verified {image}:{expected_anvil_tag} ({digest})")

    dojo_repository = "blogle/dojo2"
    version_digest = wait_for_manifest(dojo_repository, dojo_version, dojo_token, dojo_digest)
    wait_for_manifest(dojo_repository, dojo_digest, dojo_token, dojo_digest)
    print(f"Verified ghcr.io/{dojo_repository}:{dojo_version}@{version_digest}")


if __name__ == "__main__":
    main()
