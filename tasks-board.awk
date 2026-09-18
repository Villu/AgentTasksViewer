                                                                        # -*- awk -*-
# Reads a markdown task file, writes an HTML board. Called by tasks-board.
#
# The four live states are the same ones tasks-ready computes, deliberately: a
# task is ready only when nobody holds it, nothing blocks it, and no path in its
# Files is held by a task somebody has claimed. Two implementations of that rule
# would drift, so if you change one, change the other in the same commit.
#
# A fifth state, done, is a `- [x]` checkbox. It is rendered at the bottom and
# left out of the counts and the bars, because a board is for deciding what to do
# next and a finished task is not a candidate. It also drops out of the two rules
# that read other tasks: a done task holds none of its Files, and a **Blocked by**
# naming it is satisfied. Both have to be true or marking a task done would be
# worse than deleting it — it would go on blocking its dependents silently.
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
    fin[n] = (substr(line, 4, 1) == "x")
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
        if (actor[i] == "" || fin[i]) continue
        f = files[i]
        while (match(f, /`[^`]+`/)) {
            held[substr(f, RSTART + 1, RLENGTH - 2)] = id[i]
            f = substr(f, RSTART + RLENGTH)
        }
    }

    for (i = 1; i <= n; i++) {
        if (fin[i]) {
            state[i] = "done"; dn++
            why[i] = (actor[i] != "" ? "@" actor[i] : "")
            continue
        }
        state[i] = "ready"; why[i] = ""
        if (actor[i] != "")    { state[i] = "held";    why[i] = "@" actor[i] }
        else if (blk[i] != "") { state[i] = "blocked"; why[i] = blk[i] }
        else {
            split(dep[i], d, /,[ \t]*/)
            for (k in d) {
                t = d[k]; gsub(/^[ \t]+|[ \t]+$/, "", t)
                if (t != "" && (t in byid) && !fin[byid[t]]) {
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
    # Before the first paint, not at the end with the rest of the scripts: a theme
    # applied after the body renders is a flash of the other one on every reload,
    # and this page reloads itself whenever the queue changes.
    print "<script>(function(){try{var t=localStorage.getItem('board-theme');"
    print "if(t==='dark'||t==='light')document.documentElement.setAttribute('data-theme',t)}catch(e){}})();</script>"
    print "<title>" heading "</title><style>"
    print ":root{--bg:#fbfaf9;--fg:#1a1a18;--dim:#6b6a66;--card:#fff;--line:#e5e3df;--bar:#edebe7;"
    print "--ready:#2e7d5b;--blocked:#b06c1d;--held:#2b6cb0;--contested:#a33a3a;--done:#6b6a66;--kbd:#f2f0ec}"
    print "@media(prefers-color-scheme:dark){:root:not([data-theme=\"light\"]){"
    print "--bg:#171614;--fg:#eceae6;--dim:#9a9791;--card:#201f1c;--line:#32302c;--bar:#2a2825;"
    print "--ready:#5fbf90;--blocked:#d9a05b;--held:#7aaede;--contested:#e08585;--done:#9a9791;--kbd:#2a2825}}"
    print ":root[data-theme=\"dark\"]{--bg:#171614;--fg:#eceae6;--dim:#9a9791;--card:#201f1c;"
    print "--line:#32302c;--bar:#2a2825;--ready:#5fbf90;--blocked:#d9a05b;--held:#7aaede;"
    print "--contested:#e08585;--done:#9a9791;--kbd:#2a2825}"
    print "*{box-sizing:border-box}"
    print "body{margin:0;background:var(--bg);color:var(--fg);padding:32px 16px 64px;"
    print "font:15px/1.55 ui-sans-serif,-apple-system,\"Segoe UI\",system-ui,sans-serif}"
    print ".w{max-width:940px;margin:0 auto}"
    # Row gap first, column gap second. When the button wraps under the text it
    # should read as belonging to it, so the gap above it is small and the space
    # below comes from this margin rather than from .sub — which is why .sub has
    # none of its own.
    print ".hd{display:flex;justify-content:space-between;align-items:flex-start;"
    print "gap:7px 14px;flex-wrap:wrap;margin-bottom:19px}"
    print ".theme{flex:none;background:var(--card);color:var(--dim);border:1px solid var(--line);"
    print "border-radius:8px;padding:6px 11px;font:inherit;font-size:12px;cursor:pointer;"
    print "display:flex;align-items:center;gap:6px}"
    print ".theme:hover{color:var(--fg);border-color:var(--dim)}"
    print ".theme .g{font-size:13px;line-height:1}"
    print "h1{font-size:22px;margin:0 0 3px;letter-spacing:-.01em}"
    print ".sub{color:var(--dim);font-size:13px}"
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
    print "h2{font-size:11.5px;text-transform:uppercase;letter-spacing:.07em;color:var(--dim);margin:28px 0 10px;"
    print "font-weight:600;cursor:pointer;user-select:none;display:flex;align-items:center;gap:7px}"
    print "h2:hover{color:var(--fg)}"
    print "h2:focus-visible{outline:2px solid var(--held);outline-offset:3px;border-radius:3px}"
    print "h2 .caret{font-size:9px;line-height:1;transition:transform .12s;display:inline-block}"
    print "h2[aria-expanded=\"true\"] .caret{transform:rotate(90deg)}"
    print "h2 .n{font-variant-numeric:tabular-nums}"
    print "section.sec.shut .cards{display:none}"
    print "section.sec.shut h2{margin-bottom:0}"
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
    print ".card.done{border-left-color:var(--dim)}"
    print ".card.closed{border-left-color:var(--dim);padding:11px 14px}"
    print ".card.closed .ct{color:var(--dim);margin-bottom:2px}"
    print ".note{font-size:12.5px;color:var(--dim);line-height:1.5;padding:2px 2px 4px}"
    print ".card.done .ct{color:var(--dim)}"
    print ".ct{font-weight:550;margin-bottom:3px}"
    print ".no{display:inline-block;min-width:1.9em;color:var(--dim);font-weight:600;"
    print "font-variant-numeric:tabular-nums;font-size:12.5px}"
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

    print "<div class=\"hd\"><div>"
    printf "<h1>%s</h1>\n<div class=\"sub\">%d tasks", heading, n - dn
    if (dn) printf " &middot; %d completed", dn
    printf " &middot; generated %s", generated
    if (refresh + 0 > 0)
        printf " &middot; <span class=\"live\" id=\"freshness\">checking every %ds</span>", refresh
    else
        printf " &middot; <span class=\"snap\" id=\"freshness\">snapshot</span>"
    printf " &middot; a view of %s, which is the only source of truth</div>\n", esc(source)
    print "</div><button class=\"theme\" id=\"theme\" type=\"button\">"
    print "<span class=\"g\" id=\"themeg\">&#9681;</span><span id=\"themet\">System</span></button></div>"

    print "<div class=\"stats\">"
    printf "<div class=\"stat\"><b style=\"color:var(--ready)\">%d</b><span>ready</span></div>\n", cnt["ready"] + 0
    printf "<div class=\"stat\"><b style=\"color:var(--held)\">%d</b><span>in progress</span></div>\n", cnt["held"] + 0
    printf "<div class=\"stat\"><b style=\"color:var(--blocked)\">%d</b><span>blocked</span></div>\n", cnt["blocked"] + 0
    printf "<div class=\"stat\"><b style=\"color:var(--contested)\">%d</b><span>file contested</span></div>\n", cnt["contested"] + 0
    print "</div>"

    split("held ready contested blocked", order, " ")
    for (p = 0; p <= 9; p++) {
        k = "P" p
        if (!(k in pc)) continue
        printf "<div class=\"prow\"><div class=\"plab\">%s</div><div class=\"track\">", k
        for (o = 1; o <= 4; o++) {
            s = order[o]; v = pcs[k "|" s] + 0
            if (v) printf "<div class=\"seg\" style=\"width:%.1f%%;background:var(--%s)\" title=\"%d %s\"></div>", v * 100 / pc[k], s, v, s
        }
        printf "</div><div class=\"pn\">%d</div></div>\n", pc[k]
    }

    # In progress first: the coordinator's first question is who is on what, and
    # a queue long enough to scroll buried it under the ready list. Done last,
    # because it is the only section nobody acts on.
    cnt["done"] = dn
    split("held ready contested blocked done", sec, " ")
    split("In progress|Ready to start|Blocked by a file somebody holds|Blocked|Completed", lab, "|")
    num = 0
    for (o = 1; o <= 5; o++) {
        s = sec[o]
        if (!(s in cnt) || cnt[s] + 0 == 0) continue
        printf "<section class=\"sec\" data-sec=\"%s\">", s
        printf "<h2 tabindex=\"0\" role=\"button\" aria-expanded=\"true\">"
        printf "<span class=\"caret\">&#9654;</span>%s <span class=\"n\">(%d)</span></h2>\n", lab[o], cnt[s]
        print "<div class=\"cards\">"
        for (p = 0; p <= 9; p++) for (i = 1; i <= n; i++) {
            if (state[i] != s || prio_of[i] != "P" p) continue
            num++
            printf "<details class=\"card %s\" id=\"t-%s\"><summary><div class=\"ct\">", s, esc(id[i])
            printf "<span class=\"no\">%d</span>%s</div><div class=\"cm\">", num, esc(title[i])
            printf "<span class=\"p\" style=\"color:var(--%s)\">%s</span><span class=\"id\">%s</span>", s, prio_of[i], esc(id[i])
            if (tags[i] != "") printf "<span>%s</span>", esc(tags[i])
            if (why[i] != "")  printf "<span class=\"why\">%s</span>", esc(why[i])
            print "</div></summary><div class=\"body\">"
            for (j = 1; j <= fn[i]; j++)
                printf "<div class=\"f\"><div class=\"fl\">%s</div><div class=\"fv\">%s</div></div>\n", esc(flab[i, j]), md(ftxt[i, j])
            print "</div></details>"
        }
        print "</div></section>"
    }

    # Closed tasks come from the git log, not from the file — the block is gone,
    # which is the point of deleting it. So this section is a view of a different
    # source than everything above it, and it says how much of that source it is
    # showing: "20 of 63" rather than a bare "20" that reads as all of them.
    if (closed_on + 0) {
        print "<section class=\"sec\" data-sec=\"closed\">"
        printf "<h2 tabindex=\"0\" role=\"button\" aria-expanded=\"true\">"
        printf "<span class=\"caret\">&#9654;</span>Closed recently "
        if (closed_why != "")
            printf "<span class=\"n\">(unavailable)</span>"
        else if (closed_shown + 0 < closed_total + 0)
            printf "<span class=\"n\">(%d of %d)</span>", closed_shown, closed_total
        else
            printf "<span class=\"n\">(%d)</span>", closed_shown
        print "</h2>"
        print "<div class=\"cards\">"

        if (closed_why != "") {
            printf "<div class=\"note\">Not shown: %s. Everything above is unaffected &mdash; it comes from the task file, which was read.</div>\n", esc(closed_why)
        } else if (closed_shown + 0 == 0) {
            printf "<div class=\"note\">No commit touching the task file has a subject starting <code>%s</code>. That is the prefix this board was told to look for, not a rule &mdash; pass <code>--closed-match</code> to change it.</div>\n", esc(closed_match)
        } else {
            while ((getline cl < closed_file) > 0) {
                # Split by hand rather than with split(): a commit subject may
                # contain the separator, and only the first two fields are fixed.
                q = index(cl, "\t"); csha = substr(cl, 1, q - 1); cl = substr(cl, q + 1)
                q = index(cl, "\t"); cdate = substr(cl, 1, q - 1); csub = substr(cl, q + 1)
                ctext = substr(csub, length(closed_match) + 1)
                cid = ""
                q = index(ctext, ":")
                if (q > 0) { cid = substr(ctext, 1, q - 1); ctext = substr(ctext, q + 2) }
                # No row number here, and the counter deliberately does not
                # advance. It counts rows read from the task file; these come
                # from the log. Numbering both made a closed row's number depend
                # on how many live tasks happened to be above it, so closing one
                # task renumbered every historical entry — an index that moves
                # for reasons that have nothing to do with the thing it indexes.
                # These rows already carry two handles that do not move, the id
                # and the sha, and an unstable number beside stable ones invites
                # exactly the use it cannot support: writing it down.
                printf "<div class=\"card closed\"><div class=\"ct\">%s</div><div class=\"cm\">", esc(ctext)
                if (cid != "") printf "<span class=\"id\">%s</span>", esc(cid)
                printf "<span>%s</span><span class=\"id\">%s</span></div></div>\n", esc(cdate), esc(csha)
            }
            close(closed_file)
            if (closed_shown + 0 < closed_total + 0)
                printf "<div class=\"note\">The %d most recent of %d. This list is truncated, not complete &mdash; <code>--closed N</code> shows more.</div>\n", closed_shown, closed_total
        }
        print "</div></section>"
    }

    printf "<footer>Regenerate with <code>%s</code>, or keep it current with <code>%s --serve</code>. Nothing here is editable &mdash; change the task file.</footer>\n", label, label
    print "</div>"

    # A section heading shows and hides its list of tasks. It does not touch the
    # cards' own open state: expanding a card is what reveals Details and
    # Acceptance, and a heading that did both would make "collapse this section"
    # and "expand everything in it" the same gesture.
    #
    # Its own script, not folded into the one below, because that one is wrapped
    # in a try for sessionStorage and a throw there would take this with it — a
    # heading that silently does nothing when clicked is worse than no affordance.
    # Which sections are shut is remembered below, beside the open cards.
    print "<script>"
    print "document.querySelectorAll('section.sec').forEach(function(sec){"
    print "var h=sec.querySelector('h2');if(!h)return;"
    print "function flip(){var shut=sec.classList.toggle('shut');"
    print "h.setAttribute('aria-expanded',shut?'false':'true');"
    print "if(sec.saveShut)sec.saveShut()}"
    print "h.addEventListener('click',flip);"
    print "h.addEventListener('keydown',function(e){"
    print "if(e.key==='Enter'||e.key===' '){e.preventDefault();flip()}});"
    print "});"
    print "</script>"

    # System, light, dark — three states, not a two-way switch. Following the OS
    # is the default and has to stay reachable, or somebody who once clicked the
    # button is pinned to whichever theme they picked for the rest of the year.
    # localStorage, not sessionStorage: a theme is not a per-tab detail, and it is
    # the one thing here worth surviving the browser being closed.
    print "<script>"
    print "(function(){var b=document.getElementById('theme');if(!b)return;"
    print "var g=document.getElementById('themeg'),t=document.getElementById('themet');"
    print "var seq=['system','light','dark'],lab={system:'System',light:'Light',dark:'Dark'};"
    print "var gl={system:'\\u25D1',light:'\\u2600',dark:'\\u263E'};"
    print "function get(){try{var v=localStorage.getItem('board-theme');"
    print "return v==='light'||v==='dark'?v:'system'}catch(e){return 'system'}}"
    print "function put(v){var r=document.documentElement;"
    print "if(v==='system')r.removeAttribute('data-theme');else r.setAttribute('data-theme',v);"
    print "g.textContent=gl[v];t.textContent=lab[v];"
    print "b.setAttribute('aria-label','Theme: '+lab[v]+', click to change');"
    print "try{if(v==='system')localStorage.removeItem('board-theme');"
    print "else localStorage.setItem('board-theme',v)}catch(e){}}"
    print "put(get());"
    print "b.addEventListener('click',function(){put(seq[(seq.indexOf(get())+1)%3])});"
    print "})();"
    print "</script>"

    # Survive the meta refresh: keep which cards are open and where the page was.
    # Wrapped because sessionStorage throws in some contexts, and the board has
    # to render correctly without it.
    print "<script>"
    print "(function(){try{var K='board-open',C='board-shut',S=sessionStorage;"
    print "var open=JSON.parse(S.getItem(K)||'[]');"
    print "open.forEach(function(id){var e=document.getElementById(id);if(e)e.open=true});"
    print "document.querySelectorAll('details.card').forEach(function(d){"
    print "d.addEventListener('toggle',function(){var a=[];"
    print "document.querySelectorAll('details.card[open]').forEach(function(x){a.push(x.id)});"
    print "S.setItem(K,JSON.stringify(a))})});"
    # Shut sections are keyed by state name, not by position: a task moving from
    # ready to held changes which sections exist, and a section that was shut
    # should come back shut rather than whichever one is now third.
    print "var shut=JSON.parse(S.getItem(C)||'[]');"
    print "document.querySelectorAll('section.sec').forEach(function(sec){"
    print "var h=sec.querySelector('h2');"
    print "if(shut.indexOf(sec.dataset.sec)>=0){sec.classList.add('shut');"
    print "if(h)h.setAttribute('aria-expanded','false')}"
    print "sec.saveShut=function(){var a=[];"
    print "document.querySelectorAll('section.sec.shut').forEach(function(x){a.push(x.dataset.sec)});"
    print "S.setItem(C,JSON.stringify(a))}});"
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
