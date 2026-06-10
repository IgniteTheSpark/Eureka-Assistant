---
name: report-quiz
description: >
  Content skill (genre=quiz) of the Eureka report engine (§6.14). Turns pre-fetched study
  records into a multiple-choice quiz that tests what the user recorded. Distractors must be
  plausible (same domain), never throwaway. No tools — data injected; output annotated
  Markdown only. Rendered as an interactive scored quiz.
---

# Quiz 内容 skill

你把**已经查好的真实学习记录**出成一份**测验**考用户。数据已注入,你**不调任何工具**。

## 铁律(考他记的；干扰项要合理)

- 题目与**正确答案只来自注入的 `data`**(测他记的词/概念,正确答案=他记的释义)。**绝不**考他没记过的。
- **干扰项(错误项)= 测验质量的命门**:同类、似真、不送分。可由你生成,但要**合理**(同领域近义/易混),**禁**明显不相关的凑数项。
- 每题 **4 个选项、1 个正确**;`explain` 用他记的原话点明。
- 学习内容太少、出不了像样测验 → 如实说「内容还不够出一份测验」,**不硬凑**。

## 输入

```
title:  "<标题,如「本周词汇小测」>"
brief:  "<一句话诉求>"
data:   <JSON：真实学习记录>
```

## 内容骨架

1. `# <标题>` + 一行 headline(测什么、几题)。
2. **一个 `:::quiz` 块**:内放 JSON 数组,每题 `{q, options:[4 项], answer:<正确项下标,从 0>, explain?}`。**≤ ~10 题**。

## 注解 Markdown 语法(只用这些)

- 标准:`#` `##` 段落
- **测验:`:::quiz` 内放 JSON 数组 `:::`** —— 每题 `{"q":"…","options":["A","B","C","D"],"answer":0,"explain":"…"}`(`answer`=正确项下标)

> **写法铁律**:`:::` 块标记必须**单独成行、行首顶格、不加反引号**;JSON 数组直接放在块内,**不要**再套 ``` 代码栅栏。

## 只输出报告正文(硬规则)

**只输出报告 Markdown 本身**,不要解释/思考过程/元评论/括号备注。不写「我」「你提供的 data」。内容不足时,只用一句正文如实说明。

## 输出格式

```
---
genre: quiz
title: 本周词汇小测
---
# 本周词汇小测
这周记的词,挑 5 个考考你。

:::quiz
[
  {"q": "「ubiquitous」最接近哪个意思?", "options": ["无处不在的","稀有的","短暂的","昂贵的"], "answer": 0, "explain": "你记的:present everywhere"},
  {"q": "「resilient」指的是?", "options": ["脆弱的","有韧性、能快速恢复的","昂贵的","古老的"], "answer": 1}
]
:::
```

内容不够时,如实说明,不硬凑。
