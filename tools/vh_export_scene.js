// Run inside the reference app (vite dev server) to export its fully built scene for the Godot parity
// harness: every mesh / instanced mesh / LOD with geometry buffers, instance data, world matrices and a
// material descriptor. Bodies are POSTed to a local receiver (tools: receiver on 127.0.0.1:8766).
(async () => {
  const send = (name, body) => fetch('http://127.0.0.1:8766/' + name, { method: 'POST', body });
  const { Game } = await import('/src/game/Game.ts');
  const TX = await import('/src/game/textures.ts');
  const div = document.createElement('div');
  div.style.cssText = 'position:fixed;left:0;top:0;width:1280px;height:800px;z-index:-5;';
  document.body.appendChild(div);
  const cb = { onProgress() {}, onLock() {}, onPrompt() {}, onStats() {}, onLocation() {}, onHudToggle() {}, onAudio() {} };
  const g = new Game(div, cb, 'high', 0);
  await g.init();
  g.scene.updateMatrixWorld(true);

  // identify leaf atlases by a checksum of their pixels
  const sig = (data) => { let s = 0; for (let i = 0; i < data.length; i += 997) s = (s * 31 + data[i]) >>> 0; return s; };
  const leafSig = {};
  for (const k of ['broad', 'oak', 'needle', 'blossom', 'willow', 'shrub', 'ivy', 'fern']) leafSig[sig(TX.makeLeafTexture(k).image.data)] = k;
  const lin = (c) => (c ? [c.r, c.g, c.b] : null);

  const describe = (m) => {
    const d = { type: m.type };
    const key = m.customProgramCacheKey ? m.customProgramCacheKey() : '';
    if (key && key !== m.uuid && !/^[0-9a-f-]{36}$/.test(key)) d.key = key;
    if (m.isShaderMaterial) {
      const u = m.uniforms;
      if (u.tReflection) { d.kind = 'water'; d.sky_only = !!(m.defines && 'SKY_ONLY' in m.defines); }
      else if (u.tGlow) d.kind = 'mist';
      else if (/streak/.test(m.fragmentShader)) d.kind = 'waterfall';
      else if (/vH/.test(m.fragmentShader)) d.kind = 'city';
      else if (/clouds/.test(m.fragmentShader)) d.kind = 'sky';
      else d.kind = 'shader';
      return d;
    }
    for (const p of ['roughness', 'metalness', 'opacity', 'transparent', 'vertexColors', 'flatShading', 'emissiveIntensity', 'alphaTest', 'side', 'blending', 'depthWrite']) if (m[p] !== undefined) d[p] = m[p];
    d.color = lin(m.color);
    if (m.emissive) d.emissive = lin(m.emissive);
    if (m.map && m.map.image && m.map.image.data) d.map = leafSig[sig(m.map.image.data)] || (m.map.image.width === 128 ? 'glow' : 'tex' + m.map.image.width);
    return d;
  };

  const geos = new Map();
  let blobIndex = 0;
  const geoId = async (geo) => {
    if (geos.has(geo.uuid)) return geos.get(geo.uuid);
    const id = 'g' + geos.size;
    const parts = [], header = { attrs: {}, index: null, instanced: {}, instanceCount: geo.instanceCount ?? null };
    let off = 0;
    const add = (name, arr, itemSize, inst) => {
      const f = arr instanceof Float32Array ? arr : new Float32Array(arr);
      (inst ? header.instanced : header.attrs)[name] = { offset: off, count: f.length / itemSize, itemSize };
      parts.push(f); off += f.byteLength;
    };
    for (const [name, a] of Object.entries(geo.attributes)) {
      if (a.isInterleavedBufferAttribute) continue;
      add(name, a.array, a.itemSize, !!a.isInstancedBufferAttribute);
    }
    if (geo.index) {
      const idx = new Uint32Array(geo.index.array);
      header.index = { offset: off, count: idx.length };
      parts.push(idx); off += idx.byteLength;
    }
    const buf = new Uint8Array(off); let o = 0;
    for (const p of parts) { buf.set(new Uint8Array(p.buffer, p.byteOffset, p.byteLength), o); o += p.byteLength; }
    await send(id + '.bin', buf);
    geos.set(geo.uuid, { id, header });
    return { id, header };
  };

  const objects = [];
  const visit = async (o) => {
    if (o.isLOD) {
      const levels = [];
      for (const lv of o.levels) {
        const meshes = [];
        lv.object.updateMatrixWorld(true);
        const sub = [];
        lv.object.traverse((c) => { if (c.isMesh) sub.push(c); });
        for (const c of sub) { const gi = await geoId(c.geometry); meshes.push({ geo: gi.id, mat: describe(c.material), matrix: Array.from(c.matrixWorld.elements), cast: c.castShadow }); }
        levels.push({ distance: lv.distance, meshes });
      }
      objects.push({ lod: levels, name: o.name });
      return;
    }
    if (o.isMesh && o.visible !== false) {
      const gi = await geoId(o.geometry);
      const e = { geo: gi.id, mat: describe(o.material), matrix: Array.from(o.matrixWorld.elements), cast: o.castShadow, layers: o.layers.mask, name: o.name, order: o.renderOrder };
      if (o.isInstancedMesh) {
        const inst = new Float32Array(o.instanceMatrix.array.slice(0, o.count * 16));
        const iname = 'i' + (blobIndex++) + '.bin';
        await send(iname, inst);
        e.instances = { file: iname, count: o.count };
        if (o.instanceColor) { const cn = 'c' + (blobIndex++) + '.bin'; await send(cn, new Float32Array(o.instanceColor.array.slice(0, o.count * 3))); e.instances.colors = cn; }
      }
      objects.push(e);
    }
    for (const c of o.children) await visit(c);
  };
  for (const c of g.scene.children) await visit(c);

  const t = g.terrain;
  await send('terrain_heights.bin', t.heights);
  await send('terrain_splat.bin', t.splat);
  const sun = g.sun;
  const manifest = {
    objects, geometries: Object.fromEntries([...geos.values()].map((v) => [v.id, v.header])),
    sun: { color: lin(sun.color), intensity: sun.intensity, pos: sun.position.toArray(), target: sun.target.position.toArray() },
    grid: { x0: -160, z0: -210, size: 320, n: 400 },
    camera: { fov: g.camera.fov, near: g.camera.near, far: g.camera.far },
  };
  await send('scene.json', new TextEncoder().encode(JSON.stringify(manifest)));
  return { objects: objects.length, geometries: geos.size, blobs: blobIndex };
})()
