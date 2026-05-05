program clipboard_server;

{$mode objfpc}{$H+}

{ ============================================================
  clipboard_server  Ver. 3  —  endpoint /api/state
  ============================================================
  Dodano GET /api/state zwracajacy JSON {author, text}.
  Pozostale endpointy bez zmian.
  ============================================================ }

{ ============================================================
  clipboard_server  Ver. 4  —  Optimistic Locking
  ============================================================
  POST /api/push przyjmuje opcjonalny parametr expected_version.
    expected_version == FVersion → zapisz, zwroc 200
    expected_version != FVersion → zwroc 409 Conflict
  Brak expected_version → zapisz bez sprawdzania (kompatybilnosc
  z www i starymi klientami).
  Sprawdzenie i zapis w jednej sekcji krytycznej — brak wyścigu
  między sprawdzeniem a zapisem.
  ============================================================ }

{ ============================================================
  clipboard_server  Ver. 5  —  Base64 dla tekstu schowka
  ============================================================

  Problem z Ver. 4:
  ─────────────────────────────────────────────────────────────
  GET /api/state zwracal tekst schowka wewnatrz JSON przez
  JSONEscape (newline→\n, tab→\t, backslash→\\ itd.).
  Klient Ver. 4 pytal /api/state, parsowal JSON, ale NIE
  deSCAPOWAL sekwencji escape — widzial \n jako dwa znaki
  zamiast jednego. Rozmiary nigdy sie nie zgadzaly przy
  tekstach z programowania (duzo znakow specjalnych).
  Efekt: TextLocal != ServerText zawsze → CASE C (czekaj)
  lub bledne PULL ktore nadpisywalo schowek uzytkownika.

  Rozwiazanie:
  ─────────────────────────────────────────────────────────────
  FPull przechowywany jest teraz jako Base64 (klient wysyla
  Base64 w parametrze data=).

  GET /api/state zwraca pole "text_b64" zamiast "text":
    {"version":N,"author":"IP","text_b64":"BASE64"}
  Base64 uzywa tylko znakow A-Za-z0-9+/= — zadnych znakow
  specjalnych, zadnego JSON-escapingu, zadnych problemow
  z porownaniem rozmiarow.

  GET /api/pull (legacy) zwraca Base64 jako trzecia linia
  (zamiast surowego tekstu) — stare klienty przestana
  dzialac poprawnie, ale /api/pull nie jest juz uzywany.

  POST /api/push z text/plain (www):
  ─────────────────────────────────────────────────────────────
  Przegladarka wysyla surowy tekst przez text/plain.
  Serwer sam koduje go do Base64 przed zapisem do FPull.
  Dzieki temu FPull ZAWSZE zawiera Base64, niezaleznie
  od zrodla (klient Pascal lub www).

  Zmiana w kodzie wzgledem Ver. 4:
  ─────────────────────────────────────────────────────────────
  + funkcja EncodeBase64(s) — FPC unit base64
  + w POST /api/push: jesli text/plain → zakoduj do B64
  + w GET /api/state: zwroc "text_b64" zamiast "text",
    bez JSONEscape (Base64 nie wymaga escapingu)
  + JSONEscape pozostaje dla pola "author" (IP, bezpieczne)
  Wszystko inne identyczne z Ver. 4.
  ============================================================ }

uses
  {$IFDEF UNIX} cthreads {$ENDIF},
  Classes, SysUtils, CustApp, fphttpserver, httpdefs, SyncObjs, base64;

type
  TMyApplication = class(TCustomApplication)
  private
    FHTTPServer  : TFPHTTPServer;
    FLock        : TCriticalSection;
    FPull        : string;   // ZAWSZE przechowywany jako Base64
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

{ ── Pomocnicze ────────────────────────────────────────────── }

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

// Escape tylko dla krotkich pol (author = IP).
// Pole text_b64 jest Base64 — nie wymaga zadnego escapingu.
function JSONEscapeSimple(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    case S[i] of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
    else
      Result := Result + S[i];
    end;
end;

// Koduje surowy tekst do Base64.
// Wynik zawiera tylko A-Za-z0-9+/= — bezpieczny w JSON i HTTP.
// FPull zawsze przechowuje Base64 — niezaleznie od zrodla.
function EncodeBase64Str(const S: string): string;
var
  SS  : TStringStream;
  Enc : TBase64EncodingStream;
  Out : TStringStream;
begin
  Result := '';
  if S = '' then Exit;
  SS  := TStringStream.Create(S);
  Out := TStringStream.Create('');
  try
    Enc := TBase64EncodingStream.Create(Out);
    try
      Enc.CopyFrom(SS, SS.Size);
    finally
      Enc.Free;  // Free wymusza flush bufora
    end;
    Result := Out.DataString;
  finally
    Out.Free;
    SS.Free;
  end;
end;

{ ── Glowna obsluga zadan ──────────────────────────────────── }

procedure TMyApplication.HandleRequest(Sender: TObject;
  var ARequest : TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
var
  InputData      : string;   // Base64 od klienta Pascal LUB surowy tekst od www
  InputClient    : string;
  ExpectedVerStr : string;
  ExpectedVer    : Int64;
  ShouldUpdate   : Boolean;
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
  CurPull        : string;   // Base64
  CurVersion     : Int64;
begin
  try
    { OPTIONS }
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

    { ── POST /api/push ──────────────────────────────────────
      Klient Pascal wysyla data= jako Base64.
      Przegladarka (www) wysyla surowy tekst jako text/plain —
      serwer sam koduje go do Base64 przed zapisem.
      FPull zawsze zawiera Base64. }
    if (ARequest.Method = 'POST') and (ARequest.URI = '/api/push') then
    begin
      ExpectedVerStr := '';
      ExpectedVer    := -1;
      ShouldUpdate   := True;

      if Pos('text/plain', LowerCase(ARequest.ContentType)) > 0 then
      begin
        // Zrodlo: www — surowy tekst, kodujemy do Base64
        InputData   := EncodeBase64Str(ARequest.Content);
        InputClient := '';
        // www nie wysyla expected_version — brak optimistic locking
      end
      else
      begin
        // Zrodlo: klient Pascal — data= juz jest Base64
        InputData      := ARequest.ContentFields.Values['data'];
        InputClient    := Trim(ARequest.ContentFields.Values['client']);
        ExpectedVerStr := Trim(ARequest.ContentFields.Values['expected_version']);
      end;

      // Sprawdzenie wersji I zapis w jednej sekcji krytycznej
      FLock.Enter;
      try
        if ExpectedVerStr <> '' then
        begin
          ExpectedVer := StrToInt64Def(ExpectedVerStr, -1);
          if ExpectedVer <> FVersion then
          begin
            ShouldUpdate := False;
            LogMsg('PUSH CONFLICT from=' + InputClient +
                   ' expected=' + ExpectedVerStr +
                   ' current='  + IntToStr(FVersion));
          end;
        end;

        if ShouldUpdate and (InputData <> '') then
        begin
          Inc(FVersion);
          FPull   := InputData;   // Base64
          FAuthor := InputClient;
          LogMsg('PUSH v' + IntToStr(FVersion) +
                 ' from='     + InputClient +
                 ' expected=' + ExpectedVerStr +
                 ' b64='      + IntToStr(Length(InputData)) + 'B');
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
          AResponse.Code    := 200;
          AResponse.Content := IntToStr(FVersion);
        end;
      finally
        FLock.Leave;
      end;

      AResponse.ContentType := 'text/plain';
      Exit;
    end;

    { ── GET /api/pull — legacy, zwraca Base64 jako trzecia linia ── }
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

    { ── GET /api/state — JSON z text_b64 zamiast text ──────
      Kluczowa zmiana w Ver. 5: pole "text_b64" zawiera Base64.
      Klient dekoduje Base64 po stronie klienta.
      Brak JSONEscape dla tekstu — Base64 nie zawiera znakow
      specjalnych wiec jest bezpieczny w JSON bez escapingu. }
    if (ARequest.Method = 'GET') and (ARequest.URI = '/api/state') then
    begin
      FLock.Enter;
      try
        CurAuthor  := FAuthor;
        CurPull    := FPull;    // Base64
        CurVersion := FVersion;
      finally
        FLock.Leave;
      end;
      AResponse.Code        := 200;
      AResponse.ContentType := 'application/json; charset=utf-8';
      // text_b64 nie wymaga JSONEscape — Base64 jest bezpieczny w JSON
      AResponse.Content :=
        '{"version":'   + IntToStr(CurVersion) +
        ',"author":"'   + JSONEscapeSimple(CurAuthor) + '"' +
        ',"text_b64":"' + CurPull + '"}';
      Exit;
    end;

    { ── POST /api/file — bez zmian ─────────────────────────── }
    if (ARequest.Method = 'POST') and (ARequest.URI = '/api/file') then
    begin
      RawName  := URIDecode(ARequest.CustomHeaders.Values['X-Filename']);
      SafeName := SafeFileName(RawName);
      if SafeName = '' then SafeName := 'upload';

     DestPath := FExeDir + 'file' + PathDelim + SafeName;

// Upewnij sie ze katalog istnieje (zabezpieczenie gdyby ktos usnal go recznie)
ForceDirectories(FExeDir + 'file');

FLock.Enter;
try
  // Skasuj poprzedni plik (dowolna nazwa) jesli istnieje
  if (FFilePath <> '') and FileExists(FFilePath) then
  begin
    LogMsg('FILE del old: ' + FFilePath);
    DeleteFile(FFilePath);
  end;
  // Jesli nowy plik ma ta sama nazwe co stary, FFilePath == DestPath
  // i powyzszy DeleteFile juz go usunal. Jesli jednak FFilePath bylo puste
  // (pierwszy upload) ale plik o tej nazwie juz fizycznie istnieje
  // (np. po restarcie serwera), tez go usun.
  if (DestPath <> FFilePath) and FileExists(DestPath) then
  begin
    LogMsg('FILE del existing: ' + DestPath);
    DeleteFile(DestPath);
  end;
  FFileName := '';
  FFilePath := '';
  FFileSize := 0;
finally
  FLock.Leave;
end;

      LogMsg('FILE saved: ' + SafeName + ' (' + IntToStr(BufSize) + 'B)');
      AResponse.Code        := 200;
      AResponse.Content     := 'OK';
      AResponse.ContentType := 'text/plain';
      Exit;
    end;

    { ── GET /api/file — bez zmian ──────────────────────────── }
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

    { ── GET /api/fileinfo — bez zmian ──────────────────────── }
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

    { ── GET / — index.html — bez zmian ─────────────────────── }
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

  LogMsg('Clipboard Sync Server Ver.5 -- http://0.0.0.0:' + IntToStr(Port));
  WriteLn('  POST /api/push     -> wyslij tekst (data=BASE64, opt. expected_version)');
  WriteLn('  GET  /api/pull     -> legacy (zwraca Base64)');
  WriteLn('  GET  /api/state    -> JSON {version, author, text_b64}');
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
