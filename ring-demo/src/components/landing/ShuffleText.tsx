import { useEffect, useMemo, useRef, useState } from "react";
import { useGSAP } from "@gsap/react";
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { SplitText as GSAPSplitText } from "gsap/SplitText";

gsap.registerPlugin(ScrollTrigger, GSAPSplitText, useGSAP);

type ShuffleDirection = "down" | "left" | "right" | "up";

interface ShuffleTextProps {
  duration?: number;
  ease?: string;
  reducedMotion?: boolean;
  rootMargin?: string;
  shuffleDirection?: ShuffleDirection;
  shuffleTimes?: number;
  stagger?: number;
  text: string;
  threshold?: number;
  triggerOnHover?: boolean;
}

/**
 * ReactBits Shuffle, adapted to render a span inside the landing-page heading.
 * Source behavior: https://reactbits.dev/text-animations/shuffle
 */
export function ShuffleText({
  duration = 0.35,
  ease = "power3.out",
  reducedMotion = false,
  rootMargin = "-100px",
  shuffleDirection = "right",
  shuffleTimes = 1,
  stagger = 0.03,
  text,
  threshold = 0.1,
  triggerOnHover = true,
}: ShuffleTextProps) {
  const ref = useRef<HTMLSpanElement>(null);
  const splitRef = useRef<GSAPSplitText | null>(null);
  const wrappersRef = useRef<HTMLSpanElement[]>([]);
  const timelineRef = useRef<gsap.core.Timeline | null>(null);
  const playingRef = useRef(false);
  const hoverHandlerRef = useRef<(() => void) | null>(null);
  const [fontsLoaded, setFontsLoaded] = useState(false);
  const [ready, setReady] = useState(reducedMotion);

  useEffect(() => {
    if (!("fonts" in document)) {
      setFontsLoaded(true);
      return;
    }

    if (document.fonts.status === "loaded") {
      setFontsLoaded(true);
      return;
    }

    let active = true;
    void document.fonts.ready.then(() => {
      if (active) setFontsLoaded(true);
    });
    return () => {
      active = false;
    };
  }, []);

  const scrollTriggerStart = useMemo(() => {
    const startPercent = (1 - threshold) * 100;
    const match = /^(-?\d+(?:\.\d+)?)(px|em|rem|%)?$/.exec(rootMargin);
    const value = match ? Number.parseFloat(match[1]) : 0;
    const unit = match?.[2] ?? "px";
    const offset =
      value === 0
        ? ""
        : value < 0
          ? `-=${Math.abs(value)}${unit}`
          : `+=${value}${unit}`;
    return `top ${startPercent}%${offset}`;
  }, [rootMargin, threshold]);

  useGSAP(
    () => {
      const element = ref.current;
      if (!element || !text || !fontsLoaded) return;

      const removeHover = () => {
        if (!hoverHandlerRef.current || !ref.current) return;
        ref.current.removeEventListener("mouseenter", hoverHandlerRef.current);
        hoverHandlerRef.current = null;
      };

      const teardown = () => {
        timelineRef.current?.kill();
        timelineRef.current = null;

        wrappersRef.current.forEach((wrapper) => {
          const original = wrapper.querySelector<HTMLElement>('[data-orig="1"]');
          if (original && wrapper.parentNode) {
            wrapper.parentNode.replaceChild(original, wrapper);
          }
        });
        wrappersRef.current = [];

        try {
          splitRef.current?.revert();
        } catch {
          // SplitText may already have been reverted by a React strict-mode pass.
        }
        splitRef.current = null;
        playingRef.current = false;
      };

      if (
        reducedMotion ||
        window.matchMedia?.("(prefers-reduced-motion: reduce)").matches
      ) {
        setReady(true);
        return () => {
          removeHover();
          teardown();
        };
      }

      const vertical =
        shuffleDirection === "up" || shuffleDirection === "down";

      const build = () => {
        teardown();
        splitRef.current = new GSAPSplitText(element, {
          charsClass: "shuffle-char",
          linesClass: "shuffle-line",
          reduceWhiteSpace: false,
          smartWrap: true,
          type: "chars",
          wordsClass: "shuffle-word",
        });

        const rolls = Math.max(1, Math.floor(shuffleTimes));
        const characters = (splitRef.current.chars ?? []) as HTMLElement[];

        characters.forEach((character) => {
          const parent = character.parentElement;
          if (!parent) return;

          const width = character.getBoundingClientRect().width;
          const height = character.getBoundingClientRect().height;
          if (!width) return;

          const wrapper = document.createElement("span");
          Object.assign(wrapper.style, {
            display: "inline-block",
            height: vertical ? `${height}px` : "auto",
            overflow: "hidden",
            verticalAlign: "bottom",
            width: `${width}px`,
          });

          const strip = document.createElement("span");
          Object.assign(strip.style, {
            display: "inline-block",
            whiteSpace: vertical ? "normal" : "nowrap",
            willChange: "transform",
          });

          parent.insertBefore(wrapper, character);
          wrapper.appendChild(strip);

          const styleCharacter = (node: HTMLElement) => {
            Object.assign(node.style, {
              display: vertical ? "block" : "inline-block",
              textAlign: "center",
              width: `${width}px`,
            });
          };

          const firstCopy = character.cloneNode(true) as HTMLElement;
          styleCharacter(firstCopy);
          character.dataset.orig = "1";
          styleCharacter(character);

          strip.appendChild(firstCopy);
          for (let index = 0; index < rolls; index += 1) {
            const copy = character.cloneNode(true) as HTMLElement;
            copy.removeAttribute("data-orig");
            styleCharacter(copy);
            strip.appendChild(copy);
          }
          strip.appendChild(character);

          const steps = rolls + 1;
          if (shuffleDirection === "right" || shuffleDirection === "down") {
            const first = strip.firstElementChild;
            const original = strip.lastElementChild;
            if (original) strip.insertBefore(original, strip.firstChild);
            if (first) strip.appendChild(first);
          }

          let startX = 0;
          let endX = 0;
          let startY = 0;
          let endY = 0;

          if (shuffleDirection === "right") startX = -steps * width;
          if (shuffleDirection === "left") endX = -steps * width;
          if (shuffleDirection === "down") startY = -steps * height;
          if (shuffleDirection === "up") endY = -steps * height;

          if (vertical) {
            gsap.set(strip, { force3D: true, x: 0, y: startY });
            strip.dataset.startY = String(startY);
            strip.dataset.finalY = String(endY);
          } else {
            gsap.set(strip, { force3D: true, x: startX, y: 0 });
            strip.dataset.startX = String(startX);
            strip.dataset.finalX = String(endX);
          }

          wrappersRef.current.push(wrapper);
        });
      };

      const cleanupToStill = () => {
        wrappersRef.current.forEach((wrapper) => {
          const strip = wrapper.firstElementChild as HTMLElement | null;
          const original = strip?.querySelector<HTMLElement>('[data-orig="1"]');
          if (!strip || !original) return;
          strip.replaceChildren(original);
          strip.style.transform = "none";
          strip.style.willChange = "auto";
        });
      };

      const play = () => {
        const strips = wrappersRef.current
          .map((wrapper) => wrapper.firstElementChild as HTMLElement | null)
          .filter((strip): strip is HTMLElement => Boolean(strip));
        if (!strips.length) {
          setReady(true);
          return;
        }

        playingRef.current = true;
        const timeline = gsap.timeline({
          onComplete: () => {
            playingRef.current = false;
            cleanupToStill();
            armHover();
          },
          smoothChildTiming: true,
        });

        const addTween = (targets: HTMLElement[], at: number) => {
          timeline.to(
            targets,
            {
              duration,
              ease,
              force3D: true,
              stagger,
              ...(vertical
                ? {
                    y: (_index: number, target: HTMLElement) =>
                      Number.parseFloat(target.dataset.finalY ?? "0"),
                  }
                : {
                    x: (_index: number, target: HTMLElement) =>
                      Number.parseFloat(target.dataset.finalX ?? "0"),
                  }),
            },
            at,
          );
        };

        const odd = strips.filter((_strip, index) => index % 2 === 1);
        const even = strips.filter((_strip, index) => index % 2 === 0);
        const oddDuration = duration + Math.max(0, odd.length - 1) * stagger;
        if (odd.length) addTween(odd, 0);
        if (even.length) addTween(even, odd.length ? oddDuration * 0.7 : 0);
        timelineRef.current = timeline;
      };

      const armHover = () => {
        if (!triggerOnHover || !ref.current) return;
        removeHover();
        const handler = () => {
          if (playingRef.current) return;
          build();
          play();
        };
        hoverHandlerRef.current = handler;
        ref.current.addEventListener("mouseenter", handler);
      };

      const create = () => {
        build();
        play();
        armHover();
        setReady(true);
      };

      const trigger = ScrollTrigger.create({
        onEnter: create,
        once: true,
        start: scrollTriggerStart,
        trigger: element,
      });

      return () => {
        trigger.kill();
        removeHover();
        teardown();
        setReady(false);
      };
    },
    {
      dependencies: [
        duration,
        ease,
        fontsLoaded,
        reducedMotion,
        scrollTriggerStart,
        shuffleDirection,
        shuffleTimes,
        stagger,
        text,
        triggerOnHover,
      ],
      scope: ref,
      revertOnUpdate: true,
    },
  );

  return (
    <span
      aria-label={text}
      className={`shuffle-text shuffle-parent${ready ? " is-ready" : ""}`}
      ref={ref}
    >
      {text}
    </span>
  );
}
