import { useEffect, useRef, type PointerEvent } from "react";

import {
  MODE_SCENES,
  type ModeScene,
  type ModeSceneFocus,
} from "./mode-scene-state";

interface ModeSceneStageProps {
  focusedMode: ModeSceneFocus;
  onFocusMode: (mode: ModeSceneFocus) => void;
  reducedMotion: boolean;
}

interface ModeScenePanelProps {
  mode: ModeScene;
  onFocusMode: (mode: ModeSceneFocus) => void;
}

function ModeScenePanel({ mode, onFocusMode }: ModeScenePanelProps) {
  const scene = MODE_SCENES[mode];

  return (
    <article
      aria-label={scene.title}
      className={`mode-scene mode-scene-${mode}`}
      onBlur={() => onFocusMode(null)}
      onFocus={() => onFocusMode(mode)}
      onPointerEnter={() => onFocusMode(mode)}
      onPointerLeave={() => onFocusMode(null)}
      onTouchStart={() => onFocusMode(mode)}
      tabIndex={0}
    >
      <img
        alt={scene.alt}
        className="mode-scene-image"
        decoding="async"
        loading="lazy"
        src={scene.image}
      />
      <span aria-hidden="true" className="mode-scene-shade" />

      <span className="mode-scene-index">{scene.label}</span>

      <span className="mode-scene-command">
        <span aria-hidden="true" className="mode-scene-waveform">
          <i />
          <i />
          <i />
          <i />
          <i />
        </span>
        <span>{scene.command}</span>
      </span>

      <span className="mode-scene-speaking-hint">
        自然表达，安静捕捉。
      </span>

      <span className="mode-scene-copy">
        <strong>{scene.title}</strong>
        <span>{scene.description}</span>
      </span>

    </article>
  );
}

export function ModeSceneStage({
  focusedMode,
  onFocusMode,
  reducedMotion,
}: ModeSceneStageProps) {
  const state = focusedMode ?? "neutral";
  const pointerModeRef = useRef<ModeSceneFocus>(focusedMode);

  useEffect(() => {
    pointerModeRef.current = focusedMode;
  }, [focusedMode]);

  const handlePointerMove = (event: PointerEvent<HTMLDivElement>) => {
    const bounds = event.currentTarget.getBoundingClientRect();
    if (bounds.width <= 0) return;
    const progress = (event.clientX - bounds.left) / bounds.width;
    const nextMode: ModeSceneFocus =
      progress < 0.44 ? "flash" : progress > 0.56 ? "vibe" : null;
    if (nextMode === pointerModeRef.current) return;
    pointerModeRef.current = nextMode;
    onFocusMode(nextMode);
  };

  return (
    <div
      aria-label="一枚戒指，两种智能体验"
      className={`mode-scene-stage${focusedMode ? ` is-${focusedMode}` : ""}`}
      data-focused-mode={state}
      data-reduced-motion={reducedMotion}
      data-testid="mode-scene-stage"
      onPointerLeave={() => onFocusMode(null)}
      onPointerMove={handlePointerMove}
      role="group"
    >
      <ModeScenePanel mode="flash" onFocusMode={onFocusMode} />

      <div aria-hidden="true" className="mode-runway">
        <span>持续在线</span>
        <span>选择一种体验</span>
      </div>

      <ModeScenePanel mode="vibe" onFocusMode={onFocusMode} />
    </div>
  );
}
