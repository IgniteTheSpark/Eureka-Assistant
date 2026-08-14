window.RekaRendererFactory = function ReKaRendererFactory(
  THREE,
  canvas,
  postHostMessage,
) {
  const THRESHOLDS = [
    0.94118, 0.29412, 0.76471, 0.05882,
    0.47059, 0.70588, 0.23529, 0.52941,
    0.82353, 0.11765, 0.88235, 0.17647,
    0.35294, 0.58824, 0.41176, 0.64706,
  ];

  const POST_VERTEX = `
    out vec2 vUv;
    void main() {
      vUv = position.xy * 0.5 + 0.5;
      gl_Position = vec4(position.xy, 0.0, 1.0);
    }
  `;

  const POST_FRAGMENT = `
    precision highp float;
    in vec2 vUv;
    out vec4 outColor;
    uniform sampler2D tDiffuse;
    uniform vec2 uResolution;
    uniform float uGridSize;
    uniform float uPixelSizeRatio;

    const mat4 THRESHOLDS = mat4(
      ${THRESHOLDS.slice(0, 4).join(', ')},
      ${THRESHOLDS.slice(4, 8).join(', ')},
      ${THRESHOLDS.slice(8, 12).join(', ')},
      ${THRESHOLDS.slice(12, 16).join(', ')}
    );

    vec3 toSrgb(vec3 color) {
      color = clamp(color, 0.0, 1.0);
      return mix(
        color * 12.92,
        1.055 * pow(color, vec3(1.0 / 2.4)) - 0.055,
        step(vec3(0.0031308), color)
      );
    }

    float bayerThreshold(vec2 cellCoord) {
      ivec2 point = ivec2(mod(cellCoord, 4.0));
      return THRESHOLDS[point.x][point.y];
    }

    void main() {
      vec2 fragCoord = vUv * uResolution;
      float pixelSize = uGridSize * uPixelSizeRatio;
      vec2 pixelUv =
        (floor(fragCoord / pixelSize) + 0.5) * pixelSize / uResolution;
      vec4 sampleColor = texture(tDiffuse, pixelUv);
      vec3 color = toSrgb(sampleColor.rgb);
      float level = dot(color, vec3(0.299, 0.587, 0.114));
      bool lit = level >= bayerThreshold(fragCoord / uGridSize);
      vec3 dithered = lit ? color : vec3(0.0);
      outColor = vec4(dithered * sampleColor.a, sampleColor.a);
    }
  `;

  let renderer = null;
  let scene = null;
  let camera = null;
  let target = null;
  let postScene = null;
  let postCamera = null;
  let postMaterial = null;
  let motionGroup = null;
  let eyeGroup = null;
  let keyLight = null;
  let fillLight = null;
  let rimLight = null;
  let observer = null;
  let disposed = false;
  let paused = false;
  let reduceMotion = false;
  let loopRunning = false;
  let elapsed = 0;
  let lastTime = 0;
  let refreshPulse = 0;
  let state = 'idle';
  let targetTiltX = 0;
  let targetTiltY = 0;
  let currentTiltX = 0;
  let currentTiltY = 0;
  let productionPitch = 0;
  let productionYaw = 0;
  let productionEyeY = 0;
  let productionRecoil = 0;
  let productionImpulse = 0;
  let production = { kind: null, phase: 'idle', side: 'right' };
  let options = {
    gridSize: 4,
    pixelSizeRatio: 1,
    maxDpr: 2,
    reduceMotion: false,
  };

  const ownedGeometries = [];
  const ownedMaterials = [];

  function ownGeometry(geometry) {
    ownedGeometries.push(geometry);
    return geometry;
  }

  function ownMaterial(material) {
    ownedMaterials.push(material);
    return material;
  }

  function createHead() {
    motionGroup = new THREE.Group();
    scene.add(motionGroup);

    const shellMaterial = ownMaterial(new THREE.MeshStandardMaterial({
      color: 0xf2f1eb,
      roughness: 0.34,
      metalness: 0.08,
    }));
    const sideMaterial = ownMaterial(new THREE.MeshStandardMaterial({
      color: 0x9d9d96,
      roughness: 0.42,
      metalness: 0.16,
    }));
    const visorMaterial = ownMaterial(new THREE.MeshStandardMaterial({
      color: 0x121311,
      roughness: 0.22,
      metalness: 0.3,
    }));
    const eyeMaterial = ownMaterial(new THREE.MeshStandardMaterial({
      color: 0x78ff74,
      emissive: 0x2acb63,
      emissiveIntensity: 2.4,
      roughness: 0.3,
      metalness: 0.04,
    }));

    const shellGeometry = ownGeometry(
      new THREE.CapsuleGeometry(0.82, 0.76, 12, 28),
    );
    shellGeometry.rotateZ(Math.PI / 2);
    const shell = new THREE.Mesh(shellGeometry, shellMaterial);
    shell.scale.set(1.05, 0.96, 0.72);
    shell.layers.set(0);
    motionGroup.add(shell);

    const visorGeometry = ownGeometry(
      new THREE.CapsuleGeometry(0.49, 1.03, 8, 24),
    );
    visorGeometry.rotateZ(Math.PI / 2);
    const visor = new THREE.Mesh(visorGeometry, visorMaterial);
    visor.position.set(0, -0.035, 0.63);
    visor.scale.set(0.96, 0.86, 0.08);
    visor.layers.set(0);
    motionGroup.add(visor);

    const sideGeometry = ownGeometry(
      new THREE.CylinderGeometry(0.34, 0.34, 0.24, 24),
    );
    sideGeometry.rotateZ(Math.PI / 2);
    for (const side of [-1, 1]) {
      const module = new THREE.Mesh(sideGeometry, sideMaterial);
      module.position.set(side * 1.26, 0, -0.02);
      module.scale.set(1, 0.88, 0.88);
      module.layers.set(0);
      motionGroup.add(module);
    }

    const pixelGeometry = ownGeometry(new THREE.PlaneGeometry(0.105, 0.105));
    eyeGroup = new THREE.Group();
    motionGroup.add(eyeGroup);
    const eyeCenters = [-0.46, 0.46];
    const pixelGap = 0.135;
    for (const eyeCenter of eyeCenters) {
      for (let row = 0; row < 3; row += 1) {
        for (let column = 0; column < 3; column += 1) {
          if (row === 1 && column === 1) continue;
          const pixel = new THREE.Mesh(pixelGeometry, eyeMaterial);
          pixel.position.set(
            eyeCenter + (column - 1) * pixelGap,
            0.015 + (1 - row) * pixelGap,
            0.732,
          );
          pixel.layers.set(0);
          eyeGroup.add(pixel);
        }
      }
    }

    motionGroup.scale.setScalar(1.12);
    motionGroup.position.y = 0.03;
  }

  function createPostProcess() {
    target = new THREE.WebGLRenderTarget(1, 1, {
      samples: 4,
      depthBuffer: true,
      stencilBuffer: false,
    });
    target.texture.colorSpace = THREE.SRGBColorSpace;

    postMaterial = ownMaterial(new THREE.ShaderMaterial({
      glslVersion: THREE.GLSL3,
      vertexShader: POST_VERTEX,
      fragmentShader: POST_FRAGMENT,
      uniforms: {
        tDiffuse: { value: target.texture },
        uResolution: { value: new THREE.Vector2(1, 1) },
        uGridSize: { value: options.gridSize },
        uPixelSizeRatio: { value: options.pixelSizeRatio },
      },
      depthTest: false,
      depthWrite: false,
      transparent: true,
      blending: THREE.NoBlending,
    }));

    const geometry = ownGeometry(new THREE.BufferGeometry());
    geometry.setAttribute(
      'position',
      new THREE.BufferAttribute(
        new Float32Array([-1, -1, 0, 3, -1, 0, -1, 3, 0]),
        3,
      ),
    );
    const mesh = new THREE.Mesh(geometry, postMaterial);
    mesh.frustumCulled = false;
    postScene = new THREE.Scene();
    postScene.add(mesh);
    postCamera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  }

  function resize(width, height, dpr) {
    if (!renderer || disposed) return;
    const cssWidth = Math.max(Number(width) || canvas.clientWidth || 1, 1);
    const cssHeight = Math.max(Number(height) || canvas.clientHeight || 1, 1);
    const pixelRatio = Math.min(
      Math.max(Number(dpr) || window.devicePixelRatio || 1, 1),
      options.maxDpr,
    );
    renderer.setPixelRatio(pixelRatio);
    renderer.setSize(cssWidth, cssHeight, false);
    const pixelSize = options.gridSize * options.pixelSizeRatio * pixelRatio;
    const targetScale = Math.min(1, 2 / pixelSize);
    target.setSize(
      Math.max(Math.round(cssWidth * pixelRatio * targetScale), 1),
      Math.max(Math.round(cssHeight * pixelRatio * targetScale), 1),
    );
    postMaterial.uniforms.uResolution.value.set(
      Math.round(cssWidth * pixelRatio),
      Math.round(cssHeight * pixelRatio),
    );
    postMaterial.uniforms.uGridSize.value = options.gridSize * pixelRatio;
    camera.aspect = cssWidth / cssHeight;
    camera.updateProjectionMatrix();
  }

  function setMotion(pose) {
    if (disposed || !pose) return;
    state = pose.state || 'idle';
    if (reduceMotion) {
      targetTiltX = 0;
      targetTiltY = 0;
      return;
    }
    const maxRadians = THREE.MathUtils.degToRad(8);
    targetTiltX = THREE.MathUtils.clamp(
      THREE.MathUtils.degToRad(Number(pose.tiltXDegrees) || 0),
      -maxRadians,
      maxRadians,
    );
    targetTiltY = THREE.MathUtils.clamp(
      THREE.MathUtils.degToRad(Number(pose.tiltYDegrees) || 0),
      -maxRadians,
      maxRadians,
    );
  }

  function setReduceMotion(enabled) {
    reduceMotion = Boolean(enabled);
    if (reduceMotion) {
      targetTiltX = 0;
      targetTiltY = 0;
      currentTiltX = 0;
      currentTiltY = 0;
      refreshPulse = 0;
      if (motionGroup) {
        motionGroup.position.y = 0.03;
        motionGroup.rotation.set(0, 0, 0);
      }
      if (eyeGroup) eyeGroup.position.y = productionTargets().eyeY * 0.65;
    }
  }

  function productionTargets() {
    const active = production.phase === 'emit' || production.phase === 'handoff';
    const charging = production.phase === 'charge';
    const signal = production.kind === 'signal';
    return {
      pitch: active ? (signal ? -0.18 : 0.21) : 0,
      yaw: charging ? (production.side === 'right' ? 0.13 : -0.13) : 0,
      eyeY: active ? (signal ? 0.11 : -0.11) : 0,
      recoil: active ? (signal ? -0.055 : 0.055) : 0,
    };
  }

  function setProduction(nextCue) {
    if (disposed) return;
    const next = nextCue || {};
    const nextPhase = next.phase || 'idle';
    if (nextPhase === 'charge' && production.phase !== 'charge') {
      productionImpulse = 1;
    }
    production = {
      kind: next.kind || null,
      phase: nextPhase,
      side: next.side === 'left' ? 'left' : 'right',
    };
    if (reduceMotion && eyeGroup) {
      eyeGroup.position.y = productionTargets().eyeY * 0.65;
    }
  }

  function pulseRefresh() {
    if (!disposed && !reduceMotion) refreshPulse = 1;
  }

  function tick(time) {
    if (paused || disposed) return;
    const delta = lastTime ? Math.min((time - lastTime) / 1000, 0.1) : 0;
    lastTime = time;
    elapsed += delta;

    const follow = 1 - Math.exp(-delta * 12);
    currentTiltX += (targetTiltX - currentTiltX) * follow;
    currentTiltY += (targetTiltY - currentTiltY) * follow;
    refreshPulse = Math.max(0, refreshPulse - delta / 0.32);
    const productionTarget = productionTargets();
    const productionFollow = 1 - Math.exp(-delta * 10);
    productionPitch += (productionTarget.pitch - productionPitch) * productionFollow;
    productionYaw += (productionTarget.yaw - productionYaw) * productionFollow;
    productionEyeY += (productionTarget.eyeY - productionEyeY) * productionFollow;
    productionRecoil += (productionTarget.recoil - productionRecoil) * productionFollow;
    productionImpulse = Math.max(0, productionImpulse - delta / 0.24);

    if (!reduceMotion) {
      const idleWeight = state === 'idle' ? 1 : 0.18;
      const dragYawMultiplier = state === 'dragging'
        ? 4
        : state === 'settling'
          ? 2.4
          : 1;
      const shake = Math.sin(elapsed * 54) * productionImpulse * 0.028;
      motionGroup.position.y = 0.03 +
        Math.sin(elapsed * 1.15) * 0.055 * idleWeight +
        productionRecoil;
      motionGroup.rotation.x = currentTiltX +
        Math.cos(elapsed * 0.7) * 0.025 * idleWeight +
        productionPitch;
      motionGroup.rotation.y = currentTiltY * dragYawMultiplier +
        Math.sin(elapsed * 0.62) * 0.04 * idleWeight +
        productionYaw;
      motionGroup.rotation.z =
        Math.sin(elapsed * 0.48) * 0.018 * idleWeight + shake;
      if (eyeGroup) eyeGroup.position.y = productionEyeY;
    } else if (eyeGroup) {
      eyeGroup.position.y = productionTarget.eyeY * 0.65;
    }

    const breath = reduceMotion ? 0 : (Math.sin(elapsed * 1.25) + 1) * 0.5;
    keyLight.intensity = 5.2 + breath * 0.42 + refreshPulse * 2.1;
    fillLight.intensity = 2.1 + breath * 0.18;
    rimLight.intensity = 3.4 + refreshPulse * 0.8;

    renderer.autoClear = true;
    renderer.setRenderTarget(target);
    renderer.setClearColor(0x000000, 0);
    renderer.clear(true, true, true);
    camera.layers.set(0);
    renderer.render(scene, camera);

    renderer.setRenderTarget(null);
    renderer.clear(true, true, true);
    renderer.render(postScene, postCamera);

  }

  function startLoop() {
    if (!renderer || loopRunning || paused || disposed) return;
    loopRunning = true;
    lastTime = 0;
    renderer.setAnimationLoop(tick);
  }

  function stopLoop() {
    if (!renderer || !loopRunning) return;
    loopRunning = false;
    renderer.setAnimationLoop(null);
    lastTime = 0;
  }

  function setPaused(value) {
    paused = Boolean(value);
    if (paused) stopLoop();
    else startLoop();
  }

  function init(nextOptions) {
    if (renderer || disposed) return;
    options = { ...options, ...(nextOptions || {}) };
    reduceMotion = Boolean(options.reduceMotion);
    renderer = new THREE.WebGLRenderer({
      canvas,
      antialias: false,
      alpha: true,
      premultipliedAlpha: true,
      powerPreference: 'high-performance',
    });
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.08;
    renderer.setClearColor(0x000000, 0);

    scene = new THREE.Scene();
    camera = new THREE.PerspectiveCamera(65, 1, 0.1, 100);
    camera.position.set(0, 0, 4.0);
    camera.lookAt(0, 0, 0);

    scene.add(new THREE.AmbientLight(0xffffff, 0.42));
    keyLight = new THREE.DirectionalLight(0xffffff, 5.2);
    keyLight.position.set(-2.8, 3.7, 4.6);
    scene.add(keyLight);
    fillLight = new THREE.DirectionalLight(0xdce7ff, 2.1);
    fillLight.position.set(3.5, 0.5, 2.2);
    scene.add(fillLight);
    rimLight = new THREE.DirectionalLight(0xffffff, 3.4);
    rimLight.position.set(0.5, 3.2, -3.4);
    scene.add(rimLight);

    createHead();
    createPostProcess();
    resize(canvas.clientWidth, canvas.clientHeight, window.devicePixelRatio);
    setReduceMotion(reduceMotion);

    observer = new ResizeObserver(() => {
      resize(canvas.clientWidth, canvas.clientHeight, window.devicePixelRatio);
    });
    observer.observe(canvas);
    canvas.addEventListener('webglcontextlost', (event) => {
      event.preventDefault();
      setPaused(true);
      postHostMessage({ type: 'error', code: 'context_lost' });
    });
    startLoop();
  }

  function destroy() {
    if (disposed) return;
    stopLoop();
    disposed = true;
    observer?.disconnect();
    target?.dispose();
    for (const geometry of ownedGeometries) geometry.dispose();
    for (const material of ownedMaterials) material.dispose();
    renderer?.dispose();
    renderer?.forceContextLoss();
    scene = null;
    postScene = null;
    motionGroup = null;
    eyeGroup = null;
  }

  window.RekaRenderer = Object.freeze({
    init,
    setMotion,
    setReduceMotion,
    setPaused,
    setProduction,
    pulseRefresh,
    resize,
    destroy,
  });
};
