import {
  BoxGeometry,
  BufferGeometry,
  Float32BufferAttribute,
  Group,
  Mesh,
  MeshPhysicalMaterial,
  MeshStandardMaterial,
} from "three";
import { describe, expect, it } from "vitest";

import { prepareSourceRing } from "./source-model";

describe("prepareSourceRing", () => {
  it("removes only the hand and preserves the complete ring hierarchy", () => {
    const source = new Group();
    const ringRoot = new Group();
    ringRoot.name = "空物体";
    const shell = new Mesh(
      new BoxGeometry(1, 0.25, 1),
      new MeshStandardMaterial({ name: "材质" }),
    );
    shell.name = "柱体";
    ringRoot.add(shell);

    const hand = new Mesh(
      new BoxGeometry(12, 12, 12),
      new MeshStandardMaterial(),
    );
    hand.name = "hand_LP:Group3794";
    source.add(ringRoot, hand);

    const prepared = prepareSourceRing(source);

    expect(prepared.object.getObjectByName("hand_LP:Group3794")).toBeUndefined();
    expect(prepared.object.getObjectByName("空物体")).toBeDefined();
    expect(prepared.object.getObjectByName("柱体")).toBeDefined();
    expect(prepared.uniformScale).toBeCloseTo(2);
    expect(prepared.exteriorMaterials.length).toBe(1);
    expect(prepared.exteriorMaterials[0]).toBeInstanceOf(MeshPhysicalMaterial);
    expect(
      (prepared.exteriorMaterials[0] as MeshPhysicalMaterial).clearcoat,
    ).toBeCloseTo(0.18);
  });

  it("preserves designer-authored high-resolution geometry by default", () => {
    const source = new Group();
    const shellGeometry = new BoxGeometry(1, 0.25, 1, 2, 2, 2);
    const circuitGeometry = new BoxGeometry(0.1, 0.02, 0.02);
    const shell = new Mesh(
      shellGeometry,
      new MeshStandardMaterial({ name: "材质" }),
    );
    shell.name = "shell";
    const circuit = new Mesh(
      circuitGeometry,
      new MeshStandardMaterial({ name: "材质.002" }),
    );
    circuit.name = "circuit";
    source.add(shell, circuit);

    const prepared = prepareSourceRing(source);
    const preparedShell = prepared.object.getObjectByName("shell") as Mesh;
    const preparedCircuit = prepared.object.getObjectByName("circuit") as Mesh;

    expect(preparedShell.geometry).toBe(shellGeometry);
    expect(preparedCircuit.geometry).toBe(circuitGeometry);
  });

  it("collects the designer-authored capacitive surface separately from the shell", () => {
    const source = new Group();
    const shell = new Mesh(
      new BoxGeometry(1, 0.25, 1),
      new MeshStandardMaterial({ name: "材质" }),
    );
    const touchSurface = new Mesh(
      new BoxGeometry(0.2, 0.02, 0.4),
      new MeshStandardMaterial({
        color: "#080808",
        name: "材质.005",
        roughness: 0.8,
      }),
    );
    source.add(shell, touchSurface);

    const prepared = prepareSourceRing(source, {
      touchSurfaceMaterial: "材质.005",
    });

    expect(prepared.exteriorMaterials).toHaveLength(1);
    expect(prepared.touchMaterials).toHaveLength(1);
    expect(prepared.touchMaterials[0].name).toBe("材质.005");
    expect(prepared.touchMaterials[0]).not.toBe(prepared.exteriorMaterials[0]);
  });

  it("can refine only a low-resolution shell while leaving circuit geometry untouched", () => {
    const source = new Group();
    const shellGeometry = new BoxGeometry(1, 0.25, 1, 2, 2, 2);
    const circuitGeometry = new BoxGeometry(0.1, 0.02, 0.02);
    const shell = new Mesh(
      shellGeometry,
      new MeshStandardMaterial({ name: "材质" }),
    );
    shell.name = "shell";
    const circuit = new Mesh(
      circuitGeometry,
      new MeshStandardMaterial({ name: "材质.002" }),
    );
    circuit.name = "circuit";
    source.add(shell, circuit);

    const prepared = prepareSourceRing(source, { refineSurface: true });
    const preparedShell = prepared.object.getObjectByName("shell") as Mesh;
    const preparedCircuit = prepared.object.getObjectByName("circuit") as Mesh;

    expect(preparedShell.geometry).not.toBe(shellGeometry);
    expect(preparedShell.geometry.attributes.position.count).toBeGreaterThan(
      shellGeometry.attributes.position.count,
    );
    expect(preparedCircuit.geometry).toBe(circuitGeometry);
  });

  it("conforms flat circuit patches to the inner wall without moving other components", () => {
    const source = new Group();
    const circuitGeometry = new BufferGeometry();
    circuitGeometry.setAttribute(
      "position",
      new Float32BufferAttribute(
        [-0.02, 0, -0.057, 0, 0, -0.057, 0.02, 0, -0.057],
        3,
      ),
    );
    const circuit = new Mesh(
      circuitGeometry,
      new MeshStandardMaterial({ name: "材质.002" }),
    );
    circuit.name = "Object_5";
    const contactGeometry = new BoxGeometry(0.01, 0.01, 0.01);
    const contact = new Mesh(
      contactGeometry,
      new MeshStandardMaterial({ name: "材质.002" }),
    );
    contact.name = "立方体";
    source.add(circuit, contact);

    const prepared = prepareSourceRing(source, {
      conformCircuitSurface: true,
    });
    const preparedCircuit = prepared.object.getObjectByName("Object_5") as Mesh;
    const preparedContact = prepared.object.getObjectByName("立方体") as Mesh;
    const position = preparedCircuit.geometry.getAttribute("position");
    const radii = Array.from({ length: position.count }, (_, index) =>
      Math.hypot(position.getX(index), position.getZ(index)),
    );

    expect(preparedCircuit.geometry).not.toBe(circuitGeometry);
    expect(Math.max(...radii) - Math.min(...radii)).toBeLessThan(0.00001);
    expect(radii[0]).toBeCloseTo(0.0674, 4);
    expect(preparedContact.geometry).toBe(contactGeometry);
  });
});
