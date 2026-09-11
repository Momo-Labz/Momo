import Combine
import AppKit
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
    @Published private(set) var port: UInt16 = 7_377

    let token: String

    private static let preferredPort: UInt16 = 7_377
    private let queue = DispatchQueue(label: "com.momolabz.barboy.desk-display", qos: .utility)
    private let lock = NSLock()
    private var listener: NWListener?
    private var activePort = preferredPort
    private var statusJSON = Data("{\"providers\":[],\"sessions\":[]}".utf8)

    init(defaults: UserDefaults = .standard) {
        if let saved = defaults.string(forKey: "deskDisplayPairingToken"), saved.count >= 20 {
            token = saved
        } else {
            let created = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            token = created
            defaults.set(created, forKey: "deskDisplayPairingToken")
        }
        displayURL = Self.makeDisplayURL(port: Self.preferredPort, token: token)
    }

    var pairingCode: String { String(token.suffix(6)).uppercased() }
    var errorMessage: String? {
        if case let .failed(message) = state { return message }
        return nil
    }

    func start() {
        guard listener == nil else { return }
        startListener(on: NWEndpoint.Port(rawValue: Self.preferredPort)!, allowsFallback: true)
    }

    private func startListener(on port: NWEndpoint.Port, allowsFallback: Bool) {
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = false
            let listener = try NWListener(using: parameters, on: port)
            self.listener = listener
            publish(.starting)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    let resolvedPort = listener.port?.rawValue ?? port.rawValue
                    self.activePort = resolvedPort
                    self.publishReady(on: resolvedPort)
                case let .failed(error):
                    listener.stateUpdateHandler = nil
                    self.listener?.cancel()
                    self.listener = nil
                    if allowsFallback, Self.isAddressInUse(error) {
                        self.startListener(on: .any, allowsFallback: false)
                    } else {
                        self.publish(.failed(error.localizedDescription))
                    }
                case .cancelled:
                    if self.listener === listener { self.publish(.stopped) }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self, Self.isLocalPeer(connection.endpoint) else {
                    connection.cancel()
                    return
                }
                self.receiveRequest(on: connection)
            }
            listener.start(queue: queue)
        } catch {
            self.listener = nil
            if allowsFallback, Self.isAddressInUse(error) {
                startListener(on: .any, allowsFallback: false)
            } else {
                publish(.failed(error.localizedDescription))
            }
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
        guard let parsed = Self.parseRequest(request), parsed.method == "GET" else {
            return Self.httpResponse(status: "400 Bad Request", type: "text/plain; charset=utf-8", body: Data("Bad request".utf8))
        }
        guard Self.isAllowedHost(parsed.host, port: activePort) else {
            return Self.httpResponse(status: "421 Misdirected Request", type: "text/plain; charset=utf-8", body: Data("Unrecognized host".utf8))
        }

        let components = parsed.components
        let headerAuthorized = Self.bearerToken(from: parsed.headers).map { Self.securelyMatches($0, token) } == true
        let cookieAuthorized = Self.cookieToken(from: parsed.headers).map { Self.securelyMatches($0, token) } == true
        let queryToken = components.queryItems?.first(where: { $0.name == "key" })?.value

        if components.path == "/health" {
            guard headerAuthorized || cookieAuthorized else {
                return Self.unauthorizedResponse()
            }
            return Self.httpResponse(status: "200 OK", type: "text/plain; charset=utf-8", body: Data("BAR BOY OK".utf8))
        }

        if (components.path == "/" || components.path == "/display"),
           let queryToken,
           Self.securelyMatches(queryToken, token) {
            return Self.httpResponse(
                status: "303 See Other",
                type: "text/plain; charset=utf-8",
                body: Data("Continue to BAR BOY".utf8),
                extraHeaders: [
                    "Location: /display",
                    "Set-Cookie: barboy_key=\(token); Path=/; HttpOnly; SameSite=Strict; Max-Age=2592000"
                ]
            )
        }

        if components.path == "/api/status" {
            guard headerAuthorized || cookieAuthorized else { return Self.unauthorizedResponse() }
            lock.lock()
            let body = statusJSON
            lock.unlock()
            return Self.httpResponse(status: "200 OK", type: "application/json; charset=utf-8", body: body)
        }

        if components.path.hasPrefix("/provider-icon/") {
            guard headerAuthorized || cookieAuthorized else { return Self.unauthorizedResponse() }
            let providerID = String(components.path.dropFirst("/provider-icon/".count))
            guard let body = Self.providerIconPNG(providerID: providerID) else {
                return Self.httpResponse(status: "404 Not Found", type: "text/plain; charset=utf-8", body: Data("Not found".utf8))
            }
            return Self.httpResponse(status: "200 OK", type: "image/png", body: body)
        }

        if components.path == "/" || components.path == "/display" {
            guard headerAuthorized || cookieAuthorized else { return Self.unauthorizedResponse() }
            return Self.httpResponse(
                status: "200 OK",
                type: "text/html; charset=utf-8",
                body: Data(Self.dashboardHTML().utf8),
                extraHeaders: [
                    "Content-Security-Policy: default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'",
                    "Referrer-Policy: no-referrer"
                ]
            )
        }

        return Self.httpResponse(status: "404 Not Found", type: "text/plain; charset=utf-8", body: Data("Not found".utf8))
    }

    private func publish(_ nextState: ServerState) {
        DispatchQueue.main.async { [weak self] in self?.state = nextState }
    }

    private func publishReady(on resolvedPort: UInt16) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.port = resolvedPort
            self.displayURL = Self.makeDisplayURL(port: resolvedPort, token: self.token)
            self.state = .ready
        }
    }

    static func makeStatusJSON(snapshots: [ProviderSnapshot], includeTitles: Bool) -> Data {
        let providers = snapshots.map { snapshot in
            RelayProvider(
                id: snapshot.provider.rawValue,
                name: snapshot.provider.name,
                mark: snapshot.provider.monogram,
                active: snapshot.activeCount,
                tokens: snapshot.localTokensToday,
                usage: snapshot.usageText,
                short: snapshot.shortWindowPercent,
                week: snapshot.weekWindowPercent,
                sessionCount: snapshot.sessions.count,
                needsAttention: snapshot.needsAttentionCount
            )
        }
        let sessions = snapshots
            .flatMap(\.sessions)
            .sorted {
                if $0.attention.isUrgent != $1.attention.isUrgent { return $0.attention.isUrgent }
                if $0.isRunning != $1.isRunning { return $0.isRunning }
                return $0.updatedAt > $1.updatedAt
            }
            .map { session in
                RelaySession(
                    id: session.id,
                    provider: session.provider.name,
                    mark: session.provider.monogram,
                    role: session.role.rawValue,
                    title: includeTitles ? session.title : (session.isRunning ? "Active session" : "Recent session"),
                    project: includeTitles ? session.project : "Private",
                    live: session.isRunning,
                    age: session.ageLabel,
                    attention: session.attention.rawValue,
                    attentionLabel: session.attention.label,
                    attentionReason: includeTitles ? session.attentionReason : nil,
                    urgent: session.attention.isUrgent,
                    model: includeTitles ? session.model : nil,
                    mcpServers: includeTitles ? session.mcpServers : [],
                    skills: includeTitles ? session.skills : [],
                    plugins: includeTitles ? session.plugins : [],
                    capabilityCount: session.capabilityCount
                )
            }
        let payload = RelayStatus(
            schemaVersion: RelayStatus.currentSchemaVersion,
            updated: ISO8601DateFormatter().string(from: .now),
            activeCount: snapshots.reduce(0) { $0 + $1.activeCount },
            attentionCount: snapshots.reduce(0) { $0 + $1.needsAttentionCount },
            providers: providers,
            sessions: Array(sessions)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(payload)) ?? Data("{}".utf8)
    }

    static func dashboardHTML() -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"><meta name="referrer" content="no-referrer">
        <title>BAR BOY Desk Display</title>
        <style>
        :root{color-scheme:dark;--bg:#201e1d;--panel:#2d2b2b;--line:#66615e;--ink:#f3f2f2;--muted:#aaa5a2;--alert:#E25C48}
        *{box-sizing:border-box}html,body{width:100%;height:100%;margin:0;overflow:hidden;background:var(--bg);color:var(--ink);font-family:ui-monospace,"SFMono-Regular",Menlo,monospace}
        body{padding:10px;display:grid;grid-template-rows:38px 1fr 12px;gap:7px}
        header{display:flex;align-items:center;gap:8px}.logo{width:31px;height:31px;border:2px solid var(--ink);display:grid;place-items:center;font-size:16px;font-weight:900}.brand{font-size:15px;font-weight:900;letter-spacing:1.5px}.sub{color:var(--muted);font-size:7px;letter-spacing:1px;margin-top:2px}.signal{margin-left:auto;border:1px solid var(--line);padding:6px 7px;font-size:8px;font-weight:900;letter-spacing:.7px}.signal.alert{border-color:var(--alert);color:var(--alert)}
        .board{min-height:0;display:grid;grid-template-columns:44% 56%;border:1px solid var(--line)}.pane{min-width:0;overflow:hidden}.pane+.pane{border-left:1px solid var(--line)}.heading,.provider-head{height:22px;display:grid;align-items:center;color:var(--muted);font-size:7px;font-weight:900;letter-spacing:.8px;border-bottom:1px solid var(--line);padding:0 7px}.provider-head{grid-template-columns:1fr 31px 31px 27px;text-align:right}.provider-head span:first-child{text-align:left}
        .provider{height:38px;display:grid;grid-template-columns:1fr 31px 31px 27px;align-items:center;padding:0 7px;border-bottom:1px solid var(--line);font-size:8px;text-align:right}.provider:last-child{border:0}.provider-name{display:grid;grid-template-columns:22px 1fr;align-items:center;gap:6px;text-align:left;min-width:0}.mark{width:21px;height:21px;background:var(--ink);color:var(--bg);display:grid;place-items:center;font-weight:900}.mark[src]{background:#f3f2f2;object-fit:contain;padding:3px}.pname{font-weight:900;white-space:nowrap}.local{font-size:6px;color:var(--muted);margin-top:2px}.urgent{color:var(--alert);font-weight:900}
        .session{height:47px;display:grid;grid-template-columns:24px 1fr auto;align-items:center;gap:6px;padding:0 7px;border-bottom:1px solid var(--line)}.session:last-child{border:0}.title{font-size:8px;font-weight:900;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.meta{font-size:6px;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:3px}.state{font-size:6px;font-weight:900;border:1px solid var(--line);padding:4px}.state.alert{border-color:var(--alert);color:var(--alert)}
        footer{display:flex;justify-content:space-between;color:var(--muted);font-size:7px;font-weight:800;letter-spacing:.6px}.offline{color:var(--alert)}
        @media(prefers-color-scheme:light){:root{--bg:#f3f2f2;--panel:#eae9e9;--line:#8b8581;--ink:#201e1d;--muted:#6c6663;--alert:#E25C48}}
        </style>
        </head>
        <body>
          <header><div class="logo">▣</div><div><div class="brand">MOMO LABZ</div><div class="sub" id="summary">CONNECTING AGENT DESK…</div></div><div class="signal" id="signal">LOCAL</div></header>
          <section class="board"><div class="pane"><div class="provider-head"><span>PROVIDER</span><span>SH</span><span>WK</span><span>SE</span></div><div id="providers"></div></div><div class="pane"><div class="heading">YOUR RETURN QUEUE</div><div id="sessions"></div></div></section>
          <footer><span>PRIVATE · MAC → DESK</span><span id="clock">--:--</span></footer>
        <script>
        const esc=s=>String(s??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#039;');
        const pct=n=>Number.isFinite(n)?`${n}%`:'—';
        const providerMark=(id,fallback)=>{const key=String(id??'').toLowerCase();return ['codex','claude','cursor','grok'].includes(key)?`<img class="mark" src="/provider-icon/${encodeURIComponent(key)}" alt="">`:`<div class="mark">${esc(fallback)}</div>`};
        function render(data){
          document.getElementById('summary').textContent=data.activeCount?`${data.activeCount} AGENT${data.activeCount===1?'':'S'} WORKING`:'EVERYTHING IS QUIET';
          const signal=document.getElementById('signal');signal.textContent=data.attentionCount?`! ${data.attentionCount} NEED${data.attentionCount===1?'S':''} YOU`:'LIVE';signal.className=data.attentionCount?'signal alert':'signal';
          document.getElementById('providers').innerHTML=data.providers.slice(0,5).map(p=>`<div class="provider"><div class="provider-name">${providerMark(p.id,p.mark)}<div><div class="pname">${esc(p.name).toUpperCase()}</div><div class="local">${esc(p.usage).toUpperCase()}</div></div></div><span>${pct(p.short)}</span><span>${pct(p.week)}</span><span class="${p.needsAttention?'urgent':''}">${p.needsAttention?'!':''}${esc(p.sessionCount)}</span></div>`).join('');
          const sessions=data.sessions.length?data.sessions:[{mark:'·',title:'Waiting for a session',role:'MOMO',project:'READY',age:'IDLE',urgent:false}];
          document.getElementById('sessions').innerHTML=sessions.slice(0,5).map(s=>{const cap=[s.model,s.capabilityCount?`${s.capabilityCount} CAP`:null].filter(Boolean).join(' / ');return `<div class="session">${providerMark(s.provider,s.mark)}<div><div class="title">${esc(s.title)}</div><div class="meta">${esc(s.urgent?(s.attentionReason||s.attentionLabel):(cap||`${s.role} / ${s.project}`))}</div></div><div class="state ${s.urgent?'alert':''}">${esc(s.urgent?s.attentionLabel:s.age)}</div></div>`}).join('');
        }
        async function poll(){try{const r=await fetch('/api/status',{cache:'no-store',credentials:'same-origin'});if(!r.ok)throw Error();render(await r.json())}catch(e){const s=document.getElementById('signal');s.textContent='OFFLINE';s.className='signal offline'}}
        setInterval(()=>document.getElementById('clock').textContent=new Date().toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'}),1000);setInterval(poll,2500);poll();
        </script>
        </body></html>
        """
    }

    static func dashboardHTML(token _: String) -> String {
        dashboardHTML()
    }

    private static func providerIconPNG(providerID: String) -> Data? {
        let assetName: String
        switch providerID.lowercased() {
        case "codex": assetName = "ProviderCodex"
        case "claude": assetName = "ProviderClaude"
        case "cursor": assetName = "ProviderCursor"
        case "grok": assetName = "ProviderGrok"
        default: return nil
        }
        guard let image = NSImage(named: assetName),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func httpResponse(status: String, type: String, body: Data, extraHeaders: [String] = []) -> Data {
        let additional = extraHeaders.isEmpty ? "" : extraHeaders.joined(separator: "\r\n") + "\r\n"
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\n\(additional)Connection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    private static func unauthorizedResponse() -> Data {
        httpResponse(
            status: "401 Unauthorized",
            type: "text/plain; charset=utf-8",
            body: Data("Pairing credential required".utf8),
            extraHeaders: ["WWW-Authenticate: Bearer realm=\"BAR BOY\""]
        )
    }

    private struct ParsedRequest {
        let method: String
        let components: URLComponents
        let host: String
        let headers: [String: String]
    }

    private static func parseRequest(_ request: String) -> ParsedRequest? {
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3,
              parts[2].hasPrefix("HTTP/1."),
              parts[1].hasPrefix("/"),
              !parts[1].contains("\\"),
              let components = URLComponents(string: "http://barboy.invalid\(parts[1])") else { return nil }

        var values: [String: [String]] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else { return nil }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            values[name, default: []].append(value)
        }
        guard values["host"]?.count == 1, let host = values["host"]?.first else { return nil }
        guard values["authorization", default: []].count <= 1,
              values["cookie", default: []].count <= 1 else { return nil }
        let headers = values.compactMapValues(\.first)
        return ParsedRequest(method: String(parts[0]), components: components, host: host, headers: headers)
    }

    private static func bearerToken(from headers: [String: String]) -> String? {
        guard let value = headers["authorization"] else { return nil }
        let pieces = value.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard pieces.count == 2, pieces[0].caseInsensitiveCompare("Bearer") == .orderedSame else { return nil }
        return String(pieces[1])
    }

    private static func cookieToken(from headers: [String: String]) -> String? {
        headers["cookie"]?
            .split(separator: ";")
            .compactMap { entry -> String? in
                let pieces = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard pieces.count == 2,
                      pieces[0].trimmingCharacters(in: .whitespaces) == "barboy_key" else { return nil }
                return String(pieces[1]).trimmingCharacters(in: .whitespaces)
            }
            .first
    }

    private static func securelyMatches(_ supplied: String, _ expected: String) -> Bool {
        let lhs = Array(supplied.utf8)
        let rhs = Array(expected.utf8)
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func isAllowedHost(_ authority: String, port: UInt16) -> Bool {
        guard let components = URLComponents(string: "http://\(authority)"),
              components.user == nil,
              components.password == nil,
              components.path.isEmpty,
              components.query == nil,
              components.fragment == nil,
              let rawHost = components.host,
              components.port.map({ $0 == Int(port) }) ?? true else { return false }

        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let machine = ProcessInfo.processInfo.hostName.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let machineAliases = Set([machine, machine.hasSuffix(".local") ? String(machine.dropLast(6)) : "\(machine).local"])
        if host == "localhost" || machineAliases.contains(host) { return true }
        if let ipv4 = IPv4Address(host) { return isPrivateIPv4(Array(ipv4.rawValue)) }
        if let ipv6 = IPv6Address(host) { return isPrivateIPv6(Array(ipv6.rawValue)) }
        return false
    }

    private static func isLocalPeer(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case let .ipv4(address): return isPrivateIPv4(Array(address.rawValue))
        case let .ipv6(address): return isPrivateIPv6(Array(address.rawValue))
        case let .name(name, _): return isAllowedHost(name, port: preferredPort)
        @unknown default: return false
        }
    }

    private static func isPrivateIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return false }
        return bytes[0] == 10
            || bytes[0] == 127
            || (bytes[0] == 169 && bytes[1] == 254)
            || (bytes[0] == 172 && (16...31).contains(bytes[1]))
            || (bytes[0] == 192 && bytes[1] == 168)
    }

    private static func isPrivateIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes.last == 1 { return true }
        if bytes[0] == 0xFC || bytes[0] == 0xFD { return true }
        if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 { return true }
        if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
            return isPrivateIPv4(Array(bytes.suffix(4)))
        }
        return false
    }

    private static func isAddressInUse(_ error: Error) -> Bool {
        guard case let NWError.posix(code) = error else { return false }
        return code == .EADDRINUSE
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
