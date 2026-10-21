// Mantener el respaldo visible cuando una ruta de póster no existe.
document.querySelectorAll('[data-poster]').forEach((imagen) => {
    const ocultar = () => { imagen.hidden = true; };
    imagen.addEventListener('error', ocultar);
    if (imagen.complete && imagen.naturalWidth === 0) ocultar();
});
