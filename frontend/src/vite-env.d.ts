/// <reference types="vite/client" />

// Allow CSS imports to be picked up by TS without complaints
declare module "*.css" {
  const content: string;
  export default content;
}

declare module "*.svg" {
  const src: string;
  export default src;
}
