type AssetRecord = Record<string, unknown>;

const CARD_LABELS: Record<string, string> = {
  todo: "待办",
  idea: "灵感",
  event: "日程",
  contact: "联系人",
  expense: "记账",
  note: "随记",
  notes: "随记",
  misc: "随记",
};

const SECRET_FIELD =
  /(authorization|password|passwd|secret|token|api_?key|cookie|credential)/i;

function asRecord(value: unknown): AssetRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as AssetRecord)
    : {};
}

function text(value: unknown) {
  if (typeof value === "string" || typeof value === "number") {
    return String(value).trim();
  }
  return "";
}

function printable(value: unknown): string {
  if (Array.isArray(value)) {
    return value.map(printable).filter(Boolean).join(" · ");
  }
  if (typeof value === "object" && value !== null) {
    return Object.entries(value)
      .filter(([key]) => !SECRET_FIELD.test(key))
      .map(([key, nested]) => `${key}: ${printable(nested)}`)
      .filter((entry) => !entry.endsWith(": "))
      .join(" · ");
  }
  if (typeof value === "boolean") return value ? "是" : "否";
  return text(value);
}

function safePayload(card: AssetRecord) {
  const payload = asRecord(card.payload);
  return Object.fromEntries(
    Object.entries(payload).filter(([key]) => !SECRET_FIELD.test(key)),
  );
}

function firstText(record: AssetRecord, keys: string[]) {
  for (const key of keys) {
    const value = text(record[key]);
    if (value) return value;
  }
  return "";
}

function metaValues(card: AssetRecord, payload: AssetRecord, cardType: string) {
  const prebuilt = Array.isArray(card.meta_fields)
    ? card.meta_fields
        .map(asRecord)
        .map((field) => text(field.value))
        .filter(Boolean)
    : [];
  if (prebuilt.length) return prebuilt;

  const source = { ...payload, ...card };
  const fields: Record<string, string[]> = {
    todo: ["due_date", "content"],
    idea: ["tags"],
    event: ["start_at", "end_at", "location", "attendees"],
    contact: ["company", "title", "phone", "email"],
    expense: ["amount", "category", "merchant", "date"],
    note: ["tags"],
    notes: ["tags"],
    misc: ["tags"],
  };
  return (fields[cardType] ?? [])
    .map((field) => {
      const value = printable(source[field]);
      if (!value) return "";
      return cardType === "expense" && field === "amount" && !value.startsWith("¥")
        ? `¥${value}`
        : value;
    })
    .filter(Boolean);
}

export function AssetCard({
  card: suppliedCard,
  index = 0,
}: {
  card: AssetRecord;
  index?: number;
}) {
  const nestedCard = asRecord(suppliedCard.card);
  const card = Object.keys(nestedCard).length ? nestedCard : suppliedCard;
  const payload = safePayload(card);
  const cardType =
    firstText(card, ["card_type", "user_skill_name", "skill_name", "type"]) ||
    "asset";
  const knownLabel = CARD_LABELS[cardType];
  const displayName =
    firstText(card, ["display_name"]) || knownLabel || "资产";
  const source = { ...payload, ...card };
  const primaryKeys: Record<string, string[]> = {
    todo: ["title", "content"],
    idea: ["title", "content"],
    event: ["title", "content"],
    contact: ["name", "title", "content"],
    expense: ["title", "item", "merchant", "content"],
    note: ["title", "content"],
    notes: ["title", "content"],
    misc: ["title", "content"],
  };
  const primary =
    firstText(source, primaryKeys[cardType] ?? ["title", "content", "name"]) ||
    displayName;
  const subtitle = firstText(card, ["subtitle"]);
  const knownMeta = metaValues(card, payload, cardType).filter(
    (value) => value !== primary && value !== subtitle,
  );
  const genericDetails = knownLabel
    ? []
    : Object.entries(payload)
        .filter(
          ([key]) =>
            !["title", "content", "name", "display_name"].includes(key),
        )
        .map(([key, value]) => `${key}: ${printable(value)}`)
        .filter((value) => !value.endsWith(": "));
  const details = knownMeta.length ? knownMeta : genericDetails;
  const stagger = Math.min(Math.max(index, 0), 5) + 1;

  return (
    <article
      aria-label={`${displayName} card`}
      className={`asset-card asset-card-${cardType} card-stagger-${stagger}`}
    >
      <div className="asset-card-icon" aria-hidden="true">
        {text(card.icon) || (cardType === "todo" ? "□" : "•")}
      </div>
      <div className="asset-card-body">
        {primary !== displayName ? (
          <p className="asset-card-kind">{displayName}</p>
        ) : null}
        <h3>{primary}</h3>
        {subtitle ? <p className="asset-card-subtitle">{subtitle}</p> : null}
        {details.length ? (
          <ul className="asset-card-meta">
            {details.map((value, detailIndex) => (
              <li key={`${value}-${detailIndex}`}>{value}</li>
            ))}
          </ul>
        ) : null}
      </div>
    </article>
  );
}
