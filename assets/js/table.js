// Sortable, paginated tables: <table data-sortable data-page-size="10">.
// Each header becomes a sort button; labels come from the table's data-* attributes.
(function () {
  'use strict';

  function setup(table) {
    var tbody = table.tBodies[0];
    var rows = Array.prototype.slice.call(tbody.rows);
    var size = parseInt(table.getAttribute('data-page-size'), 10) || rows.length;
    var collator = new Intl.Collator(table.getAttribute('data-lang') || 'fr', { numeric: true, sensitivity: 'base' });
    var page = 0;
    var sortCol = -1;
    var ascending = true;

    var nav = document.createElement('nav');
    nav.className = 'snc-pager';
    nav.setAttribute('aria-label', table.getAttribute('data-page') || 'Page');
    var prev = document.createElement('button');
    var next = document.createElement('button');
    var status = document.createElement('span');
    prev.type = next.type = 'button';
    prev.textContent = '‹ ' + (table.getAttribute('data-prev') || 'Previous');
    next.textContent = (table.getAttribute('data-next') || 'Next') + ' ›';
    status.setAttribute('aria-live', 'polite');
    nav.appendChild(prev);
    nav.appendChild(status);
    nav.appendChild(next);
    table.parentNode.insertAdjacentElement('afterend', nav);

    function pages() { return Math.max(1, Math.ceil(rows.length / size)); }

    function render() {
      tbody.innerHTML = '';
      rows.slice(page * size, page * size + size).forEach(function (r) { tbody.appendChild(r); });
      status.textContent = (table.getAttribute('data-page') || 'Page') + ' ' + (page + 1) + ' ' +
        (table.getAttribute('data-of') || 'of') + ' ' + pages();
      prev.disabled = page === 0;
      next.disabled = page >= pages() - 1;
      nav.hidden = pages() < 2;
    }

    Array.prototype.forEach.call(table.tHead.rows[0].cells, function (th, col) {
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'snc-sort';
      btn.textContent = th.textContent;
      th.textContent = '';
      th.appendChild(btn);
      th.setAttribute('aria-sort', 'none');
      btn.addEventListener('click', function () {
        ascending = sortCol === col ? !ascending : true;
        sortCol = col;
        rows.sort(function (a, b) {
          var c = collator.compare(a.cells[col].textContent.trim(), b.cells[col].textContent.trim());
          return ascending ? c : -c;
        });
        Array.prototype.forEach.call(table.tHead.rows[0].cells, function (h) { h.setAttribute('aria-sort', 'none'); });
        th.setAttribute('aria-sort', ascending ? 'ascending' : 'descending');
        page = 0;
        render();
      });
    });

    prev.addEventListener('click', function () { if (page > 0) { page--; render(); } });
    next.addEventListener('click', function () { if (page < pages() - 1) { page++; render(); } });
    render();
  }

  Array.prototype.forEach.call(document.querySelectorAll('table[data-sortable]'), setup);
})();
