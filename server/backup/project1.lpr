program project1;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, CustApp, fphttpserver, httpdefs, fphttpapp;

type
  { TMyApplication }
  TMyApplication = class(TCustomApplication)
  private
    procedure HandleRequest(Sender: TObject;
      var ARequest: TFPHTTPConnectionRequest;
      var AResponse: TFPHTTPConnectionResponse);
  protected
    procedure DoRun; override;
  end;

var
  HTTPServer: TFPHTTPServer;
  s: string;

{ TMyApplication }

procedure TMyApplication.HandleRequest(Sender: TObject;
  var ARequest: TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);

  function EscapeHTML(const str: string): string;
  begin
    Result := StringReplace(str, '&', '&amp;', [rfReplaceAll]);
    Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
    Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  end;

var
  inputText: string;
  safeText: string;

begin
  // =========================
  // 🔥 API ENDPOINT
  // =========================
  Writeln('URI: ', ARequest.URI);

  if Pos('/api', ARequest.URI) = 1 then
  begin
    if ARequest.Method = 'GET' then
    begin
      AResponse.Content := s;
      AResponse.ContentType := 'text/plain';
      Exit;
    end;

    if ARequest.Method = 'POST' then
    begin
      inputText := ARequest.ContentFields.Values['data'];

      if inputText <> '' then
        s := inputText;

      AResponse.Content := 'OK';
      AResponse.ContentType := 'text/plain';
      Exit;
    end;
  end;

  // =========================
  // 🌐 WEB UI
  // =========================
  safeText := EscapeHTML(s);

  AResponse.Content :=
  '<!DOCTYPE html>' +
  '<html>' +
  '<head>' +
  '<meta charset="utf-8">' +
  '<title>Pascal Server</title>' +

  '<style>' +
  'body { margin:0; background:#0d0d0d; color:#eaeaea; font-family: monospace; }' +
  '.container { display:flex; height:100vh; }' +
  '.left { width:50%; padding:20px; border-right:1px solid #333; white-space: pre-wrap; overflow:auto; }' +
  '.right { width:50%; padding:0; }' +
  'textarea { width:100%; height:100%; background:#111; color:#eaeaea; border:none; padding:20px; font-size:16px; font-family: monospace; resize:none; outline:none; }' +
  '.topbar { position:sticky; top:0; background:#0d0d0d; padding:10px; border-bottom:1px solid #333; }' +
  'button { background:#222; color:#fff; border:1px solid #444; padding:6px 10px; cursor:pointer; font-family:monospace; }' +
  '</style>' +
  '</head>' +

  '<body>' +
  '<div class="container">' +

  '<div class="left">' +
  '<div class="topbar"><button id="copyBtn">COPY</button></div>' +
  '<div id="display">' + safeText + '</div>' +
  '</div>' +

  '<div class="right">' +
  '<textarea id="inputBox" placeholder="write text..."></textarea>' +
  '</div>' +

  '</div>' +

  '<script>' +

  'const textarea = document.getElementById("inputBox");' +
  'const display = document.getElementById("display");' +
  'const copyBtn = document.getElementById("copyBtn");' +

  // 🔁 SEND → API
  'function sendData() {' +
  '  fetch("/api", {' +
  '    method: "POST",' +
  '    headers: { "Content-Type": "application/x-www-form-urlencoded" },' +
  '    body: "data=" + encodeURIComponent(textarea.value)' +
  '  })' +
  '  .then(r => r.text())' +
  '  .then(t => display.innerText = textarea.value);' +
  '}' +

  'let timeout = null;' +
  'textarea.addEventListener("input", () => {' +
  '  clearTimeout(timeout);' +
  '  timeout = setTimeout(sendData, 400);' +
  '});' +

  // 🔁 FETCH → API
  'setInterval(() => {' +
  '  fetch("/api")' +
  '    .then(r => r.text())' +
  '    .then(text => {' +
  '      display.innerText = text;' +
  '    });' +
  '}, 1000);' +

  // 📋 COPY
  'copyBtn.addEventListener("click", async () => {' +
  '  const text = display.innerText;' +
  '  try {' +
  '    await navigator.clipboard.writeText(text);' +
  '    copyBtn.innerText = "COPIED";' +
  '    setTimeout(() => copyBtn.innerText = "COPY", 1000);' +
  '  } catch(e) {' +
  '    const range = document.createRange();' +
  '    range.selectNodeContents(display);' +
  '    const sel = window.getSelection();' +
  '    sel.removeAllRanges();' +
  '    sel.addRange(range);' +
  '    document.execCommand("copy");' +
  '  }' +
  '});' +

  '</script>' +
  '</body>' +
  '</html>';

  AResponse.ContentType := 'text/html';
end;

procedure TMyApplication.DoRun;
begin
  HTTPServer := TFPHTTPServer.Create(nil);
  HTTPServer.Port := 8080;
  HTTPServer.OnRequest := @HandleRequest;

  s := 'Hello, world!';

  HTTPServer.Active := True;

  Writeln('Server działa: http://localhost:8080');
  Writeln('API endpoint: http://localhost:8080/api');

  ReadLn;

  HTTPServer.Free;
  Terminate;
end;

var
  Application: TMyApplication;

begin
  Application := TMyApplication.Create(nil);
  Application.Run;
  Application.Free;
end.
