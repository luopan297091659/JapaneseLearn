(() => {
  const canvas = document.createElement('canvas');
  const context = canvas.getContext('2d');
  if (!context) return;

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const colors = [
    [96, 165, 250],
    [167, 139, 250],
    [244, 114, 182],
  ];
  let width = 0;
  let height = 0;
  let particles = [];
  let mouse = { x: -999, y: -999 };
  let animationFrame = 0;
  const linkDistance = 130;
  const mouseDistance = 150;

  canvas.id = 'site-particles-canvas';
  canvas.setAttribute('aria-hidden', 'true');
  document.body.prepend(canvas);

  function resize() {
    const pixelRatio = Math.min(window.devicePixelRatio || 1, 2);
    width = window.innerWidth;
    height = window.innerHeight;
    canvas.width = Math.round(width * pixelRatio);
    canvas.height = Math.round(height * pixelRatio);
    context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);

    const count = Math.min(110, Math.max(42, Math.round(width * height / 15000)));
    particles = Array.from({ length: count }, () => {
      const color = colors[Math.floor(Math.random() * colors.length)];
      return {
        x: Math.random() * width,
        y: Math.random() * height,
        vx: (Math.random() - .5) * .55,
        vy: (Math.random() - .5) * .55,
        radius: Math.random() * 1.3 + .8,
        color,
        alpha: Math.random() * .28 + .24,
      };
    });

    if (reducedMotion) draw();
  }

  function draw() {
    context.clearRect(0, 0, width, height);

    for (const particle of particles) {
      if (!reducedMotion) {
        particle.x += particle.vx;
        particle.y += particle.vy;
        if (particle.x < 0 || particle.x > width) particle.vx *= -1;
        if (particle.y < 0 || particle.y > height) particle.vy *= -1;

        const dx = particle.x - mouse.x;
        const dy = particle.y - mouse.y;
        const distance = Math.hypot(dx, dy);
        if (distance < mouseDistance && distance > 0) {
          const force = (mouseDistance - distance) / mouseDistance * .018;
          particle.vx += dx / distance * force;
          particle.vy += dy / distance * force;
        }

        const speed = Math.hypot(particle.vx, particle.vy);
        if (speed > 1.25) {
          particle.vx *= 1.25 / speed;
          particle.vy *= 1.25 / speed;
        }
      }

      context.beginPath();
      context.arc(particle.x, particle.y, particle.radius, 0, Math.PI * 2);
      context.fillStyle = `rgba(${particle.color.join(',')},${particle.alpha})`;
      context.fill();
    }

    for (let i = 0; i < particles.length; i++) {
      for (let j = i + 1; j < particles.length; j++) {
        const first = particles[i];
        const second = particles[j];
        const distance = Math.hypot(first.x - second.x, first.y - second.y);
        if (distance >= linkDistance) continue;

        context.beginPath();
        context.moveTo(first.x, first.y);
        context.lineTo(second.x, second.y);
        context.strokeStyle = `rgba(110,125,190,${.12 * (1 - distance / linkDistance)})`;
        context.stroke();
      }
    }

    if (!reducedMotion) animationFrame = window.requestAnimationFrame(draw);
  }

  function handlePointerMove(event) {
    mouse = { x: event.clientX, y: event.clientY };
  }

  window.addEventListener('pointermove', handlePointerMove, { passive: true });
  window.addEventListener('pointerout', event => {
    if (!event.relatedTarget) mouse = { x: -999, y: -999 };
  });
  window.addEventListener('resize', () => {
    window.cancelAnimationFrame(animationFrame);
    resize();
    if (!reducedMotion && !document.hidden) draw();
  }, { passive: true });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      window.cancelAnimationFrame(animationFrame);
    } else if (!reducedMotion) {
      draw();
    }
  });

  resize();
  if (!reducedMotion) draw();
})();
