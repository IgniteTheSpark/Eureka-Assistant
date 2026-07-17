import { afterEach, describe, expect, it, vi } from "vitest";

import { observeLandingLayout } from "./landing-layout-observer";

describe("observeLandingLayout", () => {
  afterEach(() => vi.restoreAllMocks());

  it("remeasures the ring route after responsive layout and lazy images settle", () => {
    let resizeCallback: ResizeObserverCallback | undefined;
    const disconnect = vi.fn();
    const observe = vi.fn();
    vi.stubGlobal(
      "ResizeObserver",
      class {
        constructor(callback: ResizeObserverCallback) {
          resizeCallback = callback;
        }
        disconnect = disconnect;
        observe = observe;
        unobserve = vi.fn();
      },
    );
    const onLayout = vi.fn();
    const root = document.createElement("main");
    const image = document.createElement("img");
    Object.defineProperty(image, "complete", { configurable: true, value: false });
    root.append(image);

    const stop = observeLandingLayout(root, onLayout);
    expect(observe).toHaveBeenCalledWith(root);

    resizeCallback?.([], {} as ResizeObserver);
    image.dispatchEvent(new Event("load"));
    expect(onLayout).toHaveBeenCalledTimes(2);

    stop();
    expect(disconnect).toHaveBeenCalledTimes(1);
    image.dispatchEvent(new Event("load"));
    expect(onLayout).toHaveBeenCalledTimes(2);
  });
});
