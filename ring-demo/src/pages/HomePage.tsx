import { useEffect, useRef, useState } from "react";
import { useGSAP } from "@gsap/react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";

import { LivingRingStage } from "../components/living-ring/LivingRingStage";
import {
  mapLandingScrollProgress,
  type LandingChapterId,
  type LandingScrollAnchor,
} from "../components/living-ring/landing-journey";
import { observeLandingLayout } from "../components/living-ring/landing-layout-observer";
import { CommunityCta } from "../components/landing/CommunityCta";
import { DecryptedText } from "../components/landing/DecryptedText";
import { LandingStory } from "../components/landing/LandingStory";
import { LANDING_CONTENT } from "../components/landing/landing-content";
import { ScrollFloatText } from "../components/landing/ScrollFloatText";
import { ShuffleText } from "../components/landing/ShuffleText";
import type { RingJourneyFrame } from "../components/living-ring/journey-state";

gsap.registerPlugin(useGSAP, ScrollTrigger);

function useReducedMotion() {
  const [reduced, setReduced] = useState(false);

  useEffect(() => {
    if (!window.matchMedia) return;
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setReduced(query.matches);
    update();
    query.addEventListener?.("change", update);
    return () => query.removeEventListener?.("change", update);
  }, []);

  return reduced;
}

export function HomePage() {
  const homeRef = useRef<HTMLElement>(null);
  const journeyRef = useRef<RingJourneyFrame>({
    effectChapter: "",
    progress: 0,
    rotation: 0,
  });
  const reducedMotion = useReducedMotion();

  useGSAP(
    () => {
      if (!homeRef.current) return;
      if (reducedMotion) {
        journeyRef.current.effectChapter = "";
        journeyRef.current.progress = 0;
        journeyRef.current.rotation = 0;
        return;
      }
      let anchors: LandingScrollAnchor[] = [];
      let homeTop = 0;
      let senseRanges: Array<{
        end: number;
        id: "speak" | "touch" | "feel";
        start: number;
      }> = [];
      const updateSenseEffect = () => {
        const focusPosition =
          window.scrollY - homeTop + window.innerHeight * 0.5;
        journeyRef.current.effectChapter =
          senseRanges.find(
            ({ start, end }) =>
              focusPosition >= start && focusPosition < end,
          )?.id ?? "";
      };
      const updateAnchors = () => {
        const home = homeRef.current;
        if (!home) return;
        const scrollRange = Math.max(1, home.scrollHeight - window.innerHeight);
        homeTop = home.getBoundingClientRect().top + window.scrollY;
        anchors = Array.from(
          home.querySelectorAll<HTMLElement>("[data-ring-chapter]"),
        )
          .filter((element) => !element.closest(".living-ring-shell"))
          .map((section) => {
            const sectionTop =
              section.getBoundingClientRect().top + window.scrollY - homeTop;
            const centeredScroll =
              sectionTop + section.offsetHeight / 2 - window.innerHeight / 2;
            return {
              id: section.dataset.ringChapter as LandingChapterId,
              pageProgress: Math.min(
                1,
                Math.max(0, centeredScroll / scrollRange),
              ),
            };
          });
        senseRanges = Array.from(
          home.querySelectorAll<HTMLElement>(".sense-scene[data-ring-chapter]"),
        ).map((section) => {
          const start =
            section.getBoundingClientRect().top + window.scrollY - homeTop;
          return {
            end: start + section.offsetHeight,
            id: section.dataset.ringChapter as "speak" | "touch" | "feel",
            start,
          };
        });
        updateSenseEffect();
      };
      const trigger = ScrollTrigger.create({
        trigger: homeRef.current,
        start: "top top",
        end: "bottom bottom",
        onRefresh: updateAnchors,
        onUpdate: ({ progress }) => {
          journeyRef.current.progress = mapLandingScrollProgress(
            progress,
            anchors,
          );
          journeyRef.current.rotation = window.scrollY * 0.012;
          updateSenseEffect();
        },
      });
      updateAnchors();
      const stopObservingLayout = observeLandingLayout(
        homeRef.current,
        () => ScrollTrigger.refresh(),
      );
      const refresh = globalThis.setTimeout(() => ScrollTrigger.refresh(), 120);
      return () => {
        globalThis.clearTimeout(refresh);
        stopObservingLayout();
        trigger.kill();
        journeyRef.current.effectChapter = "";
      };
    },
    { dependencies: [reducedMotion], scope: homeRef, revertOnUpdate: true },
  );

  return (
    <main className="home" id="top" ref={homeRef}>
      <div className="living-ring-shell">
        <LivingRingStage
          connectionStatus="disconnected"
          focusedMode={null}
          journeyRef={journeyRef}
          reducedMotion={reducedMotion}
        />
      </div>

      <section
        className="hero"
        aria-labelledby="hero-title"
        data-ring-chapter="hero"
      >
        <div className="hero-copy">
          <p className="hero-signature">
            <strong>Eureka Ring</strong>
            <span>随身的个人智能入口</span>
          </p>
          <h1 aria-label={LANDING_CONTENT.hero.title} id="hero-title">
            <ShuffleText
              reducedMotion={reducedMotion}
              text="智能"
            />
            <ShuffleText
              reducedMotion={reducedMotion}
              shuffleDirection="left"
              text="触手可及"
            />
          </h1>
          <p className="hero-lede">{LANDING_CONTENT.hero.description}</p>
        </div>

        <p className="hero-release-note">
          正在内测
          <span>产品持续更新</span>
        </p>
      </section>

      <section
        aria-labelledby="modes-title"
        className="demo-launcher"
        data-ring-chapter="modes"
        id="modes"
      >
        <header className="demo-launcher-header">
          <ScrollFloatText
            id="modes-title"
            lines={[
              { className: "mode-title-line-primary", text: "一枚戒指" },
              {
                className: "mode-title-line-secondary",
                text: "两种智能体验",
              },
            ]}
            text={LANDING_CONTENT.modes.title}
          />
          <p>{LANDING_CONTENT.modes.description}</p>
        </header>

        <div aria-hidden="true" className="mode-ring-corridor" />

        <div className="mode-thesis" aria-label="Flash 与 Vibe 两种体验">
          <div>
            <span>Flash</span>
            <strong>
              <DecryptedText
                reducedMotion={reducedMotion}
                text="把一句话变成可继续使用的资产。"
              />
            </strong>
          </div>
          <div>
            <span>Vibe</span>
            <strong>
              <DecryptedText
                reducedMotion={reducedMotion}
                text="让声音直接进入正在使用的工具。"
              />
            </strong>
          </div>
        </div>

        <div
          aria-hidden="true"
          className="mode-bridge-anchor"
          data-ring-chapter="mode-bridge"
        />
      </section>

      <LandingStory />
      <div id="community">
        <CommunityCta />
      </div>
    </main>
  );
}
