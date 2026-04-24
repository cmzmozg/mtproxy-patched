"""Миниатюрный unit-тест для parse_server_hello.
Не требует сети, не требует реального Telegram/TLS стека."""
import sys
import os
sys.path.insert(0, os.path.dirname(__file__))

# Импортируем только нужные функции; обходим init_config.
import importlib.util
spec = importlib.util.spec_from_file_location("mtproxy_mod", "mtproxy_patched.py")
mod = importlib.util.module_from_spec(spec)
# Патчим argv, чтобы импорт не падал на отсутствии config
sys.argv = ["mtproxy_patched.py", "853", "0" * 32]
try:
    spec.loader.exec_module(mod)
except SystemExit:
    pass
except Exception as e:
    # Импорт может падать на инициализации сети — это норм, нам нужна только функция
    print(f"Import warning (expected in sandbox): {e}")

parse_server_hello = mod.parse_server_hello


def build_synthetic_server_hello(cipher=b"\x13\x01", sess_id=b"\xaa" * 32,
                                  extensions=b""):
    """Собирает корректный ServerHello handshake record (без record-layer хедера)."""
    random32 = b"\xbb" * 32
    body = b"\x03\x03"                          # version
    body += random32                            # random
    body += bytes([len(sess_id)]) + sess_id     # session_id_echo
    body += cipher                              # cipher_suite
    body += b"\x00"                             # compression = null
    body += len(extensions).to_bytes(2, "big")  # extensions length
    body += extensions
    # Handshake header
    hs = b"\x02" + len(body).to_bytes(3, "big") + body
    return hs


def test_basic():
    # Типичный минимальный TLS 1.3 ServerHello от Telegram MTProxy
    exts = (
        b"\x00\x33\x00\x24"             # key_share ext: type + len
        + b"\x00\x1d\x00\x20" + b"\xcc" * 32   # x25519 key
        + b"\x00\x2b\x00\x02\x03\x04"   # supported_versions: TLS 1.3
    )
    sh = build_synthetic_server_hello(cipher=b"\x13\x01", extensions=exts)
    parsed = parse_server_hello(sh)
    assert parsed is not None, "parse failed on valid ServerHello"
    assert parsed["version"] == b"\x03\x03", f"bad version: {parsed['version']!r}"
    assert parsed["cipher_suite"] == b"\x13\x01", f"bad cipher: {parsed['cipher_suite']!r}"
    assert parsed["extensions_raw"] == exts, "extensions mismatch"
    print("✓ test_basic passed")


def test_different_cipher():
    sh = build_synthetic_server_hello(cipher=b"\x13\x02", extensions=b"")
    parsed = parse_server_hello(sh)
    assert parsed is not None
    assert parsed["cipher_suite"] == b"\x13\x02"
    assert parsed["extensions_raw"] == b""
    print("✓ test_different_cipher passed")


def test_long_extensions():
    # Много extensions, как у настоящего vkvideo.ru / habr.com
    exts = b""
    exts += b"\x00\x33\x00\x24" + b"\x00\x1d\x00\x20" + b"\xab" * 32
    exts += b"\x00\x2b\x00\x02\x03\x04"
    exts += b"\x00\x17\x00\x00"
    exts += b"\x00\x05\x00\x00"  # status_request
    exts += b"\x00\x0b\x00\x02\x01\x00"  # ec_point_formats
    sh = build_synthetic_server_hello(cipher=b"\x13\x03", extensions=exts)
    parsed = parse_server_hello(sh)
    assert parsed is not None
    assert parsed["cipher_suite"] == b"\x13\x03"
    assert parsed["extensions_raw"] == exts
    print(f"✓ test_long_extensions passed ({len(exts)} bytes ext)")


def test_malformed():
    # Слишком короткий
    assert parse_server_hello(b"") is None
    assert parse_server_hello(b"\x02\x00\x00\x00") is None
    # Не ServerHello (ClientHello type)
    bad = b"\x01" + (50).to_bytes(3, "big") + b"\x00" * 50
    assert parse_server_hello(bad) is None
    # Длина extensions больше, чем данных
    body = b"\x03\x03" + b"\xbb" * 32 + b"\x00" + b"\x13\x01" + b"\x00" + b"\xff\xff"
    hs = b"\x02" + len(body).to_bytes(3, "big") + body
    assert parse_server_hello(hs) is None
    print("✓ test_malformed passed")


def test_empty_session_id():
    sh = build_synthetic_server_hello(sess_id=b"", extensions=b"\x00\x2b\x00\x02\x03\x04")
    parsed = parse_server_hello(sh)
    assert parsed is not None
    assert parsed["cipher_suite"] == b"\x13\x01"
    print("✓ test_empty_session_id passed")


if __name__ == "__main__":
    test_basic()
    test_different_cipher()
    test_long_extensions()
    test_malformed()
    test_empty_session_id()
    print("\nAll parse_server_hello tests passed ✓")
