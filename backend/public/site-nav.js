(() => {
  const button = document.getElementById('mobileMenuButton');
  const panel = document.getElementById('mobileNavPanel');
  const backdrop = document.getElementById('mobileNavBackdrop');

  if (!button || !panel || !backdrop) return;

  const setOpen = (open) => {
    button.setAttribute('aria-expanded', String(open));
    panel.classList.toggle('open', open);
    backdrop.classList.toggle('open', open);
    document.body.classList.toggle('mobile-menu-open', open);
  };

  button.addEventListener('click', () => {
    setOpen(button.getAttribute('aria-expanded') !== 'true');
  });
  backdrop.addEventListener('click', () => setOpen(false));
  panel.addEventListener('click', (event) => {
    if (event.target.closest('a')) setOpen(false);
  });
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') setOpen(false);
  });
  window.addEventListener('resize', () => {
    if (window.innerWidth > 900) setOpen(false);
  });
})();
