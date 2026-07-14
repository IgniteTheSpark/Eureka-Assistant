from pynput.keyboard import Key

from ring_desktop.actions import parse_keyspec, parse_sequence


def test_plain_special_key():
    assert parse_keyspec("enter") == ([], Key.enter)


def test_char_key():
    assert parse_keyspec("a") == ([], "a")


def test_ctrl_combo_char():
    assert parse_keyspec("ctrl+u") == ([Key.ctrl], "u")


def test_shift_plus_special():
    assert parse_keyspec("shift+tab") == ([Key.shift], Key.tab)


def test_cmd_combo():
    assert parse_keyspec("cmd+enter") == ([Key.cmd], Key.enter)


def test_sequence_clear_all():
    assert parse_sequence("cmd+a;backspace") == [([Key.cmd], "a"), ([], Key.backspace)]


def test_sequence_single():
    assert parse_sequence("ctrl+u") == [([Key.ctrl], "u")]


def test_sequence_strips_blanks():
    assert parse_sequence("cmd+a ; backspace ;") == [([Key.cmd], "a"), ([], Key.backspace)]
