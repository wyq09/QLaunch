(function (globalObject) {
  "use strict";

  function normalizeQuery(query) {
    return String(query || "")
      .trim()
      .toLowerCase();
  }

  function filterApps(apps, query) {
    const normalized = normalizeQuery(query);
    if (!normalized) {
      return apps.slice();
    }

    return apps.filter(function (app) {
      return String(app.name || "")
        .toLowerCase()
        .includes(normalized);
    });
  }

  function computePageSize(width, height) {
    if (width <= 520) {
      return 12;
    }

    if (width <= 900 || height <= 700) {
      return 18;
    }

    if (width <= 1250 || height <= 820) {
      return 24;
    }

    return 30;
  }

  function clampPage(page, totalPages) {
    if (!totalPages || totalPages < 1) {
      return 0;
    }

    return Math.min(Math.max(page, 0), totalPages - 1);
  }

  function paginateApps(apps, page, pageSize) {
    if (!Array.isArray(apps)) {
      throw new TypeError("apps must be an array");
    }

    if (!Number.isInteger(pageSize) || pageSize < 1) {
      throw new RangeError("pageSize must be a positive integer");
    }

    var totalPages = Math.max(1, Math.ceil(apps.length / pageSize));
    var currentPage = clampPage(Math.trunc(Number(page) || 0), totalPages);
    var startIndex = currentPage * pageSize;
    var endIndex = startIndex + pageSize;

    return {
      totalPages: totalPages,
      currentPage: currentPage,
      items: apps.slice(startIndex, endIndex),
    };
  }

  var api = {
    normalizeQuery: normalizeQuery,
    filterApps: filterApps,
    computePageSize: computePageSize,
    clampPage: clampPage,
    paginateApps: paginateApps,
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  }

  globalObject.LaunchpadCore = api;
})(typeof globalThis !== "undefined" ? globalThis : window);
