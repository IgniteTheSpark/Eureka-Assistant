/// §9 球球 — cosmetic metadata for the wardrobe UI. Keys mirror the design engine
/// (`assets/js/mascot.js`) and the backend (`core/pet.py`); labels/swatches are
/// the Flutter-side presentation of those keys. The full pet is always rendered
/// live by the engine (PetView) — these are just the picker chips.
library;

import 'package:flutter/material.dart';

/// Genome slots, in wardrobe display order. `emblem_color` uses the underscore
/// form the equip endpoint expects.
const kSkins = ['aurora', 'grape', 'coral', 'lime', 'ocean', 'bubble', 'ember', 'mint', 'sky', 'gold'];
const kEmblems = ['star', 'plus', 'heart', 'drop', 'ring', 'bolt', 'leaf'];
const kEmblemColors = ['gold', 'white', 'cyan', 'magenta', 'sky', 'lime', 'coral'];
const kHeads = ['safari', 'beanie', 'horns', 'antenna', 'sprout', 'crown'];
const kItems = ['laptop', 'book', 'coin', 'pen', 'umbrella', 'magnify', 'flower', 'dumbbell', 'leaf'];
const kCarriers = ['cloud', 'disc', 'pad', 'board', 'ring'];
const kAuras = ['soft', 'gold', 'cyan', 'magenta', 'azure', 'ember', 'verdant', 'frost', 'rainbow'];

/// §9 徽记 = 颜色烘焙进组件的命名件(不再有独立选色)。每个 = 形 × 色 × 名 × 稀有度,
/// 镜像 reka-system.js EMBLEM_OWNED。一个形(如 bolt)可有多个配色变体(赤焰/蓝电)。
class EmblemComponent {
  final String emblem; // shape key (star/plus/heart/drop/bolt/leaf/ring)
  final String color; // baked emblem_color
  final String name;
  final String tier;
  const EmblemComponent(this.emblem, this.color, this.name, this.tier);
  String get id => '$emblem@$color';
}

const kEmblemComponents = <EmblemComponent>[
  EmblemComponent('star', 'gold', '金星', 'rare'),
  EmblemComponent('plus', 'white', '银十字', 'normal'),
  EmblemComponent('heart', 'magenta', '霓粉之心', 'rare'),
  EmblemComponent('drop', 'sky', '天蓝水滴', 'rare'),
  EmblemComponent('bolt', 'coral', '赤焰闪电', 'epic'),
  EmblemComponent('bolt', 'cyan', '蓝电闪电', 'epic'),
  EmblemComponent('leaf', 'lime', '青翠之叶', 'rare'),
  EmblemComponent('ring', 'cyan', '青环', 'epic'),
];

/// The component matching the pet's current emblem + color (falls back to first).
EmblemComponent emblemComponentOf(String emblem, String color) {
  for (final c in kEmblemComponents) {
    if (c.emblem == emblem && c.color == color) return c;
  }
  // emblem matched but a different baked color → first variant of that shape.
  for (final c in kEmblemComponents) {
    if (c.emblem == emblem) return c;
  }
  return kEmblemComponents.first;
}

/// Body colorway — Chinese names from mascot.js + a representative swatch
/// (ramp[3], the saturated mid).
const skinLabel = {
  'aurora': '极光', 'grape': '葡萄', 'coral': '珊瑚', 'lime': '青柠', 'ocean': '海洋',
  'bubble': '泡泡糖', 'ember': '余烬', 'mint': '薄荷', 'sky': '晴空', 'gold': '蜜金',
};
const skinSwatch = {
  'aurora': Color(0xFF46B6E8), 'grape': Color(0xFF9A5FE8), 'coral': Color(0xFFF77662),
  'lime': Color(0xFF86D046), 'ocean': Color(0xFF46A8EE), 'bubble': Color(0xFFE85FBD),
  'ember': Color(0xFFF7864E), 'mint': Color(0xFF46E0B0), 'sky': Color(0xFF6F9EFF),
  'gold': Color(0xFFF7B63F),
};

const emblemLabel = {
  'star': '星芒', 'plus': '十字', 'heart': '爱心', 'drop': '水滴',
  'ring': '圆环', 'bolt': '闪电', 'leaf': '叶子', 'none': '无',
};
const emblemEmoji = {
  'star': '⭐', 'plus': '➕', 'heart': '❤️', 'drop': '💧',
  'ring': '💍', 'bolt': '⚡', 'leaf': '🍀', 'none': '⊘',
};

const emblemColorLabel = {
  'gold': '金', 'white': '白', 'cyan': '青', 'magenta': '粉', 'sky': '蓝', 'lime': '绿', 'coral': '橙',
};
const emblemColorSwatch = {
  'gold': Color(0xFFFFD24A), 'white': Color(0xFFFFFFFF), 'cyan': Color(0xFF6FF0E0),
  'magenta': Color(0xFFFF8FD0), 'sky': Color(0xFF7AB8FF), 'lime': Color(0xFFBFF060),
  'coral': Color(0xFFFF9A6E),
};

const headLabel = {
  'safari': '探险帽', 'beanie': '毛线帽', 'horns': '小角', 'antenna': '天线',
  'sprout': '嫩芽', 'crown': '皇冠', 'none': '不戴',
};
const headEmoji = {
  'safari': '🎩', 'beanie': '🧢', 'horns': '😈', 'antenna': '📡',
  'sprout': '🌱', 'crown': '👑', 'none': '⊘',
};

const itemLabel = {
  'laptop': '笔电', 'book': '书', 'coin': '金币', 'pen': '钢笔', 'umbrella': '雨伞',
  'magnify': '放大镜', 'flower': '花', 'dumbbell': '哑铃', 'leaf': '树叶', 'none': '空手',
};
const itemEmoji = {
  'laptop': '💻', 'book': '📖', 'coin': '🪙', 'pen': '🖊️', 'umbrella': '☂️',
  'magnify': '🔍', 'flower': '🌸', 'dumbbell': '🏋️', 'leaf': '🍃', 'none': '⊘',
};

const carrierLabel = {
  'none': '无', 'cloud': '云朵', 'disc': '飞盘', 'pad': '荷叶', 'board': '滑板', 'ring': '光环座',
};
const carrierEmoji = {
  'none': '⊘', 'cloud': '☁️', 'disc': '🛸', 'pad': '🍃', 'board': '🛹', 'ring': '🪐',
};

const auraLabel = {
  'none': '无光', 'soft': '柔光', 'gold': '金辉', 'cyan': '青辉', 'magenta': '霓彩',
  'azure': '蔚蓝', 'ember': '炽火', 'verdant': '翠绿', 'frost': '霜白', 'rainbow': '虹彩',
};
const auraEmoji = {
  'none': '⊘', 'soft': '🌫️', 'gold': '🌟', 'cyan': '💠', 'magenta': '🌈', 'azure': '🔷',
  'ember': '🔥', 'verdant': '🌿', 'frost': '❄️', 'rainbow': '🌈',
};
// aura glow colors — mirror mascot.js AURAS. The engine paints the aura as a CSS
// drop-shadow on the canvas element, which `toDataURL` does NOT capture; so the
// static preview cells re-create the glow Flutter-side from these.
const auraGlow = {
  'none': <Color>[],
  'soft': <Color>[Color(0xFF56D6C6)],
  'gold': <Color>[Color(0xFFFFD24A), Color(0xFFFFB000)],
  'cyan': <Color>[Color(0xFF6FF0E0), Color(0xFF3AC49A)],
  'magenta': <Color>[Color(0xFFFF8FD0), Color(0xFFE85FBD)],
  'azure': <Color>[Color(0xFF7AB8FF), Color(0xFF3A82E0)],
  'ember': <Color>[Color(0xFFFFB072), Color(0xFFFF6A3D)],
  'verdant': <Color>[Color(0xFFBDF07A), Color(0xFF5DB84A)],
  'frost': <Color>[Color(0xFFCFEAFF), Color(0xFF8FD0FF)],
  'rainbow': <Color>[Color(0xFFFF8FD0), Color(0xFF7AB8FF), Color(0xFF9ECE6A)],
};

/// §9.2 v4 统一光晕色 — the representative glow color(s) for a pet's skin+aura,
/// mirroring `Mascot.glowColors()`. Every surface REKA opens (menu / bubble /
/// popup) tints to this so they stay consistent and follow the equipped aura.
List<Color> rekaGlow(String skin, String aura) {
  if (aura == 'soft' || aura == 'none') {
    return [skinSwatch[skin] ?? const Color(0xFF6F9EFF)];
  }
  final g = auraGlow[aura];
  return (g == null || g.isEmpty) ? [skinSwatch[skin] ?? const Color(0xFF6F9EFF)] : g;
}

const slotLabel = {
  'skin': '体色', 'emblem': '徽记', 'emblem_color': '徽色',
  'head': '头饰', 'leftItem': '左手', 'rightItem': '右手', 'item': '道具',
  'carrier': '承载', 'aura': '光环',
};

/// A reward cosmetic's display name / fallback glyph by (slot, key) — used by the
/// milestone cards (which come from the backend as slot+key, §9.5).
String rewardLabel(String slot, String key) {
  switch (slot) {
    case 'skin': return skinLabel[key] ?? key;
    case 'emblem': return emblemLabel[key] ?? key;
    case 'head': return headLabel[key] ?? key;
    case 'leftItem':
    case 'rightItem':
    case 'item': return itemLabel[key] ?? key;
    case 'carrier': return carrierLabel[key] ?? key;
    case 'aura': return auraLabel[key] ?? key;
    default: return key;
  }
}

String rewardGlyph(String slot, String key) {
  switch (slot) {
    case 'emblem': return emblemEmoji[key] ?? '🎁';
    case 'head': return headEmoji[key] ?? '🎁';
    case 'leftItem':
    case 'rightItem':
    case 'item': return itemEmoji[key] ?? '🎁';
    case 'carrier': return carrierEmoji[key] ?? '🎁';
    case 'aura': return auraEmoji[key] ?? '🌈';
    case 'skin': return '🎨';
    default: return '🎁';
  }
}

/// §9.5 rarity tiers — must mirror core/pet.py TIERS. Color drives the wardrobe
/// card bg/border + corner tag.
class RekaTier {
  final String label;
  final Color color;
  const RekaTier(this.label, this.color);
}

const kTiers = {
  'normal': RekaTier('普通', Color(0xFF9AA6B8)),
  'rare': RekaTier('稀有', Color(0xFF6F9EFF)),
  'epic': RekaTier('史诗', Color(0xFFBB9AF7)),
  'legendary': RekaTier('传说', Color(0xFFF7C948)),
};

/// Per-cosmetic rarity — mirrors core/pet.py RARITY. Keyed by the engine table
/// name (leftItem/rightItem share 'item').
const _rarity = {
  'skin': {'aurora': 'rare', 'grape': 'normal', 'coral': 'normal', 'lime': 'normal', 'ocean': 'normal', 'bubble': 'epic', 'ember': 'rare', 'mint': 'rare', 'sky': 'normal', 'gold': 'legendary'},
  'emblem': {'star': 'normal', 'plus': 'normal', 'heart': 'rare', 'drop': 'rare', 'ring': 'epic', 'bolt': 'epic', 'leaf': 'rare', 'none': 'normal'},
  'emblem_color': {'gold': 'rare', 'white': 'normal', 'cyan': 'rare', 'magenta': 'epic', 'sky': 'normal', 'lime': 'rare', 'coral': 'rare'},
  'head': {'none': 'normal', 'safari': 'rare', 'beanie': 'normal', 'horns': 'rare', 'antenna': 'epic', 'sprout': 'rare', 'crown': 'legendary'},
  'item': {'none': 'normal', 'laptop': 'rare', 'book': 'normal', 'coin': 'rare', 'pen': 'normal', 'umbrella': 'epic', 'magnify': 'rare', 'flower': 'rare', 'dumbbell': 'epic', 'leaf': 'normal'},
  'carrier': {'none': 'normal', 'cloud': 'rare', 'disc': 'epic', 'pad': 'rare', 'board': 'epic', 'ring': 'legendary'},
  'aura': {'none': 'normal', 'soft': 'normal', 'gold': 'rare', 'cyan': 'rare', 'magenta': 'epic', 'azure': 'rare', 'ember': 'epic', 'verdant': 'rare', 'frost': 'rare', 'rainbow': 'legendary'},
};

String tierOf(String slot, String key) {
  final t = (slot == 'leftItem' || slot == 'rightItem') ? 'item' : slot;
  return _rarity[t]?[key] ?? 'normal';
}

/// Lock-condition hints — mirror core/pet.py LOCK_RULES. A cosmetic with a hint
/// that's not yet owned shows 🔒 + this label until the milestone is met.
const _lockHint = {
  'skin': {'gold': '点亮 8 个领域', 'bubble': '连续记录 14 天'},
  'head': {'crown': '累计捕捉 100 条'},
  'carrier': {'ring': '点亮 8 个领域'},
  'aura': {'rainbow': '集齐 8 种身色'},
};

String? lockHint(String slot, String key) => _lockHint[slot]?[key];

/// Human label for a dropped/owned cosmetic (slot uses the drop-pool keys:
/// skin | emblem | head | item). Used by the drop toast.
String cosmeticLabel(String slot, String key) {
  switch (slot) {
    case 'skin':
      return skinLabel[key] ?? key;
    case 'emblem':
      return emblemLabel[key] ?? key;
    case 'head':
      return headLabel[key] ?? key;
    case 'item':
      return itemLabel[key] ?? key;
    case 'carrier':
      return carrierLabel[key] ?? key;
    case 'aura':
      return auraLabel[key] ?? key;
    default:
      return key;
  }
}

/// Emoji glyph for a dropped/owned cosmetic (drop-pool slots).
String cosmeticEmoji(String slot, String key) {
  switch (slot) {
    case 'skin':
      return '🎨';
    case 'emblem':
      return emblemEmoji[key] ?? '✨';
    case 'head':
      return headEmoji[key] ?? '🎩';
    case 'item':
      return itemEmoji[key] ?? '🎁';
    case 'carrier':
      return carrierEmoji[key] ?? '☁️';
    case 'aura':
      return auraEmoji[key] ?? '🌈';
    default:
      return '🎁';
  }
}
