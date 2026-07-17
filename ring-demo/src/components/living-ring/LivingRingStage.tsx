import {
  Component,
  lazy,
  Suspense,
  useCallback,
  useEffect,
  useRef,
  useState,
  type ErrorInfo,
  type MutableRefObject,
  type ReactNode,
} from "react";

import {
  resolveRingJourney,
  resolveRingPosterStyle,
  type RingJourneyFrame,
} from "./journey-state";
import {
  resolveLandingRingFrame,
  resolveSenseEffectChapter,
} from "./landing-journey";
import type { LivingRingMode } from "./motion-state";
import { resolveConnectionTreatment } from "./product-treatment";
import { SenseRingEffects } from "./SenseRingEffects";

const LivingRingScene = lazy(() => import("./LivingRingScene"));

interface SceneBoundaryProps {
  children: ReactNode;
  onError: () => void;
}

class SceneBoundary extends Component<
  SceneBoundaryProps,
  { failed: boolean }
> {
  state = { failed: false };

  static getDerivedStateFromError() {
    return { failed: true };
  }

  componentDidCatch(_error: Error, _info: ErrorInfo) {
    this.props.onError();
  }

  render() {
    return this.state.failed ? null : this.props.children;
  }
}

function supportsWebGL() {
  if (typeof window === "undefined" || !window.WebGLRenderingContext) return false;
  try {
    const canvas = document.createElement("canvas");
    return Boolean(canvas.getContext("webgl") || canvas.getContext("experimental-webgl"));
  } catch {
    return false;
  }
}

interface LivingRingStageProps {
  connectionStatus: string;
  focusedMode: LivingRingMode;
  journeyRef: MutableRefObject<RingJourneyFrame>;
  reducedMotion: boolean;
}

export function LivingRingStage(props: LivingRingStageProps) {
  const stageRef = useRef<HTMLDivElement>(null);
  const [canRenderScene, setCanRenderScene] = useState(false);
  const [sceneReady, setSceneReady] = useState(false);
  const [sceneFailed, setSceneFailed] = useState(false);
  const mode = props.focusedMode ?? "neutral";
  const productMedium = "realtime-3d";
  const handleSceneReady = useCallback(() => setSceneReady(true), []);
  const handleSceneError = useCallback(() => setSceneFailed(true), []);
  const connectionTreatment = resolveConnectionTreatment(
    props.connectionStatus,
    props.reducedMotion,
  );

  useEffect(() => {
    if (!supportsWebGL()) return;
    const handle = globalThis.setTimeout(() => setCanRenderScene(true), 80);
    return () => globalThis.clearTimeout(handle);
  }, []);

  useEffect(() => {
    const stage = stageRef.current;
    if (!stage || props.reducedMotion) return;
    let animationFrame = 0;
    const handlePointer = (event: PointerEvent) => {
      cancelAnimationFrame(animationFrame);
      animationFrame = requestAnimationFrame(() => {
        const x = (event.clientX / window.innerWidth - 0.5) * 16;
        const y = (event.clientY / window.innerHeight - 0.5) * 10;
        stage.style.setProperty("--ring-pointer-x", `${x.toFixed(2)}px`);
        stage.style.setProperty("--ring-pointer-y", `${y.toFixed(2)}px`);
      });
    };
    window.addEventListener("pointermove", handlePointer, { passive: true });
    return () => {
      cancelAnimationFrame(animationFrame);
      window.removeEventListener("pointermove", handlePointer);
    };
  }, [props.reducedMotion]);

  useEffect(() => {
    const stage = stageRef.current;
    if (!stage) return;
    let animationFrame = 0;
    let handoffProgress = 0;
    let previousTime = performance.now();

    const updatePosterJourney = (time: number) => {
      const delta = Math.min(0.1, Math.max(0, (time - previousTime) / 1000));
      previousTime = time;
      const journey = props.journeyRef.current;
      const landingFrame = resolveLandingRingFrame(
        journey.progress,
        window.innerWidth <= 760,
        props.reducedMotion,
      );
      const handoffTarget =
        landingFrame.chapter === "modes" &&
        props.focusedMode &&
        !props.reducedMotion
          ? 1
          : 0;
      const damping = 1 - Math.exp(-delta * (handoffTarget ? 3.4 : 5.8));
      handoffProgress += (handoffTarget - handoffProgress) * damping;
      const modeHandoff = resolveRingJourney(
        1,
        window.innerWidth <= 760,
        props.focusedMode,
        props.reducedMotion,
        handoffProgress,
      );
      const pose =
        landingFrame.chapter === "modes" && props.focusedMode
          ? {
              ...landingFrame,
              position: modeHandoff.position,
              rotation: modeHandoff.rotation,
              scale: modeHandoff.scale,
              opacity: modeHandoff.opacity,
            }
          : landingFrame;
      const poster = resolveRingPosterStyle(
        pose,
        window.innerWidth,
        window.innerHeight,
      );

      stage.style.setProperty("--ring-poster-x", `${poster.translateX.toFixed(2)}px`);
      stage.style.setProperty("--ring-poster-y", `${poster.translateY.toFixed(2)}px`);
      stage.style.setProperty("--ring-poster-scale", poster.scale.toFixed(4));
      stage.style.setProperty(
        "--ring-poster-rotation",
        `${poster.rotationDegrees.toFixed(2)}deg`,
      );
      stage.style.setProperty("--ring-poster-opacity", poster.opacity.toFixed(4));
      stage.style.setProperty("--ring-state-color", landingFrame.color);
      stage.style.setProperty(
        "--ring-state-pulse",
        landingFrame.pulse.toFixed(3),
      );
      stage.dataset.ringChapter = landingFrame.chapter;
      stage.dataset.ringEffectChapter =
        journey.effectChapter ??
        resolveSenseEffectChapter(landingFrame.progress);
      animationFrame = requestAnimationFrame(updatePosterJourney);
    };

    animationFrame = requestAnimationFrame(updatePosterJourney);
    return () => cancelAnimationFrame(animationFrame);
  }, [props.focusedMode, props.journeyRef, props.reducedMotion]);

  return (
    <div
      aria-label="Eureka Ring product"
      className={`living-ring-stage${sceneReady ? " is-scene-ready" : ""}`}
      data-connection-status={props.connectionStatus}
      data-exterior-sweep={connectionTreatment.exteriorSweep > 0}
      data-focused-mode={mode}
      data-handoff-active={Boolean(
        props.focusedMode && !props.reducedMotion,
      )}
      data-product-medium={productMedium}
      data-testid="living-ring-stage"
      ref={stageRef}
      role="img"
    >
      {!sceneReady ? (
        <img
          alt=""
          aria-hidden="true"
          className="living-ring-poster"
          src="/ring/ring-connect.png"
        />
      ) : null}
      <SenseRingEffects />
      {canRenderScene && !sceneFailed ? (
        <SceneBoundary onError={handleSceneError}>
          <Suspense fallback={null}>
            <LivingRingScene {...props} onReady={handleSceneReady} />
          </Suspense>
        </SceneBoundary>
      ) : null}
    </div>
  );
}
