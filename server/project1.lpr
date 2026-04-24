program clipboard_server;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX} cthreads {$ENDIF},
  Classes, SysUtils, CustApp, fphttpserver, httpdefs, SyncObjs;

type
  TMyApplication = class(TCustomApplication)
  private
    FHTTPServer: TFPHTTPServer;
    FLock      : TCriticalSection;
    FPush      : string;  // last value received from any client
    FPull      : string;  // value served to clients (updated from FPush when changed)
    function  GetPortFromArgs: Word;
    procedure HandleRequest(Sender: TObject;
      var ARequest : TFPHTTPConnectionRequest;
      var AResponse: TFPHTTPConnectionResponse);
  protected
    procedure DoRun; override;
  end;

function EscapeHTML(const S: string): string;
begin
  Result := StringReplace(S,      '&', '&amp;',  [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;',   [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;',   [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '<br>',   [rfReplaceAll]);
  Result := StringReplace(Result, #13, '',        [rfReplaceAll]);
end;

procedure TMyApplication.HandleRequest(Sender: TObject;
  var ARequest : TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
var
  InputText: string;
  SafeText : string;
begin
  try
    WriteLn('[', FormatDateTime('hh:nn:ss', Now), '] ',
      ARequest.Method, ' ', ARequest.URI,
      ' [', ARequest.RemoteAddr, ']');

    // -- OPTIONS (CORS preflight) ------------------------------------------
    if ARequest.Method = 'OPTIONS' then
    begin
      AResponse.Code := 204;
      AResponse.CustomHeaders.Values['Access-Control-Allow-Origin']  := '*';
      AResponse.CustomHeaders.Values['Access-Control-Allow-Methods'] := 'GET, POST, OPTIONS';
      AResponse.CustomHeaders.Values['Access-Control-Allow-Headers'] := 'Content-Type';
      Exit;
    end;

    AResponse.CustomHeaders.Values['Access-Control-Allow-Origin'] := '*';

    // -- POST /api/push -> client sends its clipboard ----------------------
    //    Store in FPush. If different from FPull, promote to FPull so other
    //    clients will receive the new value on their next /api/pull.
    if (ARequest.Method = 'POST') and (ARequest.URI = '/api/push') then
    begin
      InputText := ARequest.ContentFields.Values['data'];
      if InputText <> '' then
      begin
        FLock.Enter;
        try
          if InputText <> FPush then
          begin
            FPush := InputText;
            FPull := InputText;   // promote: new data available for all clients
            WriteLn('  [PUSH -> PULL] "', Copy(InputText, 1, 80), '"');
          end;
        finally
          FLock.Leave;
        end;
      end;
      AResponse.Code        := 200;
      AResponse.Content     := 'OK';
      AResponse.ContentType := 'text/plain';
      Exit;
    end;

    // -- GET /api/pull -> client fetches current clipboard -----------------
    //    Returns FPull (only updated when a client pushes something new).
    if (ARequest.Method = 'GET') and (ARequest.URI = '/api/pull') then
    begin
      FLock.Enter;
      try
        AResponse.Content := FPull;
      finally
        FLock.Leave;
      end;
      AResponse.Code        := 200;
      AResponse.ContentType := 'text/plain; charset=utf-8';
      Exit;
    end;

    // -- GET / -> web UI ---------------------------------------------------
    if (ARequest.Method = 'GET') and
       ((ARequest.URI = '/') or (ARequest.URI = '')) then
    begin
      FLock.Enter;
      try
        SafeText := EscapeHTML(FPull);
      finally
        FLock.Leave;
      end;

      AResponse.Code        := 200;
      AResponse.ContentType := 'text/html; charset=utf-8';
      AResponse.CustomHeaders.Values['Content-Type'] := 'text/html; charset=utf-8';
      AResponse.Content :=
        '<!DOCTYPE html>' +
        '<html lang="en"><head>' +
        '<meta charset="utf-8">' +
        '<meta name="viewport" content="width=device-width,initial-scale=1.0">' +
        '<title>ClipSync</title>' +
        '<link rel="preconnect" href="https://fonts.googleapis.com">' +
        '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>' +
        '<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:ital,wght@0,400;0,600;1,400&family=DM+Sans:wght@400;500;600&display=swap" rel="stylesheet">' +
        '<style>' +
        ':root{' +
        '--bg:#07090d;--s1:#0c1018;--s2:#111620;--b1:#1a2535;--b2:#253650;' +
        '--text:#bfcfdf;--dim:#3d5570;--accent:#00c8f0;--accent-glow:rgba(0,200,240,0.15);' +
        '--green:#00df82;--green-glow:rgba(0,223,130,0.15);--red:#ff4560;' +
        '--ui:"DM Sans",sans-serif;--mono:"IBM Plex Mono",monospace' +
        '}' +
        '*{box-sizing:border-box;margin:0;padding:0}' +
        'html,body{height:100%;background:var(--bg);color:var(--text);font-family:var(--ui)}' +
        '::-webkit-scrollbar{width:3px}::-webkit-scrollbar-track{background:transparent}' +
        '::-webkit-scrollbar-thumb{background:var(--b2);border-radius:2px}' +
        'header{height:52px;display:flex;align-items:center;justify-content:space-between;' +
        'padding:0 18px;background:var(--s1);border-bottom:1px solid var(--b1);flex-shrink:0}' +
        '.wordmark{display:flex;align-items:center;gap:9px}' +
        '.wm-badge{width:26px;height:26px;border-radius:7px;' +
        'background:linear-gradient(135deg,var(--accent),#0066cc);' +
        'display:grid;place-items:center;font-size:13px}' +
        '.wm-name{font-size:15px;font-weight:600;letter-spacing:-.3px}' +
        '.wm-name em{color:var(--accent);font-style:normal}' +
        '.live-pill{display:flex;align-items:center;gap:5px;background:var(--s2);' +
        'border:1px solid var(--b1);border-radius:20px;padding:4px 10px 4px 7px;' +
        'font-size:11px;font-family:var(--mono);color:var(--dim)}' +
        '.live-dot{width:6px;height:6px;border-radius:50%;background:var(--green);' +
        'box-shadow:0 0 5px var(--green);flex-shrink:0;animation:blink 2.2s ease-in-out infinite}' +
        '@keyframes blink{0%,100%{opacity:1}50%{opacity:.3}}' +
        '.layout{display:flex;height:calc(100vh - 52px);overflow:hidden}' +
        '.pane{flex:1;display:flex;flex-direction:column;overflow:hidden;min-width:0}' +
        '.pane+.pane{border-left:1px solid var(--b1)}' +
        '.ph{display:flex;align-items:center;justify-content:space-between;' +
        'padding:9px 14px;background:var(--s2);border-bottom:1px solid var(--b1);flex-shrink:0;gap:8px}' +
        '.ph-tag{font-size:10px;font-weight:600;letter-spacing:1.8px;text-transform:uppercase;' +
        'font-family:var(--mono);display:flex;align-items:center;gap:6px}' +
        '.ph-tag.rx{color:var(--accent)}.ph-tag.tx{color:var(--green)}' +
        '.btn{display:flex;align-items:center;gap:5px;background:transparent;' +
        'border:1px solid var(--b2);color:var(--accent);border-radius:6px;' +
        'padding:5px 11px;cursor:pointer;font-family:var(--mono);font-size:10px;' +
        'font-weight:600;letter-spacing:.8px;text-transform:uppercase;' +
        'transition:background .15s,border-color .15s,transform .1s}' +
        '.btn:hover{background:var(--accent-glow);border-color:var(--accent)}' +
        '.btn:active{transform:scale(.94)}' +
        '.btn.ok{color:var(--green);border-color:var(--green);background:var(--green-glow)}' +
        '#display{flex:1;overflow:auto;padding:16px 18px;white-space:pre-wrap;' +
        'word-break:break-word;font-size:13px;line-height:1.8;font-family:var(--mono)}' +
        '#display:empty::before{content:"No data yet...";color:var(--dim);font-style:italic}' +
        'textarea{flex:1;background:transparent;color:var(--text);border:none;' +
        'padding:16px 18px;font-size:13px;font-family:var(--mono);resize:none;outline:none;line-height:1.8}' +
        'textarea::placeholder{color:var(--dim);font-style:italic}' +
        '.send-bar{height:26px;flex-shrink:0;padding:0 14px;display:flex;align-items:center;' +
        'border-top:1px solid var(--b1);font-size:10px;font-family:var(--mono);' +
        'color:var(--dim);transition:color .2s}' +
        '.send-bar.sending{color:var(--green)}.send-bar.err{color:var(--red)}' +
        '@media(max-width:620px){' +
        'html,body{height:auto;overflow:auto}' +
        '.layout{flex-direction:column;height:auto;min-height:calc(100vh - 52px)}' +
        '.pane{min-height:45vh}.pane+.pane{border-left:none;border-top:1px solid var(--b1)}}' +
        '</style></head><body>' +
        '<header>' +
        '<div class="wordmark"><div class="wm-badge">&#x2398;</div>' +
        '<span class="wm-name">Clip<em>Sync</em></span></div>' +
        '<div class="live-pill"><div class="live-dot"></div><span id="liveTxt">live</span></div>' +
        '</header>' +
        '<div class="layout">' +
        '<div class="pane">' +
        '<div class="ph"><span class="ph-tag rx">&#x2193; Incoming</span>' +
        '<button class="btn" id="copyBtn" onclick="copyText()">&#x2398;&nbsp;Copy</button></div>' +
        '<div id="display">' + SafeText + '</div>' +
        '</div>' +
        '<div class="pane">' +
        '<div class="ph"><span class="ph-tag tx">&#x2191; Outgoing</span></div>' +
        '<textarea id="inputBox" placeholder="Type or paste text to broadcast..."></textarea>' +
        '<div class="send-bar" id="sendBar"></div>' +
        '</div>' +
        '</div>' +
        '<script>' +
        'var display=document.getElementById("display");' +
        'var inputBox=document.getElementById("inputBox");' +
        'var copyBtn=document.getElementById("copyBtn");' +
        'var sendBar=document.getElementById("sendBar");' +
        'var liveTxt=document.getElementById("liveTxt");' +
        'var lastData="";var sendTimer=null;var errCount=0;' +
        'function sendData(text){' +
        'sendBar.textContent="sending...";sendBar.className="send-bar sending";' +
        'fetch("/api/push",{method:"POST",' +
        'headers:{"Content-Type":"application/x-www-form-urlencoded"},' +
        'body:"data="+encodeURIComponent(text)})' +
        '.then(function(){sendBar.textContent="\u2713 sent";' +
        'setTimeout(function(){sendBar.textContent="";sendBar.className="send-bar";},1500);})' +
        '.catch(function(){sendBar.textContent="send failed";sendBar.className="send-bar err";});}' +
        'inputBox.addEventListener("input",function(){' +
        'clearTimeout(sendTimer);sendTimer=setTimeout(function(){sendData(inputBox.value);},450);});' +
        'function copyText(){var t=display.innerText;' +
        'if(navigator.clipboard)navigator.clipboard.writeText(t).catch(fbCopy);else fbCopy();' +
        'copyBtn.innerHTML="\u2713&nbsp;Copied!";copyBtn.classList.add("ok");' +
        'setTimeout(function(){copyBtn.innerHTML="\u2398&nbsp;Copy";copyBtn.classList.remove("ok");},1600);}' +
        'function fbCopy(){var r=document.createRange();r.selectNodeContents(display);' +
        'var s=window.getSelection();s.removeAllRanges();s.addRange(r);' +
        'document.execCommand("copy");s.removeAllRanges();}' +
        'function poll(){fetch("/api/pull").then(function(r){return r.text();})' +
        '.then(function(t){errCount=0;liveTxt.textContent="live";' +
        'if(t!==lastData){lastData=t;display.innerText=t;}})' +
        '.catch(function(){errCount++;if(errCount>2)liveTxt.textContent="offline";});}' +
        'setInterval(poll,1200);poll();' +
        '</script></body></html>';
      Exit;
    end;

    // -- 404 ---------------------------------------------------------------
    AResponse.Code        := 404;
    AResponse.Content     := 'Not found';
    AResponse.ContentType := 'text/plain';

  except
    on E: Exception do
    begin
      WriteLn('ERROR: ', E.Message);
      try
        AResponse.Code        := 500;
        AResponse.Content     := 'Internal error';
        AResponse.ContentType := 'text/plain';
      except end;
    end;
  end;
end;

procedure TMyApplication.DoRun;
var
  Port: Word;
begin
  Port  := GetPortFromArgs;
  FLock := TCriticalSection.Create;
  FPush := '';
  FPull := '';

  WriteLn('Clipboard Sync Server -- http://0.0.0.0:', Port);
  WriteLn('  POST /api/push  -> receive clipboard from client');
  WriteLn('  GET  /api/pull  -> serve clipboard to clients');
  WriteLn('  GET  /          -> web UI');

  FHTTPServer           := TFPHTTPServer.Create(nil);
  FHTTPServer.Port      := Port;
  FHTTPServer.OnRequest := @HandleRequest;
  FHTTPServer.Active    := True;

  WriteLn('Press ENTER to stop...');
  ReadLn;

  FHTTPServer.Active := False;
  FreeAndNil(FHTTPServer);
  FreeAndNil(FLock);
  Terminate;
end;

function TMyApplication.GetPortFromArgs: Word;
var
  i: Integer;
begin
  Result := 8080;
  for i := 1 to ParamCount do
    if (ParamStr(i) = '-p') and (i < ParamCount) then
      Result := Word(StrToIntDef(ParamStr(i + 1), 8080));
end;

var
  App: TMyApplication;
begin
  App := TMyApplication.Create(nil);
  try
    App.Run;
  finally
    App.Free;
  end;
end.

