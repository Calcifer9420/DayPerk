// 与 App 的 ClockOutConfetti 共用参数、随机种子、运动方程和纸片绘制方式。
// 浏览器只负责预览；不引入第三方粒子库，也不修改原生 App。
(function (scope) {
  const colors = [[1, .76, .23], [1, .34, .49], [.25, .82, .94], [.58, .44, .96], [.35, .86, .63], [1, .91, .61]];
  function random(index, salt) {
    const u64 = value => BigInt.asUintN(64, value);
    let value = u64(BigInt(index + 1) * 0x9E3779B97F4A7C15n + BigInt(salt + 1) * 0xBF58476D1CE4E5B9n);
    value = u64((value ^ (value >> 30n)) * 0xBF58476D1CE4E5B9n);
    value = u64((value ^ (value >> 27n)) * 0x94D049BB133111EBn);
    return Number((value ^ (value >> 31n)) >> 11n) / 2 ** 53;
  }
  const particles = Array.from({length: 138}, (_, index) => {
    const fromTop = index >= 80;
    const ribbon = fromTop ? index % 2 === 0 : index % 5 === 0;
    return {index, fromTop, ribbon, left: index % 2 === 0,
      values: Array.from({length: 11}, (_, salt) => random(index, salt))};
  });
  function pose(particle, width, height, elapsed) {
    const {fromTop, ribbon, left, values: r} = particle;
    const age = elapsed - (fromTop ? .12 + r[0] * 1.1 : r[0] * .35);
    if (age < 0) return null;
    const phase = r[1] * Math.PI * 2;
    const originX = fromTop ? width * (.04 + r[2] * .92) : (left ? -8 : width + 8);
    const originY = fromTop ? -60 - r[3] * 40 : height * (.57 + r[3] * .12);
    const velocityX = fromTop ? -20 + r[4] * 40 : (left ? 1 : -1) * (160 + r[4] * 210);
    const velocityY = fromTop ? 25 + r[5] * 50 : -250 - r[5] * 200;
    const drag = fromTop ? .9 : 1.15;
    const terminal = ribbon ? 125 + r[6] * 50 : 175 + r[6] * 70;
    const flight = (1 - Math.exp(-drag * age)) / drag;
    const sway = (Math.sin(age * (2 + r[7] * 2) + phase) - Math.sin(phase)) * (ribbon ? 16 : 10);
    return {x: originX + velocityX * flight + sway,
      y: originY + terminal * age + (velocityY - terminal) * flight,
      rotation: phase + age * (ribbon ? .7 : 2.1) * (left ? 1 : -1),
      flip: Math.cos(phase + age * (ribbon ? 2.2 : 5)), phase: phase + age * 2};
  }
  const rgba = (color, alpha = 1) => `rgba(${color.map(v => Math.round(v * 255)).join(',')},${alpha})`;
  function fill(context, path, color, start, end, shades) {
    const gradient = context.createLinearGradient(...start, ...end);
    shades.forEach(([shade, alpha], i) => gradient.addColorStop(i / (shades.length - 1), rgba(shade || color, alpha)));
    context.fillStyle = gradient;
    context.fill(path);
  }
  function drawRibbon(context, color, length, width, phase) {
    const center = y => Math.sin(y / length * Math.PI * 2.3 + phase) * 4.5;
    const half = y => width / 2 * (.35 + Math.abs(Math.cos(y / length * Math.PI * 2.3 + phase)) * .65);
    for (let segment = 0; segment < 12; segment++) {
      const y0 = -length / 2 + length * segment / 12;
      const y1 = -length / 2 + length * (segment + 1) / 12;
      const middle = (y0 + y1) / 2;
      const strip = new Path2D();
      strip.moveTo(center(y0) - half(y0), y0);
      strip.quadraticCurveTo(center(middle) - half(middle), middle, center(y1) - half(y1), y1);
      strip.lineTo(center(y1) + half(y1), y1);
      strip.quadraticCurveTo(center(middle) + half(middle), middle, center(y0) + half(y0), y0);
      strip.closePath();
      const fold = Math.cos(middle / length * Math.PI * 2.3 + phase);
      fill(context, strip, color, [-6, middle], [6, middle], fold > 0 ? [[null, 1], [null, .8], [[1, 1, 1], .9]] : [[null, .55], [null, 1], [null, .65]]);
    }
  }
  function draw(canvas, elapsed) {
    const context = canvas.getContext('2d');
    context.clearRect(0, 0, canvas.width, canvas.height);
    if (elapsed < 0) return;
    // 原生浮窗宽 430 pt，按预览像素比例绘制，速度与纸片大小一起保持一致。
    const scale = canvas.width / 430;
    const width = 430, height = canvas.height / scale;
    context.save();
    context.scale(scale, scale);
    for (const particle of particles) {
      const position = pose(particle, width, height, elapsed);
      if (!position || position.y > height + 100) continue;
      const {ribbon, values: r} = particle;
      context.save();
      context.translate(position.x, position.y);
      context.rotate(position.rotation);
      context.scale(Math.max(.16, Math.abs(position.flip)), 1);
      const color = colors[Math.floor(r[8] * colors.length) % colors.length];
      if (ribbon) {
        drawRibbon(context, color, 40 + r[9] * 34, 3.5 + r[10] * 2, position.phase);
      } else {
        const w = 6 + r[9] * 5, h = 9 + r[10] * 7;
        const paper = new Path2D();
        paper.moveTo(-w / 2, -h / 2);
        paper.quadraticCurveTo(0, -h / 2 - 1.5, w / 2, -h / 2 + 1);
        paper.lineTo(w / 2 - 1, h / 2);
        paper.quadraticCurveTo(0, h / 2 + 1.5, -w / 2, h / 2 - 1);
        paper.closePath();
        fill(context, paper, color, [-w, -h], [w, h], [[null, .7], [null, 1], [[1, 1, 1], .85], [null, 1]]);
        context.strokeStyle = rgba(color, position.flip > 0 ? .55 : .9);
        context.lineWidth = .35;
        context.stroke(paper);
      }
      context.restore();
    }
    context.restore();
  }
  scope.ClockOutConfettiPreview = {random, particles, pose, draw};
})(globalThis);
