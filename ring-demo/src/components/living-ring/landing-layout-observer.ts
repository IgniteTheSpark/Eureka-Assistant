export function observeLandingLayout(
  root: HTMLElement,
  onLayout: () => void,
) {
  const images = Array.from(root.querySelectorAll("img"));
  const pendingImages = images.filter((image) => !image.complete);
  pendingImages.forEach((image) => image.addEventListener("load", onLayout));

  const observer =
    typeof ResizeObserver === "function"
      ? new ResizeObserver(() => onLayout())
      : null;
  observer?.observe(root);
  root
    .querySelectorAll<HTMLElement>("[data-ring-chapter]")
    .forEach((chapter) => observer?.observe(chapter));

  let cancelled = false;
  void document.fonts?.ready.then(() => {
    if (!cancelled) onLayout();
  });

  return () => {
    cancelled = true;
    observer?.disconnect();
    pendingImages.forEach((image) =>
      image.removeEventListener("load", onLayout),
    );
  };
}
