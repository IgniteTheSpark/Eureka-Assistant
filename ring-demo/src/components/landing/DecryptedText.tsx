import { useEffect, useRef, useState } from "react";

const GLYPHS = "·◇○△□＋×";

interface DecryptedTextProps {
  reducedMotion?: boolean;
  text: string;
}

function decryptFrame(text: string, progress: number) {
  const resolved = Math.floor(text.length * progress);

  return Array.from(text, (character, index) => {
    if (index < resolved || /[\s，。·、]/u.test(character)) return character;
    return GLYPHS[(index * 3 + resolved) % GLYPHS.length];
  }).join("");
}

export function DecryptedText({ reducedMotion = false, text }: DecryptedTextProps) {
  const rootRef = useRef<HTMLSpanElement>(null);
  const [displayText, setDisplayText] = useState(text);
  const [state, setState] = useState<"idle" | "running" | "complete">(
    reducedMotion ? "complete" : "idle",
  );

  useEffect(() => {
    setDisplayText(text);
    setState(reducedMotion ? "complete" : "idle");

    if (reducedMotion) return;
    if (typeof IntersectionObserver === "undefined") {
      setState("complete");
      return;
    }

    let frame = 0;
    let startedAt = 0;
    const duration = 760;
    const root = rootRef.current;
    if (!root) return;

    const animate = (time: number) => {
      if (!startedAt) startedAt = time;
      const progress = Math.min(1, (time - startedAt) / duration);
      setDisplayText(decryptFrame(text, progress));
      if (progress < 1) {
        frame = requestAnimationFrame(animate);
      } else {
        setDisplayText(text);
        setState("complete");
      }
    };

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (!entry?.isIntersecting) return;
        setDisplayText(decryptFrame(text, 0));
        setState("running");
        frame = requestAnimationFrame(animate);
        observer.disconnect();
      },
      {
        rootMargin: "0px 0px -50% 0px",
        threshold: 0,
      },
    );

    observer.observe(root);
    return () => {
      observer.disconnect();
      cancelAnimationFrame(frame);
    };
  }, [reducedMotion, text]);

  return (
    <span
      aria-label={text}
      className="decrypted-text"
      data-decrypted-state={state}
      data-decrypted-visible={state === "idle" ? "false" : "true"}
      ref={rootRef}
    >
      <span aria-hidden="true" className="decrypted-text-visual">
        {displayText}
      </span>
    </span>
  );
}
