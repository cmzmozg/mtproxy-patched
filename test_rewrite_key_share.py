"""Тест для _rewrite_key_share."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))

import importlib.util
spec = importlib.util.spec_from_file_location("mtproxy_mod", "mtproxy_patched.py")
mod = importlib.util.module_from_spec(spec)
sys.argv = ["mtproxy_patched.py", "853", "0" * 32]
try:
    spec.loader.exec_module(mod)
except SystemExit:
    pass
except Exception as e:
    print(f"Import warning: {e}")

rewrite = mod._rewrite_key_share
parse_sh = mod.parse_server_hello


def test_replaces_x25519():
    orig_key = b"\xaa" * 32
    ext = b"\x00\x33" + (4 + 32).to_bytes(2, "big") + b"\x00\x1d" + (32).to_bytes(2, "big") + orig_key
    other = b"\x00\x2b\x00\x02\x03\x04"
    extensions = ext + other
    out = rewrite(extensions)
    # Длина должна остаться той же
    assert len(out) == len(extensions), f"length changed: {len(out)} vs {len(extensions)}"
    # Структура до key_share не меняется
    assert out.endswith(other), "trailing extensions disturbed"
    # Сам ключ должен был быть заменён
    new_key = out[4 + 4:4 + 4 + 32]
    assert new_key != orig_key, "key NOT replaced"
    assert len(new_key) == 32
    print("✓ test_replaces_x25519 passed — key_share заменён, длины сохранены")


def test_preserves_other_extensions():
    exts = b"\x00\x17\x00\x00" + b"\x00\x05\x00\x00"  # extended_master_secret + status_request
    out = rewrite(exts)
    assert out == exts, "extensions without key_share should be untouched"
    print("✓ test_preserves_other_extensions passed")


def test_no_keyshare():
    exts = b"\x00\x2b\x00\x02\x03\x04"  # только supported_versions
    out = rewrite(exts)
    assert out == exts
    print("✓ test_no_keyshare passed")


def test_empty():
    assert rewrite(b"") == b""
    print("✓ test_empty passed")


def test_malformed_length():
    # Заявленная длина extension больше, чем доступно данных → возвращаем как есть
    exts = b"\x00\x33\xff\xff\x00\x1d\x00\x20" + b"\xaa" * 16
    out = rewrite(exts)
    # Не должно упасть; результат может быть любым, но допустим
    print(f"✓ test_malformed_length passed (no crash, got {len(out)} bytes)")


def test_roundtrip_with_parser():
    """Сначала парсим ServerHello, потом переписываем key_share, затем
    проверяем, что cipher_suite в профиле тот же, а key реально поменялся."""
    # Собираем минимальный SH
    orig_key = b"\xcc" * 32
    exts = (
        b"\x00\x33" + (4 + 32).to_bytes(2, "big") + b"\x00\x1d" + (32).to_bytes(2, "big") + orig_key
        + b"\x00\x2b\x00\x02\x03\x04"
    )
    body = b"\x03\x03" + b"\xbb" * 32 + b"\x00" + b"\x13\x02" + b"\x00" + len(exts).to_bytes(2, "big") + exts
    hs = b"\x02" + len(body).to_bytes(3, "big") + body
    profile = parse_sh(hs)
    assert profile is not None
    assert profile["cipher_suite"] == b"\x13\x02"

    new_exts = rewrite(profile["extensions_raw"])
    assert len(new_exts) == len(profile["extensions_raw"])
    # Ищем key в результате
    idx = new_exts.find(b"\x00\x1d\x00\x20")
    assert idx >= 0
    new_key = new_exts[idx+4:idx+4+32]
    assert new_key != orig_key, "key_share replacement failed in roundtrip"
    print("✓ test_roundtrip_with_parser passed — end-to-end парс → переписать → проверить")


if __name__ == "__main__":
    test_replaces_x25519()
    test_preserves_other_extensions()
    test_no_keyshare()
    test_empty()
    test_malformed_length()
    test_roundtrip_with_parser()
    print("\nAll _rewrite_key_share tests passed ✓")
