import { act, createRef } from "react";
import { render } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import Lenis from "lenis";
import {
  ScrollStack,
  ScrollStackItem,
  type ScrollStackHandle,
} from "./ScrollStack";

const lenisApi = {
  destroy: vi.fn(),
  on: vi.fn(),
  raf: vi.fn(),
  scrollTo: vi.fn(),
};

vi.mock("lenis", () => ({
  default: vi.fn(() => lenisApi),
}));

describe("ScrollStack", () => {
  beforeEach(() => {
    vi.stubGlobal(
      "ResizeObserver",
      class ResizeObserver {
        observe() {}
        unobserve() {}
        disconnect() {}
      },
    );
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.clearAllMocks();
  });

  it("uses an internal scroller and exposes scrollToStart", () => {
    const ref = createRef<ScrollStackHandle>();
    const { container } = render(
      <ScrollStack ref={ref} useWindowScroll={false}>
        <ScrollStackItem>One</ScrollStackItem>
        <ScrollStackItem>Two</ScrollStackItem>
      </ScrollStack>,
    );

    const scroller = container.querySelector(".scroll-stack-scroller");
    expect(scroller).not.toBeNull();
    expect(container.querySelectorAll(".scroll-stack-card")).toHaveLength(2);
    expect(Lenis).toHaveBeenCalledWith(
      expect.objectContaining({ wrapper: scroller }),
    );

    act(() => ref.current?.scrollToStart());
    expect(lenisApi.scrollTo).toHaveBeenCalledWith(0, { immediate: false });
  });

  it("destroys the Lenis instance when unmounted", () => {
    const { unmount } = render(
      <ScrollStack useWindowScroll={false}>
        <ScrollStackItem>One</ScrollStackItem>
      </ScrollStack>,
    );

    const destroyCount = lenisApi.destroy.mock.calls.length;
    unmount();
    expect(lenisApi.destroy).toHaveBeenCalledTimes(destroyCount + 1);
  });

  it("keeps the first item visually in front of later stack items", () => {
    const { container } = render(
      <ScrollStack useWindowScroll={false}>
        <ScrollStackItem>Newest</ScrollStackItem>
        <ScrollStackItem>Older</ScrollStackItem>
      </ScrollStack>,
    );

    const cards = container.querySelectorAll<HTMLElement>(".scroll-stack-card");
    expect(cards[0]?.style.zIndex).toBe("2");
    expect(cards[1]?.style.zIndex).toBe("1");
  });
});
