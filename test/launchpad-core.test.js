const test = require('node:test');
const assert = require('node:assert/strict');
const core = require('../launchpad-core.js');

test('normalizeQuery trims and lowercases', () => {
  assert.equal(core.normalizeQuery('  SAFARI  '), 'safari');
  assert.equal(core.normalizeQuery(''), '');
});

test('filterApps matches case-insensitively', () => {
  const apps = [
    { name: 'Safari' },
    { name: '系统设置' },
    { name: 'Photos' },
  ];

  assert.deepEqual(core.filterApps(apps, 'saf'), [{ name: 'Safari' }]);
  assert.deepEqual(core.filterApps(apps, '系统'), [{ name: '系统设置' }]);
  assert.deepEqual(core.filterApps(apps, ''), apps);
});

test('computePageSize returns stable sizes', () => {
  assert.equal(core.computePageSize(480, 900), 12);
  assert.equal(core.computePageSize(850, 820), 18);
  assert.equal(core.computePageSize(1200, 900), 24);
  assert.equal(core.computePageSize(1400, 900), 30);
});

test('clampPage keeps page in range', () => {
  assert.equal(core.clampPage(-2, 3), 0);
  assert.equal(core.clampPage(1, 3), 1);
  assert.equal(core.clampPage(99, 3), 2);
  assert.equal(core.clampPage(0, 0), 0);
});

test('paginateApps returns current page and items', () => {
  const apps = Array.from({ length: 11 }, (_, index) => ({ name: `App-${index}` }));
  const page1 = core.paginateApps(apps, 1, 5);
  const page3 = core.paginateApps(apps, 3, 5);

  assert.equal(page1.totalPages, 3);
  assert.equal(page1.currentPage, 1);
  assert.equal(page1.items.length, 5);
  assert.equal(page1.items[0].name, 'App-5');

  assert.equal(page3.currentPage, 2);
  assert.equal(page3.items.length, 1);
  assert.equal(page3.items[0].name, 'App-10');
});

test('paginateApps validates inputs', () => {
  assert.throws(() => core.paginateApps({}, 0, 10), /apps must be an array/);
  assert.throws(() => core.paginateApps([], 0, 0), /pageSize must be a positive integer/);
});
