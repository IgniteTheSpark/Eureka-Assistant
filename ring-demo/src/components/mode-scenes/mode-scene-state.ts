export type ModeScene = "flash" | "vibe";
export type ModeSceneFocus = ModeScene | null;

export interface RingHandoffTarget {
  position: [number, number, number];
  rotation: [number, number, number];
  scale: number;
}

interface ModeSceneDefinition {
  alt: string;
  command: string;
  description: string;
  handoff: {
    desktop: RingHandoffTarget;
  };
  image: string;
  label: string;
  title: string;
}

export const MODE_SCENES: Record<ModeScene, ModeSceneDefinition> = {
  flash: {
    alt: "Flash Mode：驾驶途中用戒指捕捉闪念",
    command: "帮我安排 Kevin 下午四点到五点的会议。",
    description:
      "说出一个想法，让 Eureka 理解它，并把它变成可以继续使用的内容。",
    handoff: {
      desktop: {
        position: [-1.02, 0.29, 0],
        rotation: [-0.5, -0.36, -0.12],
        scale: 0.04,
      },
    },
    image: "/scenes/flash-driving-clean.webp",
    label: "01 · 捕捉",
    title: "Flash Mode｜闪念",
  },
  vibe: {
    alt: "Vibe Mode：在 Codex 前用戒指发出指令",
    command: "帮我执行这个计划，并把代码推送到 GitHub。",
    description:
      "对正在使用的工具直接说话，让声音成为下一种电脑交互方式。",
    handoff: {
      desktop: {
        position: [0.5, 0.17, 0],
        rotation: [-0.54, 0.32, 0.12],
        scale: 0.04,
      },
    },
    image: "/scenes/vibe-office-clean.webp",
    label: "02 · 操控",
    title: "Vibe Mode｜随声操控",
  },
};

export type RingTarget = ModeScene | "center";

export interface ModeSceneLayout {
  columns: [number, number, number];
  handoffOpacity: number;
  ringTarget: RingTarget;
  target: RingHandoffTarget | null;
}

export function resolveModeSceneLayout(
  focus: ModeSceneFocus,
  compact: boolean,
  reducedMotion: boolean,
): ModeSceneLayout {
  const ringTarget: RingTarget =
    compact || reducedMotion ? "center" : (focus ?? "center");
  const columns: [number, number, number] =
    focus === "flash"
      ? [59, 12, 29]
      : focus === "vibe"
        ? [29, 12, 59]
        : [41, 18, 41];

  return {
    columns,
    handoffOpacity: ringTarget === "center" ? 1 : 0,
    ringTarget,
    target:
      ringTarget === "center"
        ? null
        : MODE_SCENES[ringTarget].handoff.desktop,
  };
}
