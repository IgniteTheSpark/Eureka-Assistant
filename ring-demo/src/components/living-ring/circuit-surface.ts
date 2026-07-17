import { Matrix4, Mesh, Vector3 } from "three";

const INNER_WALL_CIRCUIT_RADIUS = 0.0674;

export function isInnerWallCircuitPatch(name: string) {
  return name.startsWith("Object_5");
}

export function conformCircuitToInnerWall(
  mesh: Mesh,
  radius = INNER_WALL_CIRCUIT_RADIUS,
) {
  const geometry = mesh.geometry.clone();
  const position = geometry.getAttribute("position");
  if (!position) return geometry;

  const worldToLocal = new Matrix4().copy(mesh.matrixWorld).invert();
  const point = new Vector3();
  for (let index = 0; index < position.count; index += 1) {
    point.fromBufferAttribute(position, index).applyMatrix4(mesh.matrixWorld);
    const angle = Math.atan2(point.z, point.x);
    point.set(Math.cos(angle) * radius, point.y, Math.sin(angle) * radius);
    point.applyMatrix4(worldToLocal);
    position.setXYZ(index, point.x, point.y, point.z);
  }
  position.needsUpdate = true;
  geometry.computeVertexNormals();
  geometry.computeBoundingBox();
  geometry.computeBoundingSphere();
  return geometry;
}
