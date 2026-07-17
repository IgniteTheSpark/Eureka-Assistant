import {
  forwardRef,
  type ReactNode,
  useImperativeHandle,
  useLayoutEffect,
  useRef,
} from "react";
import Lenis from "lenis";

import "./ScrollStack.css";

export interface ScrollStackHandle {
  scrollToStart(): void;
}

export interface ScrollStackProps {
  children: ReactNode;
  className?: string;
  itemDistance?: number;
  itemScale?: number;
  itemStackDistance?: number;
  stackPosition?: string;
  scaleEndPosition?: string;
  baseScale?: number;
  scaleDuration?: number;
  rotationAmount?: number;
  blurAmount?: number;
  useWindowScroll?: boolean;
  onStackComplete?: () => void;
}

export function ScrollStackItem({
  children,
  itemClassName = "",
}: {
  children: ReactNode;
  itemClassName?: string;
}) {
  return (
    <div className={`scroll-stack-card ${itemClassName}`.trim()}>{children}</div>
  );
}

function clamp(value: number, min = 0, max = 1) {
  return Math.min(max, Math.max(min, value));
}

function positionToPixels(position: string, viewportSize: number) {
  const numeric = Number.parseFloat(position);
  return position.trim().endsWith("%")
    ? viewportSize * (Number.isFinite(numeric) ? numeric / 100 : 0)
    : Number.isFinite(numeric)
      ? numeric
      : 0;
}

export const ScrollStack = forwardRef<ScrollStackHandle, ScrollStackProps>(
  function ScrollStack(
    {
      children,
      className = "",
      itemDistance = 100,
      itemScale = 0.03,
      itemStackDistance = 30,
      stackPosition = "20%",
      scaleEndPosition = "10%",
      baseScale = 0.85,
      scaleDuration = 0.5,
      rotationAmount = 0,
      blurAmount = 0,
      useWindowScroll = false,
      onStackComplete,
    },
    forwardedRef,
  ) {
    const scrollerRef = useRef<HTMLDivElement>(null);
    const lenisRef = useRef<Lenis | null>(null);

    useImperativeHandle(
      forwardedRef,
      () => ({
        scrollToStart() {
          if (lenisRef.current) {
            lenisRef.current.scrollTo(0, { immediate: false });
          } else if (useWindowScroll) {
            window.scrollTo({ top: 0, behavior: "smooth" });
          } else {
            const scroller = scrollerRef.current;
            if (typeof scroller?.scrollTo === "function") {
              scroller.scrollTo({ top: 0, behavior: "smooth" });
            } else if (scroller) {
              scroller.scrollTop = 0;
            }
          }
        },
      }),
      [useWindowScroll],
    );

    useLayoutEffect(() => {
      const scroller = scrollerRef.current;
      if (!scroller) return;

      const cards = Array.from(
        scroller.querySelectorAll<HTMLElement>(".scroll-stack-card"),
      );
      const reducedMotion = window.matchMedia(
        "(prefers-reduced-motion: reduce)",
      ).matches;
      const transforms = new WeakMap<HTMLElement, string>();
      let completed = false;

      const updateCards = () => {
        const viewportHeight = useWindowScroll
          ? window.innerHeight
          : scroller.clientHeight;
        const scrollTop = useWindowScroll ? window.scrollY : scroller.scrollTop;
        const stackY = positionToPixels(stackPosition, viewportHeight);
        const scaleEndY = positionToPixels(scaleEndPosition, viewportHeight);
        const scrollEnd = useWindowScroll
          ? document.documentElement.scrollHeight - viewportHeight
          : scroller.scrollHeight - viewportHeight;

        cards.forEach((card, index) => {
          const cardTop = useWindowScroll
            ? card.getBoundingClientRect().top + window.scrollY
            : card.offsetTop;
          const pinStart = cardTop - stackY - index * itemStackDistance;
          const pinProgress = clamp(
            (scrollTop - pinStart) / Math.max(itemDistance, 1),
          );
          const endProgress = clamp(
            (scrollTop - (scrollEnd - scaleEndY)) /
              Math.max(viewportHeight * scaleDuration, 1),
          );
          const translateY = Math.max(0, scrollTop - pinStart) * pinProgress;
          const scale = Math.max(
            baseScale,
            1 - index * itemScale - endProgress * itemScale,
          );
          const rotation = rotationAmount * pinProgress * (index % 2 ? -1 : 1);
          const blur = blurAmount * endProgress;
          const value = `translate3d(0, ${translateY.toFixed(2)}px, 0) scale(${scale.toFixed(4)}) rotate(${rotation.toFixed(2)}deg)`;

          if (transforms.get(card) !== value) {
            card.style.transform = value;
            card.style.filter = blur > 0 ? `blur(${blur.toFixed(2)}px)` : "none";
            card.style.zIndex = String(cards.length - index);
            transforms.set(card, value);
          }
        });

        const isComplete = scrollEnd > 0 && scrollTop >= scrollEnd - 2;
        if (isComplete && !completed) onStackComplete?.();
        completed = isComplete;
      };

      updateCards();

      const supportsLenis =
        typeof window.ResizeObserver === "function" &&
        typeof window.requestAnimationFrame === "function";

      if (reducedMotion || !supportsLenis) {
        scroller.addEventListener("scroll", updateCards, { passive: true });
        window.addEventListener("resize", updateCards);
        return () => {
          scroller.removeEventListener("scroll", updateCards);
          window.removeEventListener("resize", updateCards);
        };
      }

      const lenis = new Lenis({
        wrapper: useWindowScroll ? window : scroller,
        content: useWindowScroll
          ? document.documentElement
          : (scroller.firstElementChild as HTMLElement),
        smoothWheel: true,
        syncTouch: false,
      });
      lenisRef.current = lenis;
      lenis.on("scroll", updateCards);
      window.addEventListener("resize", updateCards);

      let animationFrame = 0;
      const raf = (time: number) => {
        lenis.raf(time);
        animationFrame = window.requestAnimationFrame(raf);
      };
      animationFrame = window.requestAnimationFrame(raf);

      return () => {
        window.cancelAnimationFrame(animationFrame);
        window.removeEventListener("resize", updateCards);
        lenis.destroy();
        if (lenisRef.current === lenis) lenisRef.current = null;
      };
    }, [
      baseScale,
      blurAmount,
      children,
      itemDistance,
      itemScale,
      itemStackDistance,
      onStackComplete,
      rotationAmount,
      scaleDuration,
      scaleEndPosition,
      stackPosition,
      useWindowScroll,
    ]);

    return (
      <div
        className={`scroll-stack-scroller ${className}`.trim()}
        ref={scrollerRef}
      >
        <div className="scroll-stack-inner">
          {children}
          <div className="scroll-stack-end" aria-hidden="true" />
        </div>
      </div>
    );
  },
);
