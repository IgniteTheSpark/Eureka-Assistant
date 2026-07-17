import { act, render } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";

import { DecryptedText } from "./DecryptedText";

afterEach(() => {
  vi.unstubAllGlobals();
});

it("starts decrypting only after the copy crosses the viewport midpoint", () => {
  let observerCallback: IntersectionObserverCallback | undefined;
  let observerOptions: IntersectionObserverInit | undefined;

  class MockIntersectionObserver {
    constructor(
      callback: IntersectionObserverCallback,
      options?: IntersectionObserverInit,
    ) {
      observerCallback = callback;
      observerOptions = options;
    }

    disconnect() {}
    observe() {}
    takeRecords() {
      return [];
    }
    unobserve() {}

    readonly root = null;
    readonly rootMargin = "0px";
    readonly thresholds = [0];
  }

  vi.stubGlobal("IntersectionObserver", MockIntersectionObserver);

  const { container } = render(
    <DecryptedText text="让声音直接进入正在使用的工具。" />,
  );

  const root = container.querySelector(".decrypted-text");
  expect(root?.getAttribute("data-decrypted-state")).toBe("idle");
  expect(root?.getAttribute("data-decrypted-visible")).toBe("false");

  expect(observerOptions).toEqual({
    rootMargin: "0px 0px -50% 0px",
    threshold: 0,
  });

  act(() => {
    observerCallback?.(
      [{ isIntersecting: true } as IntersectionObserverEntry],
      {} as IntersectionObserver,
    );
  });

  expect(root?.getAttribute("data-decrypted-state")).toBe("running");
  expect(root?.getAttribute("data-decrypted-visible")).toBe("true");
});
