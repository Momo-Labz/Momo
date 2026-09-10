import Combine
import Foundation
import Network

final class DeskDisplayServer: ObservableObject {
    enum ServerState: Equatable {
        case stopped
        case starting
        case ready
        case failed(String)

        var label: String {
            switch self {
            case .stopped: return "Off"
            case .starting: return "Starting…"
            case .ready: return "Ready"
            case .failed: return "Needs attention"
            }
        }
    }

    @Published private(set) var state: ServerState = .stopped
    @Published private(set) var displayURL: URL?

    let port: UInt16 = 7_377
    let token: String

    private let queue = DispatchQueue(label: "com.momolabz.barboy.desk-display", qos: .utility)
    private let lock = NSLock()
    private var listener: NWListener?
    private var statusJSON = Data("{\"providers\":[],\"sessions\":[]}".utf8)

    init(defaults: UserDefaults = .standard) {
        if let saved = defaults.string(forKey: "deskDisplayPairingToken"), saved.count >= 20 {
            token = saved
        } else {
            let created = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            token = created
            defaults.set(created, forKey: "deskDisplayPairingToken")
        }
        displayURL = Self.makeDisplayURL(port: port, token: token)
    }

    var pairingCode: String { String(token.suffix(6)).uppercased() }
    var errorMessage: String? {
        if case let .failed(message) = state { return message }
        return nil
    }

    func start() {
        guard listener == nil else { return }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            publish(.failed("Invalid port"))
            return
        }
        do {
            let listener = try NWListener(using: .tcp, on: endpointPort)
            self.listener = listener
            publish(.starting)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.publish(.ready)
                case let .failed(error):
                    self.publish(.failed(error.localizedDescription))
                    self.listener?.cancel()
                    self.listener = nil
                case .cancelled:
                    self.publish(.stopped)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.receiveRequest(on: connection)
            }
            listener.start(queue: queue)
        } catch {
            self.listener = nil
            publish(.failed(error.localizedDescription))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        publish(.stopped)
    }

    func update(snapshots: [ProviderSnapshot], includeTitles: Bool) {
        let data = Self.makeStatusJSON(snapshots: snapshots, includeTitles: includeTitles)
        lock.lock()
        statusJSON = data
        lock.unlock()
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let response = self.response(for: request)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private func response(for request: String) -> Data {
        guard let firstLine = request.components(separatedBy: "\r\n").first,
              firstLine.hasPrefix("GET "),
              let target = firstLine.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: "http://barboy.local\(target)") else {
            return Self.httpResponse(status: "400 Bad Request", type: "text/plain; charset=utf-8", body: Data("Bad request".utf8))
        }

        if components.path == "/health" {
            return Self.httpResponse(status: "200 OK", type: "text/plain; charset=utf-8", body: Data("BAR BOY OK".utf8))
        }

        let suppliedToken = components.queryItems?.first(where: { $0.name == "key" })?.value
        guard suppliedToken == token else {
            return Self.httpResponse(status: "401 Unauthorized", type: "text/plain; charset=utf-8", body: Data("Pairing key required".utf8))
        }

        if components.path == "/api/status" {
            lock.lock()
            let body = statusJSON
            lock.unlock()
            return Self.httpResponse(status: "200 OK", type: "application/json; charset=utf-8", body: body)
        }

        if components.path == "/" || components.path == "/display" {
            return Self.httpResponse(status: "200 OK", type: "text/html; charset=utf-8", body: Data(Self.dashboardHTML(token: token).utf8))
        }

        return Self.httpResponse(status: "404 Not Found", type: "text/plain; charset=utf-8", body: Data("Not found".utf8))
    }

    private func publish(_ nextState: ServerState) {
        DispatchQueue.main.async { [weak self] in self?.state = nextState }
    }

    static func makeStatusJSON(snapshots: [ProviderSnapshot], includeTitles: Bool) -> Data {
        let providers: [[String: Any]] = snapshots.map { snapshot in
            [
                "id": snapshot.provider.rawValue,
                "name": snapshot.provider.name,
                "mark": snapshot.provider.monogram,
                "active": snapshot.activeCount,
                "tokens": snapshot.localTokensToday,
                "usage": snapshot.usageText,
                "short": snapshot.shortWindowPercent.map { $0 as Any } ?? NSNull(),
                "week": snapshot.weekWindowPercent.map { $0 as Any } ?? NSNull(),
                "sessionCount": snapshot.sessions.count,
                "needsAttention": snapshot.needsAttentionCount
            ]
        }
        let sessions: [[String: Any]] = snapshots
            .flatMap(\.sessions)
            .sorted {
                if $0.attention.isUrgent != $1.attention.isUrgent { return $0.attention.isUrgent }
                if $0.isRunning != $1.isRunning { return $0.isRunning }
                return $0.updatedAt > $1.updatedAt
            }
            .prefix(5)
            .map { session in
                [
                    "id": session.id,
                    "provider": session.provider.name,
                    "mark": session.provider.monogram,
                    "role": session.role.rawValue,
                    "title": includeTitles ? session.title : (session.isRunning ? "Active session" : "Recent session"),
                    "project": includeTitles ? session.project : "Private",
                    "live": session.isRunning,
                    "age": session.ageLabel,
                    "attention": session.attention.rawValue,
                    "attentionLabel": session.attention.label,
                    "attentionReason": session.attentionReason ?? "",
                    "urgent": session.attention.isUrgent,
                    "model": session.model ?? "",
                    "mcpServers": session.mcpServers,
                    "skills": session.skills,
                    "plugins": session.plugins,
                    "capabilityCount": session.capabilityCount
                ]
            }
        let object: [String: Any] = [
            "updated": ISO8601DateFormatter().string(from: .now),
            "activeCount": snapshots.reduce(0) { $0 + $1.activeCount },
            "attentionCount": snapshots.reduce(0) { $0 + $1.needsAttentionCount },
            "providers": providers,
            "sessions": sessions
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    static func dashboardHTML(token: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <title>BAR BOY Desk Display</title>
        <style>
        :root{color-scheme:dark;--bg:#201e1d;--panel:#2d2b2b;--line:#66615e;--ink:#f3f2f2;--muted:#aaa5a2;--alert:#e15b47}
        *{box-sizing:border-box}html,body{width:100%;height:100%;margin:0;overflow:hidden;background:var(--bg);color:var(--ink);font-family:ui-monospace,"SFMono-Regular",Menlo,monospace}
        body{padding:10px;display:grid;grid-template-rows:38px 1fr 12px;gap:7px}
        header{display:flex;align-items:center;gap:8px}.logo{width:31px;height:31px;border:2px solid var(--ink);display:grid;place-items:center;font-size:16px;font-weight:900}.brand{font-size:15px;font-weight:900;letter-spacing:1.5px}.sub{color:var(--muted);font-size:7px;letter-spacing:1px;margin-top:2px}.signal{margin-left:auto;border:1px solid var(--line);padding:6px 7px;font-size:8px;font-weight:900;letter-spacing:.7px}.signal.alert{border-color:var(--alert);color:var(--alert);animation:pulse .9s cubic-bezier(.32,.72,0,1) infinite alternate}@keyframes pulse{to{opacity:.45;transform:scale(.96)}}
        .board{min-height:0;display:grid;grid-template-columns:44% 56%;border:1px solid var(--line)}.pane{min-width:0;overflow:hidden}.pane+.pane{border-left:1px solid var(--line)}.heading,.provider-head{height:22px;display:grid;align-items:center;color:var(--muted);font-size:7px;font-weight:900;letter-spacing:.8px;border-bottom:1px solid var(--line);padding:0 7px}.provider-head{grid-template-columns:1fr 31px 31px 27px;text-align:right}.provider-head span:first-child{text-align:left}
        .provider{height:38px;display:grid;grid-template-columns:1fr 31px 31px 27px;align-items:center;padding:0 7px;border-bottom:1px solid var(--line);font-size:8px;text-align:right}.provider:last-child{border:0}.provider-name{display:grid;grid-template-columns:22px 1fr;align-items:center;gap:6px;text-align:left;min-width:0}.mark{width:21px;height:21px;background:var(--ink);color:var(--bg);display:grid;place-items:center;font-weight:900}.pname{font-weight:900;white-space:nowrap}.local{font-size:6px;color:var(--muted);margin-top:2px}.urgent{color:var(--alert);font-weight:900}
        .session{height:47px;display:grid;grid-template-columns:24px 1fr auto;align-items:center;gap:6px;padding:0 7px;border-bottom:1px solid var(--line)}.session:last-child{border:0}.title{font-size:8px;font-weight:900;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.meta{font-size:6px;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:3px}.state{font-size:6px;font-weight:900;border:1px solid var(--line);padding:4px}.state.alert{border-color:var(--alert);color:var(--alert)}
        footer{display:flex;justify-content:space-between;color:var(--muted);font-size:7px;font-weight:800;letter-spacing:.6px}.offline{color:var(--alert)}
        @media(prefers-color-scheme:light){:root{--bg:#f3f2f2;--panel:#eae9e9;--line:#8b8581;--ink:#201e1d;--muted:#6c6663;--alert:#ec3013}}
        @media(prefers-reduced-motion:reduce){.signal.alert{animation:none}}
        </style>
        </head>
        <body>
          <header><div class="logo">▣</div><div><div class="brand">MOMO LABZ</div><div class="sub" id="summary">CONNECTING AGENT DESK…</div></div><div class="signal" id="signal">LOCAL</div></header>
          <section class="board"><div class="pane"><div class="provider-head"><span>PROVIDER</span><span>SH</span><span>WK</span><span>SE</span></div><div id="providers"></div></div><div class="pane"><div class="heading">YOUR RETURN QUEUE</div><div id="sessions"></div></div></section>
          <footer><span>PRIVATE · MAC → DESK</span><span id="clock">--:--</span></footer>
        <script>
        const key='\(token)';
        const esc=s=>String(s??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#039;');
        const pct=n=>Number.isFinite(n)?`${n}%`:'—';
        function render(data){
          document.getElementById('summary').textContent=data.activeCount?`${data.activeCount} AGENT${data.activeCount===1?'':'S'} WORKING`:'EVERYTHING IS QUIET';
          const signal=document.getElementById('signal');signal.textContent=data.attentionCount?`! ${data.attentionCount} NEED${data.attentionCount===1?'S':''} YOU`:'LIVE';signal.className=data.attentionCount?'signal alert':'signal';
          document.getElementById('providers').innerHTML=data.providers.slice(0,5).map(p=>`<div class="provider"><div class="provider-name"><div class="mark">${esc(p.mark)}</div><div><div class="pname">${esc(p.name).toUpperCase()}</div><div class="local">${esc(p.usage).toUpperCase()}</div></div></div><span>${pct(p.short)}</span><span>${pct(p.week)}</span><span class="${p.needsAttention?'urgent':''}">${p.needsAttention?'!':''}${esc(p.sessionCount)}</span></div>`).join('');
          const sessions=data.sessions.length?data.sessions:[{mark:'·',title:'Waiting for a session',role:'MOMO',project:'READY',age:'IDLE',urgent:false}];
          document.getElementById('sessions').innerHTML=sessions.slice(0,5).map(s=>{const cap=[s.model,s.capabilityCount?`${s.capabilityCount} CAP`:null].filter(Boolean).join(' / ');return `<div class="session"><div class="mark">${esc(s.mark)}</div><div><div class="title">${esc(s.title)}</div><div class="meta">${esc(s.urgent?(s.attentionReason||s.attentionLabel):(cap||`${s.role} / ${s.project}`))}</div></div><div class="state ${s.urgent?'alert':''}">${esc(s.urgent?s.attentionLabel:s.age)}</div></div>`}).join('');
        }
        async function poll(){try{const r=await fetch(`/api/status?key=${key}`,{cache:'no-store'});if(!r.ok)throw Error();render(await r.json())}catch(e){const s=document.getElementById('signal');s.textContent='OFFLINE';s.className='signal offline'}}
        setInterval(()=>document.getElementById('clock').textContent=new Date().toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'}),1000);setInterval(poll,2500);poll();
        </script>
        </body></html>
        """
    }

    private static func httpResponse(status: String, type: String, body: Data) -> Data {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    private static func makeDisplayURL(port: UInt16, token: String) -> URL? {
        let host = ProcessInfo.processInfo.hostName
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        components.path = "/display"
        components.queryItems = [URLQueryItem(name: "key", value: token)]
        return components.url
    }
}
