export const PRODUCT_CAMERA = {
  projection: "orthographic" as const,
  position: [0, 0, 6] as [number, number, number],
  zoom: 270,
};

export const PRODUCT_LIGHTING = {
  ambient: 0.24,
  frontFill: 0.72,
  hemisphere: 0.34,
  key: 2.25,
  rim: 1.08,
};

export const PRODUCT_RENDERING = {
  dpr: [1, 1.5] as [number, number],
};

export const PRODUCT_GEOMETRY = {
  source: "/ring/ring-capacitive-7-17.glb",
  touchSurfaceMaterial: "材质.005",
  removeOnly: ["hand"] as const,
  proceduralShell: false,
  proceduralCircuit: false,
  refineSourceSurface: false,
  conformCircuitSurface: true,
};
