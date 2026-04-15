program project1;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, CustApp, fphttpserver, httpdefs, fphttpapp;

type
  TMyApplication = class(TCustomApplication)
  private
    function GetPortFromArgs: Word;
    procedure HandleRequest(Sender: TObject;
      var ARequest: TFPHTTPConnectionRequest;
      var AResponse: TFPHTTPConnectionResponse);
  protected
    procedure DoRun; override;
  end;

var
  HTTPServer: TFPHTTPServer;
  s: string;


  function TMyApplication.GetPortFromArgs: Word;
var
  i: Integer;
begin
  Result := 8080; // default

  for i := 1 to ParamCount do
  begin
    if (ParamStr(i) = '-p') and (i < ParamCount) then
      Result := StrToIntDef(ParamStr(i + 1), 8080);
  end;
end;


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
      begin
        s := inputText;
      end;

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
    <!DOCTYPE html> +
    <html> +
    <head> +
    <meta charset="utf-8"> +
    <meta name="viewport" content="width=device-width, initial-scale=1.0"> +
    <title>Pascal Server</title> +

    <style> +
    body { +
     margin:0; +
     background: linear-gradient(135deg,#0b0f14,#0f1720); +
     color:#eaeaea; +
     font-family: system-ui, -apple-system, Segoe UI, Roboto, monospace; +
    } +

    .container { +
     display:flex; +
     height:100vh; +
    } +

    .left { +
     width:50%; +
     padding:20px; +
     border-right:1px solid rgba(255,255,255,0.08); +
     overflow:auto; +
    } +

    .right { +
     width:50%; +
     padding:0; +
    } +

    .panel { +
     background: rgba(255,255,255,0.04); +
     border: 1px solid rgba(255,255,255,0.08); +
     border-radius: 12px; +
     overflow: hidden; +
     box-shadow: 0 10px 30px rgba(0,0,0,0.4); +
     display:flex; +
     flex-direction:column; +
     height:100%; +
    } +

    .topbar { +
     display:flex; +
     align-items:center; +
     justify-content:space-between; +
     padding:12px; +
     background: rgba(10,12,18,0.9); +
     backdrop-filter: blur(10px); +
     border-bottom:1px solid rgba(255,255,255,0.08); +
    } +

    #display { +
     padding:16px; +
     white-space:pre-wrap; +
     flex:1; +
     overflow:auto; +
    } +

    textarea { +
     width:100%; +
     height:100%; +
     background: transparent; +
     color:#eaeaea; +
     border:none; +
     padding:20px; +
     font-size:15px; +
     font-family: monospace; +
     resize:none; +
     outline:none; +
    } +

    button { +
     background: linear-gradient(135deg,#2b6cff,#1e40af); +
     color:#fff; +
     border:none; +
     padding:10px 18px; +
     border-radius:10px; +
     cursor:pointer; +
     font-family:inherit; +
     font-weight:600; +
     font-size:14px; +
    } +

    </style> +
    </head> +

    <body> +

    <div class="container"> +
     <div class="left"> +
       <div class="panel"> +
         <div class="topbar"> +
           <span>📄 Paste</span> +
           <button id="copyBtn">Copy</button> +
         </div> +
         <div id="display"> + safeText + </div> +
       </div> +
     </div> +

     <div class="right"> +
       <div class="panel"> +
         <textarea id="inputBox" placeholder="Write text..."></textarea> +
       </div> +
     </div> +
    </div> +

    <script> +
    const textarea=document.getElementById("inputBox"); +
    const display=document.getElementById("display"); +
    const copyBtn=document.getElementById("copyBtn"); +

    function sendData(){ +
    fetch("/api",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:"data="+encodeURIComponent(textarea.value)}) +
    .then(()=>display.innerText=textarea.value); +
    } +

    textarea.addEventListener("input",()=>setTimeout(sendData,400)); +

    setInterval(()=>{ +
    fetch("/api").then(r=>r.text()).then(t=>display.innerText=t); +
    },1000); +

    </script> +

    </body> +
    </html>;

    AResponse.ContentType := text/html;

  AResponse.ContentType := 'text/html';
end;

procedure TMyApplication.DoRun;
var
  Port: Word;
begin
    Port := GetPortFromArgs; // 👈 ONLY CHANGE USED

  Writeln('Server running on http://localhost:' + IntToStr(Port));
  Writeln('Use -p <port> to change port');



  HTTPServer := TFPHTTPServer.Create(nil);
  HTTPServer.Port := Port;
  HTTPServer.OnRequest := @HandleRequest;

  s := 'Hello, world!';

  HTTPServer.Active := True;



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
