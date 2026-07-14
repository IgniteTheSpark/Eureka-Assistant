from ring_desktop.recorder import Recorder


def test_finalizes_after_gap():
    t = [0.0]
    cap = []
    r = Recorder(on_capture=cap.append, gap=0.6, now=lambda: t[0])
    r.start()
    r.feed(b"abc")
    t[0] = 0.3
    r.tick()
    assert r.recording and cap == []   # 还在 gap 内
    t[0] = 1.0
    r.tick()
    assert not r.recording and cap == [b"abc"]   # 断流收尾


def test_feed_ignored_when_not_recording():
    t = [0.0]
    cap = []
    r = Recorder(on_capture=cap.append, now=lambda: t[0])
    r.feed(b"x")
    t[0] = 2.0
    r.tick()
    assert cap == []


def test_max_duration_finalizes():
    t = [0.0]
    cap = []
    r = Recorder(on_capture=cap.append, gap=99, max_dur=5.0, now=lambda: t[0])
    r.start()
    r.feed(b"y")
    t[0] = 6.0
    r.tick()
    assert cap == [b"y"]


def test_empty_capture_not_emitted():
    t = [0.0]
    cap = []
    r = Recorder(on_capture=cap.append, gap=0.6, now=lambda: t[0])
    r.start()           # 没喂任何帧
    t[0] = 1.0
    r.tick()
    assert cap == []


def test_second_doubletap_stops_immediately():
    t = [0.0]
    cap = []
    r = Recorder(on_capture=cap.append, now=lambda: t[0])
    r.start()
    r.feed(b"abc")
    r.stop()            # 第二次双击 = 立即停
    assert not r.recording and cap == [b"abc"]


def test_start_blocked_during_cooldown():
    t = [0.0]
    cap = []
    r = Recorder(on_capture=cap.append, gap=0.6, cooldown=1.0, now=lambda: t[0])
    r.start()
    r.feed(b"x")
    r.stop()            # 停在 t=0 → 冷却到 t=1.0
    t[0] = 0.5
    r.start()           # 冷却内 → 忽略
    r.feed(b"y")
    assert not r.recording
    t[0] = 3.0
    r.start()           # 冷却已过 → 正常
    r.feed(b"z")
    t[0] = 5.0
    r.tick()
    assert cap == [b"x", b"z"]   # "y" 被冷却挡掉，没录进去
