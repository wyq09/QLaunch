(function () {
  "use strict";

  var core = window.LaunchpadCore;
  if (!core) {
    throw new Error("LaunchpadCore is missing.");
  }

  var APPS = [
    { name: "访达", icon: "🗂️", tint: "rgba(178, 214, 255, 0.62)" },
    { name: "地图", icon: "🗺️", tint: "rgba(137, 230, 197, 0.58)" },
    { name: "照片", icon: "🌄", tint: "rgba(255, 214, 166, 0.66)" },
    { name: "日历", icon: "📅", tint: "rgba(255, 203, 198, 0.68)" },
    { name: "提醒事项", icon: "✅", tint: "rgba(178, 237, 214, 0.6)" },
    { name: "备忘录", icon: "📝", tint: "rgba(255, 241, 183, 0.66)" },
    { name: "邮件", icon: "✉️", tint: "rgba(177, 214, 255, 0.68)" },
    { name: "Safari", icon: "🧭", tint: "rgba(166, 237, 255, 0.66)" },
    { name: "信息", icon: "💬", tint: "rgba(167, 239, 183, 0.68)" },
    { name: "音乐", icon: "🎵", tint: "rgba(255, 195, 199, 0.66)" },
    { name: "播客", icon: "🎙️", tint: "rgba(255, 190, 173, 0.66)" },
    { name: "天气", icon: "⛅", tint: "rgba(176, 227, 255, 0.68)" },
    { name: "时钟", icon: "🕒", tint: "rgba(196, 219, 255, 0.62)" },
    { name: "家庭", icon: "🏠", tint: "rgba(190, 239, 222, 0.62)" },
    { name: "App Store", icon: "🛍️", tint: "rgba(180, 219, 255, 0.64)" },
    { name: "终端", icon: "💻", tint: "rgba(166, 198, 235, 0.62)" },
    { name: "系统设置", icon: "⚙️", tint: "rgba(204, 220, 236, 0.56)" },
    { name: "键盘侠", icon: "⌨️", tint: "rgba(214, 229, 246, 0.54)" },
    { name: "相机", icon: "📷", tint: "rgba(208, 224, 245, 0.6)" },
    { name: "计算器", icon: "🧮", tint: "rgba(247, 223, 170, 0.62)" },
    { name: "图书", icon: "📚", tint: "rgba(255, 217, 167, 0.66)" },
    { name: "股票", icon: "📈", tint: "rgba(194, 237, 213, 0.62)" },
    { name: "健康", icon: "🫀", tint: "rgba(255, 191, 204, 0.66)" },
    { name: "健身", icon: "🏃", tint: "rgba(186, 234, 224, 0.62)" },
    { name: "翻译", icon: "🌐", tint: "rgba(188, 222, 255, 0.62)" },
    { name: "快捷指令", icon: "⚡", tint: "rgba(210, 210, 255, 0.66)" },
    { name: "文件", icon: "📁", tint: "rgba(184, 224, 255, 0.62)" },
    { name: "预览", icon: "🖼️", tint: "rgba(201, 234, 255, 0.58)" },
    { name: "FaceTime", icon: "📹", tint: "rgba(184, 245, 214, 0.62)" },
    { name: "Keynote", icon: "📊", tint: "rgba(255, 209, 182, 0.62)" },
    { name: "Pages", icon: "📄", tint: "rgba(193, 223, 255, 0.62)" },
    { name: "Numbers", icon: "📉", tint: "rgba(198, 241, 211, 0.62)" },
    { name: "TV", icon: "📺", tint: "rgba(193, 212, 255, 0.6)" },
    { name: "新闻", icon: "🗞️", tint: "rgba(226, 235, 255, 0.58)" },
    { name: "通讯录", icon: "👤", tint: "rgba(214, 231, 245, 0.58)" },
    { name: "无边记", icon: "🧠", tint: "rgba(208, 240, 231, 0.58)" },
    { name: "开发者", icon: "🛠️", tint: "rgba(200, 219, 255, 0.62)" },
    { name: "下载", icon: "⬇️", tint: "rgba(198, 229, 255, 0.62)" },
    { name: "游戏中心", icon: "🎮", tint: "rgba(202, 232, 255, 0.62)" },
    { name: "截图", icon: "📸", tint: "rgba(219, 238, 255, 0.56)" },
    { name: "钱包", icon: "💳", tint: "rgba(205, 217, 255, 0.58)" },
    { name: "密码", icon: "🔐", tint: "rgba(204, 228, 255, 0.58)" },
  ];

  var state = {
    query: "",
    page: 0,
    editMode: false,
  };

  var shell = document.getElementById("launchpad-shell");
  var grid = document.getElementById("app-grid");
  var dotNav = document.getElementById("dot-nav");
  var searchInput = document.getElementById("search-input");
  var modeToggle = document.getElementById("mode-toggle");
  var cardTemplate = document.getElementById("app-card-template");

  function getPageSize() {
    return core.computePageSize(window.innerWidth, window.innerHeight);
  }

  function getFilteredApps() {
    return core.filterApps(APPS, state.query);
  }

  function handleOpenApp(app) {
    var baseTitle = app.name + "（示例）";
    document.title = baseTitle;

    var iconNode = document.createElement("span");
    iconNode.textContent = app.icon;
    iconNode.style.marginRight = "8px";

    var toast = document.createElement("div");
    toast.className = "launch-toast";
    toast.setAttribute("role", "status");
    toast.append(iconNode, document.createTextNode("正在打开 " + app.name));

    Object.assign(toast.style, {
      position: "absolute",
      left: "50%",
      bottom: "74px",
      transform: "translateX(-50%)",
      padding: "10px 16px",
      borderRadius: "999px",
      background: "linear-gradient(145deg, rgba(245, 251, 255, 0.82), rgba(230, 244, 255, 0.36))",
      border: "1px solid rgba(216, 238, 255, 0.8)",
      color: "#10283d",
      fontSize: "0.88rem",
      boxShadow: "0 12px 20px rgba(10, 29, 52, 0.26)",
      backdropFilter: "blur(10px)",
      zIndex: "6",
    });

    shell.appendChild(toast);

    setTimeout(function () {
      toast.remove();
    }, 1200);
  }

  function renderDots(totalPages) {
    dotNav.innerHTML = "";

    for (var i = 0; i < totalPages; i += 1) {
      var dot = document.createElement("button");
      dot.type = "button";
      dot.setAttribute("aria-label", "第 " + (i + 1) + " 页");
      dot.setAttribute("aria-current", i === state.page ? "true" : "false");
      dot.dataset.page = String(i);
      dot.addEventListener("click", function (event) {
        var target = event.currentTarget;
        state.page = Number(target.dataset.page) || 0;
        render();
      });
      dotNav.appendChild(dot);
    }
  }

  function renderGrid(apps) {
    grid.innerHTML = "";

    if (!apps.length) {
      var emptyNode = document.createElement("p");
      emptyNode.className = "app-grid-empty";
      emptyNode.textContent = "没有匹配的 App";
      grid.appendChild(emptyNode);
      return;
    }

    var fragment = document.createDocumentFragment();
    apps.forEach(function (app) {
      var card = cardTemplate.content.firstElementChild.cloneNode(true);
      var icon = card.querySelector(".app-icon");
      var label = card.querySelector(".app-label");

      card.setAttribute("aria-label", "打开 " + app.name);
      card.addEventListener("click", function () {
        handleOpenApp(app);
      });

      if (state.editMode) {
        card.classList.add("is-jiggling");
      }

      icon.textContent = app.icon;
      icon.style.setProperty("--app-tint", app.tint);
      label.textContent = app.name;
      fragment.appendChild(card);
    });

    grid.appendChild(fragment);
  }

  function render() {
    var filtered = getFilteredApps();
    var pagination = core.paginateApps(filtered, state.page, getPageSize());

    state.page = pagination.currentPage;
    renderGrid(pagination.items);
    renderDots(pagination.totalPages);
  }

  function wireEvents() {
    searchInput.addEventListener("input", function (event) {
      state.query = event.target.value;
      state.page = 0;
      render();
    });

    modeToggle.addEventListener("click", function () {
      state.editMode = !state.editMode;
      modeToggle.setAttribute("aria-pressed", state.editMode ? "true" : "false");
      modeToggle.textContent = state.editMode ? "完成" : "编辑模式";
      render();
    });

    window.addEventListener("resize", render);

    window.addEventListener("keydown", function (event) {
      if (event.key === "ArrowRight") {
        state.page += 1;
        render();
      }

      if (event.key === "ArrowLeft") {
        state.page -= 1;
        render();
      }
    });

    window.addEventListener("pointermove", function (event) {
      var rect = shell.getBoundingClientRect();
      var relativeX = ((event.clientX - rect.left) / rect.width) * 100;
      var relativeY = ((event.clientY - rect.top) / rect.height) * 100;

      shell.style.setProperty("--pointer-x", relativeX.toFixed(2) + "%");
      shell.style.setProperty("--pointer-y", relativeY.toFixed(2) + "%");
    });
  }

  wireEvents();
  render();
})();
