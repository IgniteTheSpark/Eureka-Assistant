import { useRef, type ComponentPropsWithoutRef } from "react";
import { useGSAP } from "@gsap/react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";

gsap.registerPlugin(useGSAP, ScrollTrigger);

type HeadingTag = "h2" | "h3";

interface ScrollFloatTextProps
  extends Omit<ComponentPropsWithoutRef<"h2">, "children"> {
  as?: HeadingTag;
  lines?: readonly {
    className?: string;
    text: string;
  }[];
  text: string;
}

export function ScrollFloatText({
  as: Tag = "h2",
  className,
  lines,
  text,
  ...headingProps
}: ScrollFloatTextProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);

  useGSAP(
    () => {
      const heading = headingRef.current;
      if (!heading) return;
      const characters = heading.querySelectorAll<HTMLElement>(
        ".scroll-float-char",
      );
      const reducedMotion = window.matchMedia?.(
        "(prefers-reduced-motion: reduce)",
      ).matches;

      if (reducedMotion) {
        gsap.set(characters, {
          autoAlpha: 1,
          clearProps: "transform",
        });
        return;
      }

      const timeline = gsap.timeline({
        scrollTrigger: {
          end: "bottom bottom-=40%",
          invalidateOnRefresh: true,
          scrub: 0.35,
          start: "center bottom+=50%",
          trigger: heading,
        },
      });
      timeline.fromTo(
        characters,
        { autoAlpha: 0, scaleX: 0.7, scaleY: 2.3, yPercent: 120 },
        {
          autoAlpha: 1,
          duration: 1,
          ease: "power2.inOut",
          scaleX: 1,
          scaleY: 1,
          stagger: 0.03,
          yPercent: 0,
        },
      );
    },
    { scope: headingRef },
  );

  const rootClassName = ["scroll-float-text", className]
    .filter(Boolean)
    .join(" ");
  const visualLines = lines ?? [{ text }];

  return (
    <Tag
      className={rootClassName}
      data-scroll-float="scrub"
      ref={headingRef}
      {...headingProps}
    >
      <span className="sr-only">{text}</span>
      <span aria-hidden="true" className="scroll-float-visual">
        {visualLines.map((line, lineIndex) => (
          <span
            className={["scroll-float-line", line.className]
              .filter(Boolean)
              .join(" ")}
            key={`${line.text}-${lineIndex}`}
          >
            {Array.from(line.text).map((character, characterIndex) => (
              <span
                className="scroll-float-char"
                key={`${character}-${characterIndex}`}
              >
                {character === " " ? "\u00a0" : character}
              </span>
            ))}
          </span>
        ))}
      </span>
    </Tag>
  );
}
