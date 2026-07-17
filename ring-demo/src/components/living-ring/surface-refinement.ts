import {
  BufferGeometry,
  Float32BufferAttribute,
  Vector3,
} from "three";

interface EdgeData {
  a: number;
  b: number;
  opposites: number[];
  vertex?: number;
}

function edgeKey(a: number, b: number) {
  return a < b ? `${a}:${b}` : `${b}:${a}`;
}

function subdivideOnce(source: BufferGeometry) {
  const position = source.getAttribute("position");
  if (!position) return source.clone();

  const sourceIndex = source.getIndex();
  const indices = sourceIndex
    ? Array.from(sourceIndex.array)
    : Array.from({ length: position.count }, (_, index) => index);
  const vertices = Array.from({ length: position.count }, (_, index) =>
    new Vector3().fromBufferAttribute(position, index),
  );
  const neighbors = vertices.map(() => new Set<number>());
  const edges = new Map<string, EdgeData>();

  const registerEdge = (a: number, b: number, opposite: number) => {
    const key = edgeKey(a, b);
    const edge = edges.get(key) ?? {
      a: Math.min(a, b),
      b: Math.max(a, b),
      opposites: [],
    };
    edge.opposites.push(opposite);
    edges.set(key, edge);
    neighbors[a].add(b);
    neighbors[b].add(a);
  };

  for (let index = 0; index < indices.length; index += 3) {
    const a = indices[index];
    const b = indices[index + 1];
    const c = indices[index + 2];
    registerEdge(a, b, c);
    registerEdge(b, c, a);
    registerEdge(c, a, b);
  }

  const boundaryVertices = new Set<number>();
  edges.forEach((edge) => {
    if (edge.opposites.length === 1) {
      boundaryVertices.add(edge.a);
      boundaryVertices.add(edge.b);
    }
  });

  const refinedVertices = vertices.map((vertex, index) => {
    if (boundaryVertices.has(index)) return vertex.clone();
    const adjacent = [...neighbors[index]];
    if (adjacent.length < 3) return vertex.clone();
    const beta = adjacent.length === 3 ? 3 / 16 : 3 / (8 * adjacent.length);
    const next = vertex.clone().multiplyScalar(1 - adjacent.length * beta);
    adjacent.forEach((neighbor) => {
      next.addScaledVector(vertices[neighbor], beta);
    });
    return next;
  });

  edges.forEach((edge) => {
    const next = new Vector3();
    if (edge.opposites.length === 2) {
      next
        .addScaledVector(vertices[edge.a], 3 / 8)
        .addScaledVector(vertices[edge.b], 3 / 8)
        .addScaledVector(vertices[edge.opposites[0]], 1 / 8)
        .addScaledVector(vertices[edge.opposites[1]], 1 / 8);
    } else {
      next
        .add(vertices[edge.a])
        .add(vertices[edge.b])
        .multiplyScalar(0.5);
    }
    edge.vertex = refinedVertices.length;
    refinedVertices.push(next);
  });

  const refinedIndices: number[] = [];
  for (let index = 0; index < indices.length; index += 3) {
    const a = indices[index];
    const b = indices[index + 1];
    const c = indices[index + 2];
    const ab = edges.get(edgeKey(a, b))?.vertex;
    const bc = edges.get(edgeKey(b, c))?.vertex;
    const ca = edges.get(edgeKey(c, a))?.vertex;
    if (ab === undefined || bc === undefined || ca === undefined) continue;
    refinedIndices.push(
      a,
      ab,
      ca,
      b,
      bc,
      ab,
      c,
      ca,
      bc,
      ab,
      bc,
      ca,
    );
  }

  const geometry = new BufferGeometry();
  geometry.name = source.name;
  geometry.setAttribute(
    "position",
    new Float32BufferAttribute(
      refinedVertices.flatMap((vertex) => [vertex.x, vertex.y, vertex.z]),
      3,
    ),
  );
  geometry.setIndex(refinedIndices);
  geometry.computeVertexNormals();
  geometry.computeBoundingBox();
  geometry.computeBoundingSphere();
  return geometry;
}

export function refineProductSurface(
  source: BufferGeometry,
  iterations = 2,
) {
  let geometry = source;
  for (let iteration = 0; iteration < iterations; iteration += 1) {
    const refined = subdivideOnce(geometry);
    if (geometry !== source) geometry.dispose();
    geometry = refined;
  }
  return geometry;
}
