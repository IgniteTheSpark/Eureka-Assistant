export interface LandingExample {
  input: string;
  output: string;
}

export interface LandingSense {
  description: string;
  id: "speak" | "touch" | "feel";
  metric: string;
  title: string;
}

export const LANDING_CONTENT = {
  hero: {
    title: "智能 · 触手可及",
    description:
      "一枚连接个人智能的戒指。捕捉转瞬即逝的想法，也让声音成为操作电脑的方式。",
  },
  modes: {
    title: "一枚戒指 · 两种智能体验",
    description:
      "让 Eureka 理解一个想法，或让声音直接进入你正在使用的工具。",
    flash: {
      title: "Flash Mode｜闪念",
      description:
        "说出一个想法，让 Eureka 理解它，并把它变成可以继续使用的内容。",
    },
    vibe: {
      title: "Vibe Mode｜随声操控",
      description:
        "对正在使用的工具直接说话，让声音成为下一种电脑交互方式。",
    },
  },
  flash: {
    title: "录音只是开始。",
    description:
      "Eureka 会理解你真正想完成的事情，调用合适的能力，再把一句自然表达变成下一步可以继续使用的资产。",
    pipeline: ["一句自然表达", "理解意图", "调用 Skills", "形成资产"],
    examples: [
      { input: "提醒我明天下午联系 Kevin", output: "待办与联系人" },
      { input: "记一下这个产品方向", output: "结构化随记" },
      { input: "安排周五四点的会议", output: "日程" },
      { input: "把刚才的想法整理成项目计划", output: "文档资产" },
    ] satisfies LandingExample[],
  },
  vibe: {
    title: "不需要切换到另一块屏幕。",
    description:
      "对着戒指说话，指令直接进入你正在工作的地方。Eureka 负责连接语音、戒指动作与当前桌面应用。",
    targets: [
      {
        name: "Codex",
        description: "描述需求、执行计划、修改项目。",
      },
      {
        name: "钉钉",
        description: "输入内容、导航界面、完成日常沟通。",
      },
    ],
    supportNote:
      "以上为常见办公与效率软件示例，连接范围仍在持续扩展。",
  },
  system: {
    title: "不是把助手缩小 · 是让智能始终在手边",
    description:
      "Eureka Ring 通过电脑或手机连接个人智能，让语音、手势和触觉反馈进入用户正在使用的应用与设备。",
    nodes: [
      {
        id: "ring",
        label: "Eureka Ring",
        detail: "收下语音与手势",
        signal: "说 · 触",
      },
      {
        id: "device",
        label: "电脑或手机",
        detail: "建立连接并转交上下文",
        signal: "连接 · 上下文",
      },
      {
        id: "intelligence",
        label: "个人智能",
        detail: "理解意图 · 调用能力",
        signal: "理解 · 调用",
      },
      {
        id: "output",
        label: "应用、AI 与资产",
        detail: "执行动作 · 沉淀结果",
        signal: "执行 · 沉淀",
      },
      {
        id: "feedback",
        label: "触觉反馈",
        detail: "把状态送回手指",
        signal: "状态 · 回响",
      },
    ],
  },
  senses: [
    {
      id: "speak",
      title: "说",
      metric: "自然语音输入",
      description: "想法或指令，直接说出来。",
    },
    {
      id: "touch",
      title: "触",
      metric: "7 种手势交互",
      description: "同一个动作，在不同设备、应用和场景中承担不同含义。",
    },
    {
      id: "feel",
      title: "感",
      metric: "3 种震动反馈",
      description: "不用查看屏幕，也能感知状态与结果。",
    },
  ] satisfies LandingSense[],
  community: {
    title: "成为第一批使用 Eureka Ring 的人。",
    description:
      "产品目前处于内测阶段。扫码加入体验群，获取演示、内测资格和后续产品更新。",
    action: "扫码加入内测群",
    note: "内测名额及开放时间以群内通知为准",
  },
} as const;
