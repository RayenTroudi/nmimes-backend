"""Bcrypt hashing/verification for student access-code PINs."""

import bcrypt


def hash_access_code(code: str) -> str:
    """Hash a raw 4-digit PIN for storage in students.access_code_hash."""
    return bcrypt.hashpw(code.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_access_code(code: str, hashed: str) -> bool:
    """Compare a raw PIN against a stored bcrypt hash."""
    return bcrypt.checkpw(code.encode("utf-8"), hashed.encode("utf-8"))
