const GESTURES = [
  "单击",
  "双击",
  "三击",
  "上滑",
  "下滑",
  "左滑",
  "右滑",
] as const;

const HAPTICS = [
  { detail: "明确提醒", id: "strong", label: "强烈", signal: "burst" },
  {
    detail: "持续状态",
    id: "continuous",
    label: "连续",
    signal: "continuous-wave",
  },
  {
    detail: "逐步增强",
    id: "rising",
    label: "渐强",
    signal: "rising-wave",
  },
] as const;

export function SenseRingEffects() {
  return (
    <div aria-hidden="true" className="sense-ring-effects">
      <div className="sense-speech-effect">
        <article className="sense-speech-card sense-speech-card-capturing">
          <strong>正在聆听</strong>
          <small>捕捉来自戒指的语音</small>
          <i className="sense-dither-field" />
        </article>
        <article className="sense-speech-card sense-speech-card-transcribing">
          <strong>正在转写</strong>
          <small>让语音成为可以继续使用的文字</small>
          <i className="sense-dither-field" />
        </article>
      </div>

      <div className="sense-touch-effect">
        {GESTURES.map((gesture, index) => (
          <span className="sense-gesture-pill" data-index={index} key={gesture}>
            <i className="sense-gesture-pill-index">
              {String(index + 1).padStart(2, "0")}
            </i>
            <strong>{gesture}</strong>
          </span>
        ))}
      </div>

      <div
        className="sense-feel-effect"
        data-haptic-placement="right-field"
        data-haptic-proximity="close"
      >
        {HAPTICS.map((haptic) => (
          <span className={`haptic-pattern haptic-${haptic.id}`} key={haptic.id}>
            <i className="haptic-ring-illustration">
              <i className="haptic-ring-outline" />
              <i className={`haptic-${haptic.signal}`}>
                <b /><b /><b /><b />
              </i>
            </i>
            <span>
              <strong>{haptic.label}</strong>
              <small>{haptic.detail}</small>
            </span>
          </span>
        ))}
      </div>
    </div>
  );
}
