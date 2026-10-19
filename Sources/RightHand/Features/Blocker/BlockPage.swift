import Foundation

/// The page a blocked tab is switched to: "instagram.com is blocked — back to focus".
/// It's a local HTML file; the site, original address and focus end time are passed in the URL.
enum BlockPage {
    private static let file = AppPaths.support.appending(path: "blocked.html")

    /// Writes the page to disk (called at launch, so updates to the HTML take effect).
    static func install() {
        try? html.write(to: file, atomically: true, encoding: .utf8)
    }

    static func url(blocking blocked: URL, focusEnds: Date) -> URL {
        var site = blocked.host() ?? blocked.absoluteString
        if site.hasPrefix("www.") { site.removeFirst(4) }
        var components = URLComponents(url: file, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "site", value: site),
            URLQueryItem(name: "url", value: blocked.absoluteString),
            URLQueryItem(name: "until", value: String(Int(focusEnds.timeIntervalSince1970 * 1000))),
            URLQueryItem(name: "lang", value: AppLanguage.current),
        ]
        return components.url!
    }

    private static let html = """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Blocked · RightHand</title>
    <style>
      :root { color-scheme: dark; }
      * { box-sizing: border-box; }
      body {
        margin: 0; min-height: 100vh; display: grid; place-items: center;
        background: radial-gradient(circle at 50% 30%, #1d2b2f 0%, #0b0d0f 70%);
        color: #f2f2f2; font: 17px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
        text-align: center; padding: 24px;
      }
      .icon { font-size: 56px; margin-bottom: 8px; }
      h1 { font: 600 34px/1.2 "SF Pro Rounded", -apple-system, sans-serif; margin: 0 0 8px; }
      .site { color: #ff9f43; }
      p { color: #a9b1b6; margin: 0 0 28px; }
      .timer {
        display: inline-block; padding: 14px 26px; border-radius: 999px;
        background: rgba(255,255,255,.07); font: 600 28px "SF Mono", ui-monospace, monospace;
        font-variant-numeric: tabular-nums; letter-spacing: 1px;
      }
      .label { display: block; margin-top: 10px; font-size: 14px; color: #7d878d; }
      a { color: #4fd1c5; }
      .done { display: none; }
    </style>
    </head>
    <body>
    <main>
      <div class="icon">✋</div>
      <h1 id="title"></h1>
      <p id="subtitle"></p>
      <div class="focus">
        <span class="timer" id="timer">--:--</span>
        <span class="label" id="until"></span>
      </div>
      <div class="done" id="done">
        <p><span id="over"></span> <a id="link" href="#"></a></p>
      </div>
    </main>
    <script>
      const q = new URLSearchParams(location.search);
      const texts = {
        en: ["is blocked", "You're in a focus session. It'll be here when you're done.", "until the focus session ends", "Focus session is over.", "Open"],
        uk: ["заблоковано", "Зараз сесія фокусу. Сайт нікуди не дінеться.", "до кінця сесії фокусу", "Сесію фокусу завершено.", "Відкрити"],
        cs: ["je zablokovaný", "Právě se soustředíš. Web tu bude i potom.", "do konce soustředění", "Soustředění skončilo.", "Otevřít"],
        ru: ["заблокирован", "Сейчас сессия фокуса. Сайт никуда не денется.", "до конца сессии фокуса", "Сессия фокуса завершена.", "Открыть"],
      };
      const t = texts[q.get("lang")] || texts.en;
      const site = q.get("site") || "";
      const until = Number(q.get("until") || 0);
      const name = document.createElement("span");
      name.className = "site";
      name.textContent = site;
      document.getElementById("title").append(name, " " + t[0]);
      document.getElementById("subtitle").textContent = t[1];
      document.getElementById("until").textContent = t[2];
      document.getElementById("over").textContent = t[3];
      document.getElementById("link").textContent = t[4] + " " + site;
      document.getElementById("link").href = q.get("url") || "#";
      function tick() {
        const left = Math.max(0, Math.round((until - Date.now()) / 1000));
        const m = String(Math.floor(left / 60)).padStart(2, "0"), s = String(left % 60).padStart(2, "0");
        document.getElementById("timer").textContent = m + ":" + s;
        if (left === 0) {
          document.querySelector(".focus").style.display = "none";
          document.getElementById("done").style.display = "block";
          return;
        }
        setTimeout(tick, 1000);
      }
      tick();
    </script>
    </body>
    </html>
    """
}
