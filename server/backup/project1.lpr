program clipboard_server;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX} cthreads {$ENDIF},
  Classes, SysUtils, CustApp, fphttpserver, httpdefs, SyncObjs;

type
  TMyApplication = class(TCustomApplication)
  private
    FHTTPServer  : TFPHTTPServer;
    FLock        : TCriticalSection;
    FPull        : string;
    FAuthor      : string;
    FVersion     : Int64;
    FExeDir      : string;
    FFileName    : string;
    FFileSize    : Int64;
    FFilePath    : string;

    function  GetPortFromArgs: Word;
    procedure HandleRequest(Sender: TObject;
      var ARequest : TFPHTTPConnectionRequest;
      var AResponse: TFPHTTPConnectionResponse);
  protected
    procedure DoRun; override;
  end;

procedure LogMsg(const Msg: string); inline;
begin
  WriteLn('[', FormatDateTime('hh:nn:ss.zzz', Now), '] ', Msg);
  Flush(Output);
end;

function URIDecode(const S: string): string;
var
  i: Integer;
  c: Char;
  Hex: string;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    c := S[i];
    if (c = '%') and (i + 2 <= Length(S)) then
    begin
      Hex := '$' + S[i+1] + S[i+2];
      Result := Result + Chr(StrToIntDef(Hex, Ord('?')));
      Inc(i, 3);
    end
    else if c = '+' then
    begin
      Result := Result + ' ';
      Inc(i);
    end
    else
    begin
      Result := Result + c;
      Inc(i);
    end;
  end;
end;

function SafeFileName(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if S[i] in ['A'..'Z','a'..'z','0'..'9','_','-','.',' '] then
      Result := Result + S[i]
    else
      Result := Result + '_';
  if Result = '' then Result := 'upload';
end;

function GetFileSize(const APath: string): Int64;
var
  FS: TFileStream;
begin
  Result := 0;
  if not FileExists(APath) then Exit;
  FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    Result := FS.Size;
  finally
    FS.Free;
  end;
end;

function JSONEscape(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    case S[i] of
      '"':  Result := Result + '\"';
      '\':  Result := Result + '\\';
      #8:   Result := Result + '\b';
      #9:   Result := Result + '\t';
      #10:  Result := Result + '\n';
      #13:  Result := Result + '\r';
      #12:  Result := Result + '\f';
    else
      Result := Result + S[i];
    end;
end;

procedure TMyApplication.HandleRequest(Sender: TObject;
  var ARequest : TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
var
  InputText      : string;
  InputClient    : string;
  HTMLFile       : string;
  SL             : TStringList;
  RawName        : string;
  SafeName       : string;
  DestPath       : string;
  FS             : TFileStream;
  MS             : TMemoryStream;
  InfoJSON       : string;
  BufSize        : Int64;
  RawContent     : string;
  CurAuthor      : string;
  CurText        : string;
  CurVersion     : Int64;
  ExpectedVerStr : string;
  ExpectedVer    : Int64;
  ShouldUpdate   : Boolean;
begin
  try
    if ARequest.Method = 'OPTIONS' then
    begin
      AResponse.Code := 204;
      AResponse.CustomHeaders.Values['Access-Control-Allow-Origin']  := '*';
      AResponse.CustomHeaders.Values['Access-Control-Allow-Methods'] := 'GET, POST, OPTIONS';
      AResponse.CustomHeaders.Values['Access-Control-Allow-Headers'] :=
        'Content-Type, X-Filename, X-Filesize';
      Exit;
    end;

    AResponse.CustomHeaders.Values['Access-Control-Allow-Origin'] := '*';

    { POST /api/push }
    if (ARequest.Method = 'POST') and (ARequest.URI = '/api/push') then
    begin
      ExpectedVerStr := '';
      ExpectedVer    := -1;
      ShouldUpdate   := True;

      if Pos('text/plain', LowerCase(ARequest.ContentType)) > 0 then
      begin
        InputText   := ARequest.Content;
        InputClient := '';
      end
      else
      begin
        InputText      := ARequest.ContentFields.Values['data'];
        InputClient    := Trim(ARequest.ContentFields.Values['client']);
        ExpectedVerStr := Trim(ARequest.ContentFields.Values['expected_version']);
      end;

      // Optimistic locking: jedna sekcja krytyczna - sprawdzenie I zapis razem
      FLock.Enter;
      try
        if ExpectedVerStr <> '' then
        begin
          ExpectedVer := StrToInt64Def(ExpectedVerStr, -1);
          if ExpectedVer <> FVersion then
          begin
            // Konflikt wersji - ktos zdazyl przed nami
            ShouldUpdate := False;
            LogMsg('PUSH CONFLICT: expected=' + ExpectedVerStr +
                   ', current=' + IntToStr(FVersion));
          end;
        end;

        if ShouldUpdate and (InputText <> '') then
        begin
          Inc(FVersion);
          FPull   := InputText;
          FAuthor := InputClient;
          LogMsg('PUSH v' + IntToStr(FVersion) +
                 ' from=' + InputClient +
                 ' expected=' + ExpectedVerStr +
                 ' ' + IntToStr(Length(InputText)) + 'B');
          AResponse.Code    := 200;
          AResponse.Content := IntToStr(FVersion);
        end
        else if not ShouldUpdate then
        begin
          AResponse.Code    := 409;
          AResponse.Content := 'Conflict: expected=' + ExpectedVerStr +
                               ' current=' + IntToStr(FVersion);
        end
        else
        begin
          // InputText pusty
          AResponse.Code    := 200;
          AResponse.Content := IntToStr(FVersion);
        end;
      finally
        FLock.Leave;
      end;

      AResponse.ContentType := 'text/plain';
      Exit;
    end;

    { GET /api/pull — zachowany dla kompatybilnosci }
    if (ARequest.Method = 'GET') and (ARequest.URI = '/api/pull') then
    begin
      FLock.Enter;
      try
        AResponse.Content := IntToStr(FVersion) + #10 + FAuthor + #10 + FPull;
      finally
        FLock.Leave;
      end;
      AResponse.Code        := 200;
      AResponse.ContentType := 'text/plain; charset=utf-8';
      Exit;
    end;

    { GET /api/state — JSON: {"version":N,"author":"...","text":"..."} }
    if (ARequest.Method = 'GET') and (ARequest.URI = '/api/state') then
    begin
      FLock.Enter;
      try
        CurAuthor  := FAuthor;
        CurText    := FPull;
        CurVersion := FVersion;
      finally
        FLock.Leave;
      end;
      AResponse.Code        := 200;
      AResponse.ContentType := 'application/json; charset=utf-8';
      AResponse.Content     := '{"version":'  + IntToStr(CurVersion) +
                               ',"author":"'  + JSONEscape(CurAuthor) +
                               '","text":"'   + JSONEscape(CurText) + '"}';
      Exit;
    end;

    { POST /api/file }
    if (ARequest.Method = 'POST') and (ARequest.URI = '/api/file') then
    begin
      RawName  := URIDecode(ARequest.CustomHeaders.Values['X-Filename']);
      SafeName := SafeFileName(RawName);
      if SafeName = '' then SafeName := 'upload';

      DestPath := FExeDir + 'file' + PathDelim + SafeName;

      FLock.Enter;
      try
        if (FFilePath <> '') and FileExists(FFilePath) then
        begin
          LogMsg('FILE del old: ' + FFilePath);
          DeleteFile(FFilePath);
        end;
        FFileName := '';
        FFilePath := '';
        FFileSize := 0;
      finally
        FLock.Leave;
      end;

      RawContent := ARequest.Content;
      try
        FS := TFileStream.Create(DestPath, fmCreate);
        try
          if Length(RawContent) > 0 then
            FS.Write(RawContent[1], Length(RawContent));
        finally
          FS.Free;
        end;
      except
        on E: Exception do
        begin
          LogMsg('FILE write ERROR: ' + E.Message);
          AResponse.Code        := 500;
          AResponse.Content     := 'Write failed: ' + E.Message;
          AResponse.ContentType := 'text/plain';
          Exit;
        end;
      end;

      BufSize := GetFileSize(DestPath);

      FLock.Enter;
      try
        FFileName := RawName;
        FFilePath := DestPath;
        FFileSize := BufSize;
      finally
        FLock.Leave;
      end;

      LogMsg('FILE saved: ' + SafeName + ' (' + IntToStr(BufSize) + 'B)');
      AResponse.Code        := 200;
      AResponse.Content     := 'OK';
      AResponse.ContentType := 'text/plain';
      Exit;
    end;

    { GET /api/file }
    if (ARequest.Method = 'GET') and (ARequest.URI = '/api/file') then
    begin
      FLock.Enter;
      try
        DestPath := FFilePath;
        RawName  := FFileName;
        BufSize  := FFileSize;
      finally
        FLock.Leave;
      end;

      if (DestPath = '') or not FileExists(DestPath) then
      begin
        AResponse.Code        := 404;
        AResponse.Content     := 'No file on server';
        AResponse.ContentType := 'text/plain';
        Exit;
      end;

      try
        MS := TMemoryStream.Create;
        MS.LoadFromFile(DestPath);
        MS.Position := 0;
      except
        on E: Exception do
        begin
          LogMsg('FILE read ERROR: ' + E.Message);
          AResponse.Code        := 500;
          AResponse.Content     := 'Read failed: ' + E.Message;
          AResponse.ContentType := 'text/plain';
          Exit;
        end;
      end;

      AResponse.Code        := 200;
      AResponse.ContentType := 'application/octet-stream';
      AResponse.CustomHeaders.Values['Content-Disposition'] :=
        'attachment; filename="' + SafeFileName(RawName) + '"';
      AResponse.CustomHeaders.Values['Content-Length'] :=
        IntToStr(MS.Size);
      AResponse.ContentStream := MS;

      LogMsg('FILE send: ' + RawName + ' (' + IntToStr(BufSize) + 'B)');
      Exit;
    end;

    { GET /api/fileinfo }
    if (ARequest.Method = 'GET') and (ARequest.URI = '/api/fileinfo') then
    begin
      FLock.Enter;
      try
        if FFileName <> '' then
          InfoJSON := '{"name":"' +
            StringReplace(FFileName, '"', '\"', [rfReplaceAll]) +
            '","size":' + IntToStr(FFileSize) + '}'
        else
          InfoJSON := '';
      finally
        FLock.Leave;
      end;
      AResponse.Code        := 200;
      AResponse.Content     := InfoJSON;
      AResponse.ContentType := 'application/json; charset=utf-8';
      Exit;
    end;

    { GET / — index.html }
    if (ARequest.Method = 'GET') and
       ((ARequest.URI = '/') or (ARequest.URI = '')) then
    begin
      HTMLFile := FExeDir + 'index.html';
      if not FileExists(HTMLFile) then
      begin
        AResponse.Code        := 404;
        AResponse.Content     := 'index.html not found in ' + FExeDir;
        AResponse.ContentType := 'text/plain';
        Exit;
      end;
      SL := TStringList.Create;
      try
        SL.LoadFromFile(HTMLFile);
        AResponse.Content := SL.Text;
      finally
        SL.Free;
      end;
      AResponse.Code        := 200;
      AResponse.ContentType := 'text/html; charset=utf-8';
      Exit;
    end;

    { 404 }
    AResponse.Code        := 404;
    AResponse.Content     := 'Not found: ' + ARequest.URI;
    AResponse.ContentType := 'text/plain';
    LogMsg('404 ' + ARequest.Method + ' ' + ARequest.URI);

  except
    on E: Exception do
    begin
      LogMsg('REQUEST ERROR: ' + E.Message);
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
  Port      := GetPortFromArgs;
  FExeDir   := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  FLock     := TCriticalSection.Create;
  FPull     := '';
  FAuthor   := '';
  FVersion  := 0;
  FFileName := '';
  FFilePath := '';
  FFileSize := 0;

  ForceDirectories(FExeDir + 'file');

  LogMsg('Clipboard Sync Server -- http://0.0.0.0:' + IntToStr(Port));
  WriteLn('  POST /api/push     -> wyslij tekst (+ optional expected_version)');
  WriteLn('  GET  /api/pull     -> odbierz tekst (legacy)');
  WriteLn('  GET  /api/state    -> JSON {version, author, text}');
  WriteLn('  POST /api/file     -> wgraj plik');
  WriteLn('  GET  /api/file     -> pobierz plik');
  WriteLn('  GET  /api/fileinfo -> polling: nazwa + rozmiar');
  WriteLn('  GET  /             -> ', FExeDir, 'index.html');

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

