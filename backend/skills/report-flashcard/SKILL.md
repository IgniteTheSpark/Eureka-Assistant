---
name: report-flashcard
description: >
  Content skill (genre=flashcard) of the Eureka report engine (§6.14). Turns pre-fetched
  study records (vocabulary / reading notes / study notes) into a flashcard set — each card
  front::back, grounded strictly in what the user recorded. No tools — data injected; output
  annotated Markdown only. Rendered as an interactive flip deck.
---

# Flashcard 内容 skill

你把**已经查好的真实学习记录**(单词/读书笔记/学习笔记)做成一套**记忆卡**。数据已注入,你**不调任何工具**。

## 铁律(只做他记过的)

- 卡片**正反面只来自注入的 `data`** —— 正面=他记的词/概念,背面=**他记的释义/笔记**。**绝不发明**他没记过的词或意思。
- 一条记录 → 一张卡(一条里有多个清晰知识点可拆几张)。背面**忠实**用他的话,可轻规整、不改意思。
- 没有可做成卡的学习内容 → 如实说「这些记录还不适合做记忆卡」,**不硬凑**。

## 输入

```
title:  "<标题,如「本周新词」>"
brief:  "<一句话诉求>"
data:   <JSON：真实学习记录(单词/笔记),含 标题/正文/时间>
```

## 内容骨架

1. `# <标题>` + 一行 headline(这套卡覆盖什么、几张)。
2. **一个 `:::flashcards` 块**:每行 `正面 :: 背面`。**≤ ~20 张**(多了截断,正文写「等 N 张」)。

## 注解 Markdown 语法(只用这些)

- 标准:`#` `##` 段落
- **记忆卡:`:::flashcards` 内每行 `正面 :: 背面` `:::`**(正面=考点,背面=答案/释义)

> **写法铁律**:`:::` 块标记必须**单独成行、行首顶格、不加反引号**;写成 `` `:::flashcards` `` 会让整块失效。

## 只输出报告正文(硬规则)

**只输出报告 Markdown 本身**,不要解释/思考过程/元评论/括号备注。不写「我」「你提供的 data」。内容不足时,只用一句正文如实说明,不解释为何这么写。

## 输出格式

```
---
genre: flashcard
title: 本周新词
---
# 本周新词
这周记的 8 个词,翻牌过一遍。

:::flashcards
ubiquitous :: 无处不在的(present everywhere)
resilient :: 有韧性、能快速恢复的
candid :: 坦率、直言的
:::
```

没有可做成卡的学习内容时,如实说明,不硬凑。
