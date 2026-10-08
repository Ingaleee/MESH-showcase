"""Verify an encrypted recovery copy without contacting GitHub or extracting plaintext."""
import ctypes
import datetime
import hashlib
import io
import json
import shutil
import sys
import tarfile
from ctypes import wintypes
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


class Credential(ctypes.Structure):
    _fields_ = [
        ("Flags", wintypes.DWORD),
        ("Type", wintypes.DWORD),
        ("TargetName", wintypes.LPWSTR),
        ("Comment", wintypes.LPWSTR),
        ("LastWritten", wintypes.FILETIME),
        ("CredentialBlobSize", wintypes.DWORD),
        ("CredentialBlob", ctypes.POINTER(ctypes.c_ubyte)),
        ("Persist", wintypes.DWORD),
        ("AttributeCount", wintypes.DWORD),
        ("Attributes", wintypes.LPVOID),
        ("TargetAlias", wintypes.LPWSTR),
        ("UserName", wintypes.LPWSTR),
    ]


def read_key():
    library = ctypes.WinDLL("Advapi32.dll", use_last_error=True)
    library.CredReadW.argtypes = [
        wintypes.LPCWSTR,
        wintypes.DWORD,
        wintypes.DWORD,
        ctypes.POINTER(ctypes.POINTER(Credential)),
    ]
    library.CredReadW.restype = wintypes.BOOL
    library.CredFree.argtypes = [wintypes.LPVOID]
    pointer = ctypes.POINTER(Credential)()
    if not library.CredReadW(
        "MESH-showcase/recovery-root-v1", 1, 0, ctypes.byref(pointer)
    ):
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        value = pointer.contents
        return ctypes.string_at(value.CredentialBlob, value.CredentialBlobSize).decode()
    finally:
        library.CredFree(pointer)


def main():
    root = Path.cwd()
    if root.name != "MESH-showcase" or sys.platform != "win32":
        raise RuntimeError("Use the MESH-showcase checkout on Windows.")
    directory = Path(sys.argv[1]).resolve()
    if not directory.is_relative_to(root / ".cache"):
        raise ValueError("Choose a downloaded recovery artifact inside .cache.")
    key = bytes.fromhex(read_key())
    if len(key) != 32:
        raise ValueError("Invalid recovery key.")
    mirror = root / ".cache/independent-recovery-backup"
    mirror.mkdir(exist_ok=True)
    results = []
    for name in ("application.meshbak", "partner.meshbak"):
        source = directory / name
        if source.stat().st_size > 110 * 1024 * 1024:
            raise ValueError("Recovery archive exceeds the demonstration budget.")
        destination = mirror / name
        shutil.copyfile(source, destination)
        raw = destination.read_bytes()
        if raw[:8] != b"MESHBAK1":
            raise ValueError("Invalid recovery archive.")
        plain = AESGCM(key).decrypt(raw[8:20], raw[20:], raw[:8])
        with tarfile.open(fileobj=io.BytesIO(plain), mode="r:") as archive:
            manifest = json.load(archive.extractfile("./complete.json"))
            if len(manifest["files"]) > 500:
                raise ValueError("Too many archive members.")
            for row in manifest["files"]:
                data = archive.extractfile("./" + row["name"]).read()
                if len(data) != row["size"] or hashlib.sha256(data).hexdigest() != row["sha256"]:
                    raise ValueError("Private inventory member differs.")
            results.append({
                "kind": manifest["kind"],
                "files": len(manifest["files"]),
                "source_revision": manifest["metadata"]["revision"],
                "archive_sha256": hashlib.sha256(raw).hexdigest(),
            })
    proof = {
        "checked_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "environment": "Windows workstation, independent of source/target hosted VMs",
        "github_api_used_for_verification": False,
        "key_read_from_windows_credential_manager": True,
        "only_encrypted_backup_persisted": True,
        "inventories_verified": results,
        "scope": "Another physical device holds ciphertext and an independent key copy; "
                 "no scheduled retention or full Windows application restore claim.",
    }
    (root / ".cache/independent-custody-proof.json").write_text(
        json.dumps(proof, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(proof))


if __name__ == "__main__":
    main()
