function clamp(value, min, max){
  return Math.min(Math.max(value, min), max);
}

(function(){
  "use strict";

  function ready(fn){
    if(document.readyState === "loading"){
      document.addEventListener("DOMContentLoaded", fn, { once:true });
      return;
    }
    fn();
  }

  window.getUrlParams = window.getUrlParams || function getUrlParams(){
    return Object.fromEntries(new URLSearchParams(window.location.search));
  };

  ready(function(){
    var burger = document.getElementById("burger");
    var drawer = document.getElementById("drawer");
    var overlay = document.getElementById("drawerOverlay");
    var closeBtn = document.getElementById("drawerClose");
    if(!burger || !drawer || !overlay || !closeBtn) return;

    function open(){
      drawer.classList.add("open");
      overlay.classList.add("open");
      drawer.setAttribute("aria-hidden", "false");
      burger.setAttribute("aria-expanded", "true");
    }

    function close(){
      drawer.classList.remove("open");
      overlay.classList.remove("open");
      drawer.setAttribute("aria-hidden", "true");
      burger.setAttribute("aria-expanded", "false");
    }

    burger.addEventListener("click", open);
    overlay.addEventListener("click", close);
    closeBtn.addEventListener("click", close);
    drawer.querySelectorAll("a").forEach(function(link){
      link.addEventListener("click", close);
    });
    document.addEventListener("keydown", function(e){
      if(e.key === "Escape") close();
    });
  });
})();
