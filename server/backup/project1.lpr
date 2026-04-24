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
    FS         : string;
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

    // ── OPTIONS (CORS preflight) ─────────────────────
    if ARequest.Method = 'OPTIONS' then
    begin
      AResponse.Code := 204;
      AResponse.CustomHeaders.Values['Access-Control-Allow-Origin']  := '*';
      AResponse.CustomHeaders.Values['Access-Control-Allow-Methods'] := 'GET, POST, OPTIONS';
      AResponse.CustomHeaders.Values['Access-Control-Allow-Headers'] := 'Content-Type';
      Exit;
    end;

    AResponse.CustomHeaders.Values['Access-Control-Allow-Origin'] := '*';

    // ── POST /api/push → klient wysyła swój schowek ──────────────────
    if (ARequest.Method = 'POST') and (ARequest.URI = '/api/push') then
    begin
      InputText := ARequest.ContentFields.Values['data'];
      if InputText <> '' then
      begin
        FLock.Enter;
        FS := InputText;
        FLock.Leave;
        WriteLn('  [PUSH] "', Copy(InputText, 1, 80), '"');
      end;
      AResponse.Code        := 200;
      AResponse.Content     := 'OK';
      AResponse.ContentType := 'text/plain';
      Exit;
    end;

    // ── GET /api/pull → klient pobiera aktualny string ───────────────
    if (ARequest.Method = 'GET') and (ARequest.URI = '/api/pull') then
    begin
      FLock.Enter;
      AResponse.Content := FS;
      FLock.Leave;
      AResponse.Code        := 200;
      AResponse.ContentType := 'text/plain; charset=utf-8';
      Exit;
    end;

    // ── GET /api → zwróć s (stary endpoint, dla kompatybilności) ─────
    if (ARequest.Method = 'GET') and (Pos('/api', ARequest.URI) = 1) then
    begin
      FLock.Enter;
      AResponse.Content := FS;
      FLock.Leave;
      AResponse.Code        := 200;
      AResponse.ContentType := 'text/plain; charset=utf-8';
      Exit;
    end;

    // ── POST /api → zapisz s (stary endpoint, dla kompatybilności) ───
    if (ARequest.Method = 'POST') and (Pos('/api', ARequest.URI) = 1) then
    begin
      InputText := ARequest.ContentFields.Values['data'];
      if InputText <> '' then
      begin
        FLock.Enter;
        FS := InputText;
        FLock.Leave;
        WriteLn('  [POST/api] "', Copy(InputText, 1, 60), '"');
      end;
      AResponse.Code        := 200;
      AResponse.Content     := 'OK';
      AResponse.ContentType := 'text/plain';
      Exit;
    end;

    // ── GET / → strona WWW ───────────────────────────
    if (ARequest.Method = 'GET') and
       ((ARequest.URI = '/') or (ARequest.URI = '')) then
    begin
      FLock.Enter;
      SafeText := EscapeHTML(FS);
      FLock.Leave;

      AResponse.Code        := 200;
      AResponse.ContentType := 'text/html; charset=utf-8';
      AResponse.CustomHeaders.Values['Content-Type'] := 'text/html; charset=utf-8';
      AResponse.Content :=
        '<!DOCTYPE html>' +
        '<html><head>' +
        '<meta charset="utf-8">' +
        '<meta name="viewport" content="width=device-width,initial-scale=1.0">' +
        '<title>Pascal Server</title>' +
        '<style>' +
        '*{box-sizing:border-box;margin:0;padding:0}' +
        'body{background:linear-gradient(135deg,#0b0f14,#0f1720);color:#eaeaea;' +
        'font-family:system-ui,-apple-system,Segoe UI,Roboto,monospace;' +
        'height:100vh;display:flex;flex-direction:column;overflow:hidden}' +
        '.container{display:flex;flex:1;overflow:hidden}' +
        '.pane{width:50%;display:flex;flex-direction:column;overflow:hidden}' +
        '.pane:first-child{border-right:1px solid rgba(255,255,255,0.08)}' +
        '.topbar{display:flex;align-items:center;justify-content:space-between;' +
        'padding:10px 14px;background:rgba(10,12,18,0.95);' +
        'border-bottom:1px solid rgba(255,255,255,0.08);flex-shrink:0}' +
        '.topbar span{font-size:13px;opacity:0.7;letter-spacing:.5px}' +
        'button{background:linear-gradient(135deg,#2b6cff,#1e40af);color:#fff;' +
        'border:none;padding:8px 16px;border-radius:8px;cursor:pointer;' +
        'font-family:inherit;font-weight:600;font-size:13px;transition:all .15s ease}' +
        'button:active{transform:scale(0.94);opacity:0.8}' +
        'button.copied{background:linear-gradient(135deg,#16a34a,#15803d)}' +
        '#display{flex:1;overflow:auto;padding:16px;white-space:pre-wrap;' +
        'word-break:break-word;font-size:14px;line-height:1.6}' +
        'textarea{flex:1;background:transparent;color:#eaeaea;border:none;' +
        'padding:16px;font-size:14px;font-family:monospace;resize:none;outline:none;line-height:1.6}' +
        '</style></head><body>' +
        '<div class="container">' +
        '<div class="pane">' +
        '<div class="topbar">' +
        '<span>Schowek serwera</span>' +
        '<button id="copyBtn" onclick="copyText()">Kopiuj</button>' +
        '</div>' +
        '<div id="display">' + SafeText + '</div>' +
        '</div>' +
        '<div class="pane">' +
        '<div class="topbar"><span>Wpisz / wklej</span></div>' +
        '<textarea id="inputBox" placeholder="Wpisz tekst..."></textarea>' +
        '</div>' +
        '</div>' +
        '<script>' +
        'var display  = document.getElementById("display");' +
        'var inputBox = document.getElementById("inputBox");' +
        'var copyBtn  = document.getElementById("copyBtn");' +
        'var lastData = "";' +
        'var sendTimer = null;' +
        'function sendData(text){' +
        '  fetch("/api/push",{method:"POST",' +
        '    headers:{"Content-Type":"application/x-www-form-urlencoded"},' +
        '    body:"data="+encodeURIComponent(text)});' +
        '}' +
        'inputBox.addEventListener("input",function(){' +
        '  clearTimeout(sendTimer);' +
        '  sendTimer = setTimeout(function(){ sendData(inputBox.value); }, 400);' +
        '});' +
        'function copyText(){' +
        '  var text = display.innerText;' +
        '  if(navigator.clipboard){' +
        '    navigator.clipboard.writeText(text).catch(fallbackCopy);' +
        '  } else { fallbackCopy(); }' +
        '  copyBtn.textContent = "Skopiowano!";' +
        '  copyBtn.classList.add("copied");' +
        '  setTimeout(function(){ copyBtn.textContent="Kopiuj"; copyBtn.classList.remove("copied"); }, 1500);' +
        '}' +
        'function fallbackCopy(){' +
        '  var r = document.createRange();' +
        '  r.selectNodeContents(display);' +
        '  var s = window.getSelection();' +
        '  s.removeAllRanges(); s.addRange(r);' +
        '  document.execCommand("copy");' +
        '  s.removeAllRanges();' +
        '}' +
        'function poll(){' +
        '  fetch("/api/pull").then(function(r){ return r.text(); })' +
        '    .then(function(t){' +
        '      if(t !== lastData){ lastData = t; display.innerText = t; }' +
        '    }).catch(function(){});' +
        '}' +
        'setInterval(poll, 1200); poll();' +
        '</script>' +
        '</body></html>';
      Exit;
    end;

    // ── 404 ──────────────────────────────────────────
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
  FS    := 'Hello, world!';

  WriteLn('Clipboard Server — http://0.0.0.0:', Port);
  WriteLn('  GET  /api/pull  → zwraca aktualny schowek');
  WriteLn('  POST /api/push  → zapisuje schowek (form: data=...)');
  WriteLn('  GET  /          → strona WWW');

  FHTTPServer           := TFPHTTPServer.Create(nil);
  FHTTPServer.Port      := Port;
  FHTTPServer.OnRequest := @HandleRequest;
  FHTTPServer.Active    := True;

  WriteLn('Nacisnij ENTER aby zatrzymac...');
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

