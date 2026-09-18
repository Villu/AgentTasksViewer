                                                                        # -*- awk -*-
# Reads a markdown task file, writes an HTML board. Called by tasks-board.
#
# The four states are the same ones tasks-ready computes, deliberately: a task
# is ready only when nobody holds it, nothing blocks it, and no path in its
# Files is held by a task somebody has claimed. Two implementations of that rule
# would drift, so if you change one, change the other in the same commit.
#
# -v heading=TEXT heading on the page (title is already the per-task array).
# -v source=TEXT  what this render was made from, shown on the page. "the task
#                 file" for a working copy, "origin/main:TASKS.md" for a ref. A
#                 board of someone else's branch that looks like your checkout is
#                 the whole reason this is displayed rather than assumed.
# -v label=TEXT   how to invoke this tool, for the footer. A vendored copy is
#                 reached by another name, and a footer naming a command the
#                 reader does not have is worse than no footer.
# -v refresh=N    how often the page re-checks the stamp, for --watch/--serve.
#                 0 means a one-shot render, which says "snapshot" and claims
#                 nothing about being current.
# -v stamp=NAME   sidecar file holding the render's epoch, fetched by the page to
#                 verify it is showing the current render. Relative to the html.
# -v epoch=N      this render's epoch seconds. Must equal what is in the stamp
#                 file, or the page reloads forever.

function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }
function strip(s) { gsub(/\r/, "", s); return s }

# Escape first, then the two markdown forms this file actually uses. Done by
# hand because POSIX awk has no capture groups in gsub.
function md(s,   out, open) {
    s = esc(s)
    out = ""; open = 0
    while (match(s, /\*\*/)) {
        out = out substr(s, 1, RSTART - 1) (open ? "</strong>" : "<strong>")
        open = !open
        s = substr(s, RSTART + 2)
    }
    s = out s
    if (open) s = s "</strong>"
    out = ""; open = 0
    while (match(s, /`/)) {
        out = out substr(s, 1, RSTART - 1) (open ? "</code>" : "<code>")
        open = !open
        s = substr(s, RSTART + 1)
    }
    s = out s
    if (open) s = s "</code>"
    return s
}

function addfield(i, label, text) {
    fn[i]++
    flab[i, fn[i]] = label
    ftxt[i, fn[i]] = text
}

/^## P[0-9]/          { prio = strip($2); next }
/^- \[[ x]\] /        {
    n++; prio_of[n] = prio
    line = strip($0); actor[n] = ""
    if (match(line, /\(@[^)]+\)[ \t]*$/)) {
        actor[n] = substr(line, RSTART + 2, RLENGTH - 3)
        sub(/[ \t]*\(@[^)]+\)[ \t]*$/, "", line)
    }
    title[n] = substr(line, 7)
    next
}
/\*\*ID\*\*:/         { id[n] = strip($NF); byid[id[n]] = n; next }
/\*\*Files\*\*:/      { files[n] = strip($0)
                        t = strip($0); sub(/^.*\*\*Files\*\*:[ \t]*/, "", t); addfield(n, "Files", t); next }
/\*\*Details\*\*:/    { t = strip($0); sub(/^.*\*\*Details\*\*:[ \t]*/, "", t);    addfield(n, "Details", t); next }
/\*\*Acceptance\*\*:/ { t = strip($0); sub(/^.*\*\*Acceptance\*\*:[ \t]*/, "", t); addfield(n, "Acceptance", t); next }
/\*\*Note\*\*:/       { t = strip($0); sub(/^.*\*\*Note\*\*:[ \t]*/, "", t);       addfield(n, "Note", t); next }
/\*\*Blocked by\*\*:/ { t = strip($0); sub(/^.*\*\*Blocked by\*\*:[ \t]*/, "", t); dep[n] = t; addfield(n, "Blocked by", t); next }
/\*\*Blocked\*\*:/    { t = strip($0); sub(/^.*\*\*Blocked\*\*:[ \t]*/, "", t);    blk[n] = t; addfield(n, "Blocked", t); next }
/\*\*Tags\*\*:/       { t = strip($0); sub(/^.*\*\*Tags\*\*:[ \t]*/, "", t);       tags[n] = t; next }

END {
    for (i = 1; i <= n; i++) {
        if (actor[i] == "") continue
        f = files[i]
        while (match(f, /`[^`]+`/)) {
            held[substr(f, RSTART + 1, RLENGTH - 2)] = id[i]
            f = substr(f, RSTART + RLENGTH)
        }
    }

    for (i = 1; i <= n; i++) {
        state[i] = "ready"; why[i] = ""
        if (actor[i] != "")    { state[i] = "held";    why[i] = "@" actor[i] }
        else if (blk[i] != "") { state[i] = "blocked"; why[i] = blk[i] }
        else {
            split(dep[i], d, /,[ \t]*/)
            for (k in d) {
                t = d[k]; gsub(/^[ \t]+|[ \t]+$/, "", t)
                if (t != "" && (t in byid)) {
                    state[i] = "blocked"
                    why[i] = why[i] (why[i] ? ", " : "waits on ") t
                }
            }
            if (state[i] == "ready") {
                f = files[i]
                while (match(f, /`[^`]+`/)) {
                    p = substr(f, RSTART + 1, RLENGTH - 2)
                    if (p in held) { state[i] = "contested"; why[i] = "file " p " held by " held[p] }
                    f = substr(f, RSTART + RLENGTH)
                }
            }
        }
        cnt[state[i]]++; pc[prio_of[i]]++; pcs[prio_of[i] "|" state[i]]++
    }

    print "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
    print "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
    print "<title>" heading "</title><style>"
    print ":root{--bg:#fbfaf9;--fg:#1a1a18;--dim:#6b6a66;--card:#fff;--line:#e5e3df;--bar:#edebe7;"
    print "--ready:#2e7d5b;--blocked:#b06c1d;--held:#2b6cb0;--contested:#a33a3a;--kbd:#f2f0ec}"
    print "@media(prefers-color-scheme:dark){:root:not([data-theme=\"light\"]){"
    print "--bg:#171614;--fg:#eceae6;--dim:#9a9791;--card:#201f1c;--line:#32302c;--bar:#2a2825;"
    print "--ready:#5fbf90;--blocked:#d9a05b;--held:#7aaede;--contested:#e08585;--kbd:#2a2825}}"
    print ":root[data-theme=\"dark\"]{--bg:#171614;--fg:#eceae6;--dim:#9a9791;--card:#201f1c;"
    print "--line:#32302c;--bar:#2a2825;--ready:#5fbf90;--blocked:#d9a05b;--held:#7aaede;"
    print "--contested:#e08585;--kbd:#2a2825}"
    print "*{box-sizing:border-box}"
    print "body{margin:0;background:var(--bg);color:var(--fg);padding:32px 16px 64px;"
    print "font:15px/1.55 ui-sans-serif,-apple-system,\"Segoe UI\",system-ui,sans-serif}"
    print ".w{max-width:940px;margin:0 auto}"
    print "h1{font-size:22px;margin:0 0 3px;letter-spacing:-.01em}"
    print ".sub{color:var(--dim);font-size:13px;margin-bottom:26px}"
    print ".live{color:var(--ready);font-weight:600}"
    print ".snap{color:var(--dim);font-weight:600}"
    print ".stale{color:var(--contested);font-weight:600}"
    print ".stats{display:flex;flex-wrap:wrap;gap:10px;margin-bottom:24px}"
    print ".stat{flex:1 1 130px;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px}"
    print ".stat b{display:block;font-size:26px;line-height:1.15;font-variant-numeric:tabular-nums}"
    print ".stat span{font-size:11.5px;color:var(--dim);text-transform:uppercase;letter-spacing:.06em}"
    print ".prow{display:flex;align-items:center;gap:10px;margin:7px 0}"
    print ".plab{width:26px;font-size:12px;color:var(--dim);font-weight:600}"
    print ".track{flex:1;height:9px;background:var(--bar);border-radius:5px;overflow:hidden;display:flex}"
    print ".seg{height:100%}"
    print ".pn{width:32px;text-align:right;font-size:12px;color:var(--dim);font-variant-numeric:tabular-nums}"
    print "h2{font-size:11.5px;text-transform:uppercase;letter-spacing:.07em;color:var(--dim);margin:28px 0 10px;font-weight:600}"
    print "details.card{background:var(--card);border:1px solid var(--line);border-left:3px solid var(--line);"
    print "border-radius:8px;margin-bottom:7px}"
    print "details.card>summary{padding:11px 14px;cursor:pointer;list-style:none;border-radius:8px}"
    print "details.card>summary::-webkit-details-marker{display:none}"
    print "details.card>summary:hover{background:var(--bar)}"
    print "details.card[open]>summary{border-bottom:1px solid var(--line);border-radius:8px 8px 0 0}"
    print ".card.ready{border-left-color:var(--ready)}"
    print ".card.blocked{border-left-color:var(--blocked)}"
    print ".card.held{border-left-color:var(--held)}"
    print ".card.contested{border-left-color:var(--contested)}"
    print ".ct{font-weight:550;margin-bottom:3px}"
    print ".cm{font-size:12.5px;color:var(--dim);display:flex;flex-wrap:wrap;gap:9px;align-items:baseline}"
    print ".id{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11.5px}"
    print ".p{font-weight:650}.why{font-style:italic}"
    print ".body{padding:12px 14px 14px}"
    print ".f{margin-bottom:11px}.f:last-child{margin-bottom:0}"
    print ".fl{font-size:10.5px;text-transform:uppercase;letter-spacing:.07em;color:var(--dim);"
    print "font-weight:650;margin-bottom:2px}"
    print ".fv{font-size:13.5px;line-height:1.6}"
    print "code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.88em;"
    print "background:var(--kbd);padding:1px 4px;border-radius:3px}"
    print "footer{margin-top:34px;padding-top:14px;border-top:1px solid var(--line);color:var(--dim);font-size:12px}"
    print "</style></head><body><div class=\"w\">"

    printf "<h1>%s</h1>\n<div class=\"sub\">%d tasks &middot; generated %s", heading, n, generated
    if (refresh + 0 > 0)
        printf " &middot; <span class=\"live\" id=\"freshness\">checking every %ds</span>", refresh
    else
        printf " &middot; <span class=\"snap\" id=\"freshness\">snapshot</span>"
    printf " &middot; a view of %s, which is the only source of truth</div>\n", esc(source)

    print "<div class=\"stats\">"
    printf "<div class=\"stat\"><b style=\"color:var(--ready)\">%d</b><span>ready</span></div>\n", cnt["ready"] + 0
    printf "<div class=\"stat\"><b style=\"color:var(--held)\">%d</b><span>in progress</span></div>\n", cnt["held"] + 0
    printf "<div class=\"stat\"><b style=\"color:var(--blocked)\">%d</b><span>blocked</span></div>\n", cnt["blocked"] + 0
    printf "<div class=\"stat\"><b style=\"color:var(--contested)\">%d</b><span>file contested</span></div>\n", cnt["contested"] + 0
    print "</div>"

    split("ready held blocked contested", order, " ")
    for (p = 0; p <= 3; p++) {
        k = "P" p
        if (!(k in pc)) continue
        printf "<div class=\"prow\"><div class=\"plab\">%s</div><div class=\"track\">", k
        for (o = 1; o <= 4; o++) {
            s = order[o]; v = pcs[k "|" s] + 0
            if (v) printf "<div class=\"seg\" style=\"width:%.1f%%;background:var(--%s)\" title=\"%d %s\"></div>", v * 100 / pc[k], s, v, s
        }
        printf "</div><div class=\"pn\">%d</div></div>\n", pc[k]
    }

    split("ready contested blocked held", sec, " ")
    split("Ready to start|Blocked by a file somebody holds|Blocked|In progress", lab, "|")
    for (o = 1; o <= 4; o++) {
        s = sec[o]
        if (!(s in cnt)) continue
        printf "<h2>%s (%d)</h2>\n", lab[o], cnt[s]
        for (p = 0; p <= 3; p++) for (i = 1; i <= n; i++) {
            if (state[i] != s || prio_of[i] != "P" p) continue
            printf "<details class=\"card %s\" id=\"t-%s\"><summary><div class=\"ct\">%s</div><div class=\"cm\">", s, esc(id[i]), esc(title[i])
            printf "<span class=\"p\" style=\"color:var(--%s)\">%s</span><span class=\"id\">%s</span>", s, prio_of[i], esc(id[i])
            if (tags[i] != "") printf "<span>%s</span>", esc(tags[i])
            if (why[i] != "")  printf "<span class=\"why\">%s</span>", esc(why[i])
            print "</div></summary><div class=\"body\">"
            for (j = 1; j <= fn[i]; j++)
                printf "<div class=\"f\"><div class=\"fl\">%s</div><div class=\"fv\">%s</div></div>\n", esc(flab[i, j]), md(ftxt[i, j])
            print "</div></details>"
        }
    }

    printf "<footer>Regenerate with <code>%s</code>, or keep it current with <code>%s --serve</code>. Nothing here is editable &mdash; change the task file.</footer>\n", label, label
    print "</div>"
    # Survive the meta refresh: keep which cards are open and where the page was.
    # Wrapped because sessionStorage throws in some contexts, and the board has
    # to render correctly without it.
    print "<script>"
    print "(function(){try{var K='board-open',S=sessionStorage;"
    print "var open=JSON.parse(S.getItem(K)||'[]');"
    print "open.forEach(function(id){var e=document.getElementById(id);if(e)e.open=true});"
    print "document.querySelectorAll('details.card').forEach(function(d){"
    print "d.addEventListener('toggle',function(){var a=[];"
    print "document.querySelectorAll('details.card[open]').forEach(function(x){a.push(x.id)});"
    print "S.setItem(K,JSON.stringify(a))})});"
    print "var y=S.getItem('board-scroll');if(y)window.scrollTo(0,+y);"
    print "window.addEventListener('scroll',function(){S.setItem('board-scroll',window.scrollY)},{passive:true});"
    print "}catch(e){}})();"
    print "</script>"

    # Freshness is verified, never asserted. The page fetches the stamp its
    # renderer writes and reports what it found: current, superseded (reload), or
    # unverifiable. A file:// board cannot fetch a sibling, so it says so instead
    # of claiming to be live while showing a frozen render - which is the bug this
    # replaced. All ASCII, single-quoted, so nothing here needs escaping.
    printf "<script>(function(){var R=%d,M=%d,S='%s';\n", refresh + 0, epoch + 0, stamp
    print "var el=document.getElementById('freshness');if(!el)return;"
    print "function p(c,t){el.className=c;el.textContent=t}"
    print "function z(n){return (n<10?'0':'')+n}"
    print "function ago(s){return s<60?s+'s ago':s<3600?Math.floor(s/60)+'m ago':Math.floor(s/3600)+'h ago'}"
    print "function nows(){return Math.floor(Date.now()/1000)}"
    print "if(!R){var tick=function(){p('snap','snapshot, rendered '+ago(nows()-M))};"
    print "tick();setInterval(tick,1000);return}"
    print "if(!S){p('stale','cannot verify: renderer wrote no stamp');return}"
    print "function check(){fetch(S+'?_='+Date.now(),{cache:'no-store'})"
    print ".then(function(r){if(!r.ok)throw 0;return r.text()})"
    print ".then(function(t){var s=parseInt(t,10);if(s>M){location.reload();return}"
    print "var d=new Date();p('live','live, checked '+z(d.getHours())+':'+z(d.getMinutes())+':'+z(d.getSeconds()))})"
    print ".catch(function(){var f=location.protocol.indexOf('http')!==0;"
    print "p('stale',f?'NOT refreshing: a '+location.protocol+' board cannot read '+S+' - run tasks-board --serve'"
    print ":'NOT refreshing: cannot read '+S+' - is the renderer still running?')})}"
    print "check();setInterval(check,R*1000);"
    print "})();</script>"
    print "</body></html>"
}
