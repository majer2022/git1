                                       program ClipboardSL;

{$mode objfpc}{$H+}

{ ============================================================
  ClipboardSL  Ver. 3  â  logika synchronizacji
  ============================================================

  Zmienne stanu klienta:
    TextLocal      â aktualny tekst w lokalnym schowku
    LastPulled     â ostatni tekst POBRANY z serwera (lub wysÅany)
    ServerText     â tekst ktÃ³ry serwer aktualnie trzyma
    ServerAuthor   â ClientID ktÃ³ry ostatnio zrobiÅ PUSH na serwerze
    ClientID       â wÅasny IP tego klienta

  Algorytm (co sekundÄ):
  âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  1. TextLocal  := GetClipboard()
  2. ServerText, ServerAuthor := GET /api/state

  3. jeÅli TextLocal == ServerText:
       â stan zsynchronizowany, nic nie rÃ³b

  4. jeÅli TextLocal != ServerText:

       A) TextLocal != LastPulled
          â uÅ¼ytkownik skopiowaÅ coÅ nowego lokalnie
          â PUSH niezaleÅ¼nie od tego kto jest ServerAuthor
          â LastPulled := TextLocal

       B) TextLocal == LastPulled  AND  ServerAuthor != ClientID
          â lokalny schowek nie zmieniÅ siÄ od ostatniego pobrania
          â ktoÅ inny (inny klient lub www) zmieniÅ serwer
          â PULL: SetClipboard(ServerText), LastPulled := ServerText

       C) TextLocal == LastPulled  AND  ServerAuthor == ClientID
          â serwer ma inny tekst niÅ¼ my, ale to MY byliÅmy ostatnim
            autorem i lokalny schowek siÄ nie zmieniÅ
          â sytuacja niespÃ³jna â nic nie rÃ³b, czekaj

  Dlaczego to dziaÅa lepiej niÅ¼ Ver. 2:
  âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  Ver. 2 decydowaÅ tylko na podstawie ServerAuthor.
  BÅÄd: gdy author="" (www lub ÅwieÅ¼y serwer), klient robiÅ
  PULL i nadpisywaÅ schowek uÅ¼ytkownika danymi z serwera.
  Ver. 3 Åledzi LastPulled â jeÅli lokalny != LastPulled,
  uÅ¼ytkownik coÅ skopiowaÅ â zawsze PUSH.
  ============================================================ }

{ ============================================================
  ClipboardSL  Ver. 4  â  Optimistic Locking
  ============================================================

  Problem z Ver. 3:
  âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  Przy duÅ¼ych stringach transfer trwa ponad sekundÄ. W tym
  czasie drugi klient moÅ¼e zdÄÅ¼yÄ zrobiÄ PUSH i nadpisaÄ
  serwer. Klient ktÃ³ry wysÅaÅ duÅ¼y string dostaje 200, ale
  serwer juÅ¼ ma dane od kogoÅ innego â duÅ¼y string ginie.

  RozwiÄzanie:
  âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  GET /api/state zwraca "version":N.
  Klient wysyÅa expected_version=N przy kaÅ¼dym PUSH.
  Serwer:
    FVersion == expected_version â zapisz, zwrÃ³Ä 200
    FVersion != expected_version â zwrÃ³Ä 409, nic nie zapisuj
  Klient po 409 nie aktualizuje LastPulled â retry w nast. iteracji.

  Nowa zmienna:
    ServerVersion â ostatnia wersja z GET /api/state
  ============================================================ }

{ ============================================================
  ClipboardSL  Ver. 5  â  Base64 dla tekstu schowka
  ============================================================

  Problem z Ver. 4:
  âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  GET /api/state zwracaÅ tekst przez JSONEscape (serwer).
  Parser klienta ParseStateJSON NIE dekodowaÅ sekwencji
  escape â widziaÅ \n jako dwa znaki zamiast jednego.
  Przy tekstach z programowania (duÅ¼e iloÅci znakÃ³w specjalnych:
  nawiasy, backslash, cudzysÅÃ³w, newline) rozmiary nigdy siÄ
  nie zgadzaÅy: TextLocal != ServerText zawsze â klient
  wpadaÅ w CASE C (czekaj w nieskoÅczonoÅÄ) lub robiÅ bÅÄdny
  PULL nadpisujÄc schowek.

  RozwiÄzanie â Base64 wszÄdzie:
  âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  Klient ZAWSZE koduje tekst do Base64 przed wysÅaniem PUSH.
  Serwer przechowuje i zwraca Base64 bez Å¼adnego przetwarzania.
  GET /api/state zwraca pole "text_b64" zamiast "text":
    {"version":N,"author":"IP","text_b64":"BASE64..."}

  Base64 uÅ¼ywa tylko A-Za-z0-9+/= â zero znakÃ³w specjalnych,
  zero problemÃ³w z JSON, HTTP, newline, null, Unicode.

  Klient po otrzymaniu /api/state:
    1. dekoduje text_b64 â ServerText (surowy tekst)
    2. porÃ³wnuje ServerText z TextLocal (oba surowe)
    3. decyzja PUSH/PULL/czekaj na surowych stringach

  Przy PUSH wysyÅa Base64 jako parametr data=.
  Serwer Ver. 5 sam koduje tekst z www (text/plain) do Base64
  przed zapisem â FPull zawsze Base64 niezaleÅ¼nie od ÅºrÃ³dÅa.

  Narzut rozmiaru: ~33% â przy LAN bez znaczenia.

  Nowe funkcje:
    EncodeBase64(s) â string â Base64
    DecodeBase64(s) â Base64 â string

  Nowa flaga:
    -d  wÅÄcza linie [DBG] (domyÅlnie wyÅÄczone)
        Bez -d output jest czysty, tylko kluczowe zdarzenia.
        Z -d identyczne zachowanie jak Ver. 4-DEBUG.

  KompatybilnoÅÄ:
    Wymaga serwera Ver. 5 (pole text_b64 w /api/state).
    JeÅli serwer zwrÃ³ci stare "text" bez "text_b64",
    klient zaloguje WARNING i nie bÄdzie synchronizowaÅ.
  ============================================================ }

uses
  Classes, SysUtils, Process, fphttpclient, HTTPDefs, base64;

var
  SERVER_URL : string;
  ServerIP   : string  = '192.168.1.212';
  ServerPort : string  = '8080';
  DebugMode  : Boolean = False;   // wÅÄczane przez -d

  { ââ Logowanie ââââââââââââââââââââââââââââââââââââââââââââ }

  procedure Log(const Msg: string); inline;
  begin
    WriteLn('[', FormatDateTime('hh:nn:ss.zzz', Now), '] ', Msg);
    Flush(Output);
  end;

  // Linie [DBG] â tylko gdy uruchomiono z -d
  procedure LogD(const Msg: string); inline;
  begin
    if not DebugMode then Exit;
    WriteLn('[', FormatDateTime('hh:nn:ss.zzz', Now), '] [DBG] ', Msg);
    Flush(Output);
  end;

  { ââ Argumenty ââââââââââââââââââââââââââââââââââââââââââââ }

  procedure ShowHelp;
  begin
    WriteLn('ClipboardSL Ver. 5 -- clipboard sync over LAN');
    WriteLn('');
    WriteLn('Usage:  ./ClipboardSL -a <IP> -p <PORT> [-d]');
    WriteLn('  -a <ip>    server address (default: 192.168.1.204)');
    WriteLn('  -p <port>  server port    (default: 8080)');
    WriteLn('  -d         enable debug logging ([DBG] lines)');
    WriteLn('  -h         show this help');
  end;

  procedure ParseArgs;
  var
    i: Integer;
  begin
    i := 1;
    while i <= ParamCount do
    begin
      if (ParamStr(i) = '-h') or (ParamStr(i) = '--help') then
        begin ShowHelp; Halt; end
      else if (ParamStr(i) = '-a') and (i < ParamCount) then
        begin ServerIP := ParamStr(i+1); Inc(i); end
      else if (ParamStr(i) = '-p') and (i < ParamCount) then
        begin ServerPort := ParamStr(i+1); Inc(i); end
      else if ParamStr(i) = '-d' then
        DebugMode := True;
      Inc(i);
    end;
  end;

  { ââ Base64 âââââââââââââââââââââââââââââââââââââââââââââââ }

  // Koduje dowolny string (znaki specjalne, newline, null,
  // Unicode) do Base64. Wynik bezpieczny w JSON i HTTP.
  function EncodeBase64(const S: string): string;
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
        Enc.Free;   // Free wymusza flush bufora Base64
      end;
      Result := Out.DataString;
    finally
      Out.Free;
      SS.Free;
    end;
  end;

  // Dekoduje Base64 â oryginalny string.
  // Wynik byte-for-byte identyczny z tym co weszÅo do EncodeBase64.
  //
  // Ver. 5.1 â czyta pÄtlÄ z buforem 4KB zamiast Dec.Size.
  // TBase64DecodingStream nie obsÅuguje wÅaÅciwoÅci Size przy duÅ¼ych
  // danych â wywoÅanie Dec.Size rzucaÅo "Stream read error" dla
  // tekstÃ³w >~100KB. PÄtla read do BytesRead=0 jest odporna na
  // dowolny rozmiar danych.
  function DecodeBase64(const S: string): string;
  var
    SS        : TStringStream;
    Dec       : TBase64DecodingStream;
    OutStr    : TStringStream;
    Buffer    : array[0..4095] of Byte;
    BytesRead : Integer;
  begin
    Result := '';
    if S = '' then Exit;
    SS     := TStringStream.Create(S);
    OutStr := TStringStream.Create('');
    try
      Dec := TBase64DecodingStream.Create(SS, bdmMIME);
      try
        repeat
          BytesRead := Dec.Read(Buffer, SizeOf(Buffer));
          if BytesRead > 0 then
            OutStr.Write(Buffer, BytesRead);
        until BytesRead = 0;
      finally
        Dec.Free;
      end;
      Result := OutStr.DataString;
    finally
      OutStr.Free;
      SS.Free;
    end;
  end;

  { ââ System âââââââââââââââââââââââââââââââââââââââââââââââ }

  function GetLocalIP: string;
  var
    P     : TProcess;
    SL    : TStringList;
    Parts : TStringList;
    Raw   : string;
    i     : Integer;
  begin
    Result := '';
    P  := TProcess.Create(nil);
    SL := TStringList.Create;
    try
      P.Executable := 'hostname';
      P.Parameters.Add('-I');
      P.Options := [poUsePipes, poWaitOnExit];
      P.Execute;
      SL.LoadFromStream(P.Output);
      Raw := Trim(SL.Text);
      LogD('hostname -I raw: "' + Raw + '"');
      Parts := TStringList.Create;
      try
        Parts.Delimiter     := ' ';
        Parts.DelimitedText := Raw;
        LogD('parsed ' + IntToStr(Parts.Count) + ' address(es):');
        for i := 0 to Parts.Count - 1 do
          LogD('  [' + IntToStr(i) + '] "' + Trim(Parts[i]) + '"');
        if Parts.Count > 0 then
          Result := Trim(Parts[0]);
      finally
        Parts.Free;
      end;
    finally
      SL.Free;
      P.Free;
    end;
    if Result = '' then Result := '127.0.0.1';
    LogD('ClientID = "' + Result + '"');
  end;

  function GetClipboardText: string;
  var
    P  : TProcess;
    MS : TMemoryStream;
    Buf: array[0..65535] of Byte;
    N  : LongInt;
    T  : QWord;
  begin
    Result := '';
    P  := TProcess.Create(nil);
    MS := TMemoryStream.Create;
    try
      P.Executable := 'xclip';
      P.Parameters.Add('-selection');
      P.Parameters.Add('clipboard');
      P.Parameters.Add('-o');
      P.Options := [poUsePipes, poStderrToOutPut];
      try
        P.Execute;
      except
        on E: Exception do begin Log('xclip GET ERROR: ' + E.Message); Exit; end;
      end;
      T := GetTickCount64;
      repeat
        while P.Output.NumBytesAvailable > 0 do
        begin
          N := P.Output.Read(Buf, SizeOf(Buf));
          if N > 0 then MS.Write(Buf, N);
        end;
        if GetTickCount64 - T > 5000 then
        begin
          P.Terminate(0);
          Log('xclip GET timeout');
          Exit;
        end;
        if P.Running then Sleep(20);
      until not P.Running;

      while P.Output.NumBytesAvailable > 0 do
      begin
        N := P.Output.Read(Buf, SizeOf(Buf));
        if N > 0 then MS.Write(Buf, N);
      end;

      if P.ExitCode <> 0 then
      begin
        LogD('xclip ExitCode=' + IntToStr(P.ExitCode) + ' (clipboard empty?)');
        Exit;
      end;
      if MS.Size = 0 then Exit;

      SetLength(Result, MS.Size);
      MS.Position := 0;
      MS.Read(Result[1], MS.Size);
    finally
      MS.Free;
      P.Free;
    end;
  end;

  // Ver. 5.1 â zapis przez plik tymczasowy zamiast pipe/stdin.
  //
  // Poprzednia wersja: printf %s "$1" | xclip -selection clipboard
  // xclip przy duzych danych fork-uje sie do tla zeby trzymac
  // schowek dla innych aplikacji X11. TProcess z poWaitOnExit
  // czekal na zakonczenie fork-owanego procesu ktory nigdy sie
  // nie konczy -> deadlock, program zawieszal sie na zawsze.
  //
  // Rozwiazanie: zapisujemy tekst do pliku tymczasowego, xclip
  // czyta plik przez -i i natychmiast konczy proces glowny.
  // Unikalna nazwa pliku (PID) = brak konfliktow przy wielu
  // instancjach klienta na tej samej maszynie.
  procedure SetClipboardText(const AText: string);
  var
    P        : TProcess;
    TempFile : string;
    F        : TFileStream;
  begin
    TempFile := IncludeTrailingPathDelimiter(GetTempDir) +
                'clip_' + IntToStr(GetProcessID) + '.tmp';
    LogD('SetClipboard: ' + IntToStr(Length(AText)) + 'B via tempfile=' + TempFile);
    try
      // Zapis binarny bez konwersji znakow
      F := TFileStream.Create(TempFile, fmCreate);
      try
        if Length(AText) > 0 then
          F.WriteBuffer(AText[1], Length(AText));
      finally
        F.Free;
      end;

      // xclip -i czyta plik i konczy proces glowny natychmiast
      P := TProcess.Create(nil);
      try
        P.Executable := 'xclip';
        P.Parameters.Add('-selection');
        P.Parameters.Add('clipboard');
        P.Parameters.Add('-i');
        P.Parameters.Add(TempFile);
        P.Options := [poWaitOnExit];
        P.Execute;
        LogD('SetClipboard: ExitCode=' + IntToStr(P.ExitCode));
      finally
        P.Free;
      end;

      // Dane sa juz w RAM xclip-a â kasujemy plik
      if FileExists(TempFile) then
        DeleteFile(TempFile);

    except
      on E: Exception do
      begin
        Log('SetClipboard ERROR: ' + E.Message);
        if FileExists(TempFile) then DeleteFile(TempFile);
      end;
    end;
  end;

  { ââ HTTP âââââââââââââââââââââââââââââââââââââââââââââââââ }

  function HttpGet(const URL: string; out OutCode: Integer): string;
  var
    C: TFPHTTPClient;
    R: TStringStream;
    T: QWord;
  begin
    Result  := '';
    OutCode := 0;
    C := TFPHTTPClient.Create(nil);
    R := TStringStream.Create('');
    try
      C.ConnectTimeout := 3000;
      C.IOTimeout      := 30000;
      T := GetTickCount64;
      try
        C.Get(URL, R);
        OutCode := C.ResponseStatusCode;
        Result  := R.DataString;
        LogD('GET ' + URL + ' HTTP=' + IntToStr(OutCode) +
             ' size=' + IntToStr(Length(Result)) + 'B' +
             ' time=' + IntToStr(GetTickCount64 - T) + 'ms');
      except
        on E: Exception do
          Log('HTTP GET ERROR: ' + E.Message);
      end;
    finally
      R.Free;
      C.Free;
    end;
  end;

  function HttpPost(const URL, Body: string; out OutCode: Integer): string;
  var
    C   : TFPHTTPClient;
    Req : TStringStream;
    Res : TStringStream;
    T   : QWord;
  begin
    Result  := '';
    OutCode := 0;
    C   := TFPHTTPClient.Create(nil);
    Req := TStringStream.Create(Body, TEncoding.UTF8);
    Res := TStringStream.Create('');
    try
      C.ConnectTimeout := 3000;
      C.IOTimeout      := 30000;
      C.AddHeader('Content-Type', 'application/x-www-form-urlencoded; charset=utf-8');
      Req.Position  := 0;
      C.RequestBody := Req;
      T := GetTickCount64;
      LogD('POST ' + URL + ' body=' + IntToStr(Length(Body)) + 'B');
      try
        C.Post(URL, Res);
        OutCode := C.ResponseStatusCode;
        Result  := Res.DataString;
        LogD('POST HTTP=' + IntToStr(OutCode) +
             ' resp="' + Trim(Result) + '"' +
             ' time=' + IntToStr(GetTickCount64 - T) + 'ms');
      except
        on E: Exception do
          Log('HTTP POST ERROR: ' + E.Message);
      end;
    finally
      Res.Free;
      Req.Free;
      C.Free;
    end;
  end;

  { ââ Parser JSON /api/state Ver.5 âââââââââââââââââââââââââ }

  // Parsuje {"version":N,"author":"IP","text_b64":"BASE64"}
  //
  // text_b64 zawiera Base64 â tylko A-Za-z0-9+/=
  // Nie ma znakÃ³w specjalnych, szukamy zamykajÄcego " wprost.
  // OutTextB64 = surowy Base64, dekodowany w pÄtli gÅÃ³wnej.
  // JeÅli brak pola text_b64 (stary serwer) â OutTextB64 = ''
  // i klient zaloguje WARNING.
  procedure ParseStateJSON(const JSON   : string;
                           out OutVer   : Int64;
                           out OutAuthor: string;
                           out OutB64   : string);
  var
    P1, P2: Integer;
  begin
    OutVer    := 0;
    OutAuthor := '';
    OutB64    := '';

    // version â liczba bez cudzysÅowÃ³w
    P1 := Pos('"version":', JSON);
    if P1 > 0 then
    begin
      Inc(P1, Length('"version":'));
      while (P1 <= Length(JSON)) and (JSON[P1] in [' ',#9,#10,#13]) do Inc(P1);
      P2 := P1;
      while (P2 <= Length(JSON)) and (JSON[P2] in ['0'..'9']) do Inc(P2);
      if P2 > P1 then
        OutVer := StrToInt64Def(Copy(JSON, P1, P2 - P1), 0);
    end;

    // author â IP, bez znakÃ³w specjalnych
    P1 := Pos('"author":"', JSON);
    if P1 > 0 then
    begin
      Inc(P1, Length('"author":"'));
      P2 := Pos('"', JSON, P1);
      if P2 > P1 then
        OutAuthor := Copy(JSON, P1, P2 - P1);
    end;

    // text_b64 â Base64, tylko bezpieczne znaki,
    // szukamy zamykajÄcego " bez obawy o escape'y
    P1 := Pos('"text_b64":"', JSON);
    if P1 > 0 then
    begin
      Inc(P1, Length('"text_b64":"'));
      P2 := Pos('"', JSON, P1);
      if P2 > P1 then
        OutB64 := Copy(JSON, P1, P2 - P1);
    end;

    LogD('ParseJSON: v=' + IntToStr(OutVer) +
         ' author="' + OutAuthor + '"' +
         ' b64_len=' + IntToStr(Length(OutB64)) + 'B');
  end;

{ ââ Zmienne globalne âââââââââââââââââââââââââââââââââââââ }
var
  ClientID      : string;
  LastPulled    : string;   // surowy tekst (nie Base64) ostatnio pobrany/wysÅany
  ServerVersion : Int64;
  TextLocal     : string;   // surowy tekst ze schowka
  LocalB64      : string;   // TextLocal zakodowany Base64 (do PUSH)
  StateResp     : string;
  ServerAuthor  : string;
  ServerTextB64 : string;   // Base64 z /api/state
  ServerText    : string;   // ServerTextB64 zdekodowany (do porÃ³wnaÅ)
  PushBody      : string;
  PushResp      : string;
  HttpCode      : Integer;
  LoopN         : Integer;
  P             : TProcess;
  SL            : TStringList;
  O             : string;

begin
  // -- SprawdÅº xclip ----------------------------------------------------------
  P  := TProcess.Create(nil);
  SL := TStringList.Create;
  try
    P.Executable := 'which';
    P.Parameters.Add('xclip');
    P.Options := [poUsePipes, poWaitOnExit];
    P.Execute;
    SL.LoadFromStream(P.Output);
    O := Trim(SL.Text);
  finally
    SL.Free;
    P.Free;
  end;
  if O = '' then
  begin
    WriteLn('ERROR: xclip not found -- install with: sudo apt install xclip');
    Halt(1);
  end;

  ParseArgs;
  SERVER_URL    := 'http://' + ServerIP + ':' + ServerPort;
  LastPulled    := '';
  ServerVersion := 0;
  LoopN         := 0;

  ClientID := GetLocalIP;

  Log('START Ver.5 | client="' + ClientID + '" | server="' + SERVER_URL + '"');
  if DebugMode then
    Log('  debug ON  â [DBG] lines enabled')
  else
    Log('  debug OFF â uruchom z -d aby wÅÄczyÄ [DBG]');

  // âââ GÅÃWNA PÄTLA ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  while True do
  begin
    try
      // 1. Czytaj lokalny schowek (surowy tekst)
      TextLocal := GetClipboardText;

      // 2. Koduj do Base64 â gotowe do wysÅania w PUSH
      LocalB64 := EncodeBase64(TextLocal);

      // 3. Pobierz stan serwera
      StateResp := HttpGet(SERVER_URL + '/api/state', HttpCode);

      if HttpCode <> 200 then
      begin
        if HttpCode <> 0 then
          Log('[' + IntToStr(LoopN) + '] STATE failed HTTP=' + IntToStr(HttpCode));
      end
      else
      begin
        // 4. Parsuj JSON â otrzymujemy Base64 tekstu serwera
        ParseStateJSON(StateResp, ServerVersion, ServerAuthor, ServerTextB64);

        if ServerTextB64 = '' then
        begin
          // Brak pola text_b64 â serwer w starej wersji
          Log('WARNING: serwer nie zwraca "text_b64" â zaktualizuj do Ver.5!');
        end
        else
        begin
          // 5. Zdekoduj Base64 â surowy tekst serwera
          ServerText := DecodeBase64(ServerTextB64);

          Log('[' + IntToStr(LoopN) + ']' +
              ' lokalny='    + IntToStr(Length(TextLocal)) + 'B' +
              ' serwer='     + IntToStr(Length(ServerText)) + 'B' +
              ' v='          + IntToStr(ServerVersion) +
              ' author="'    + ServerAuthor + '"' +
              ' lastPulled=' + IntToStr(Length(LastPulled)) + 'B');

          LogD('--- decision ---');
          LogD('  TextLocal==ServerText  : ' + BoolToStr(TextLocal = ServerText, True));
          LogD('  TextLocal==LastPulled  : ' + BoolToStr(TextLocal = LastPulled, True));
          LogD('  ServerAuthor==ClientID : ' + BoolToStr(ServerAuthor = ClientID, True) +
               '  ("' + ServerAuthor + '" vs "' + ClientID + '")');

          if TextLocal = ServerText then
          begin
            // Zsynchronizowany
            LogD('  -> SYNCED');
            if LastPulled <> TextLocal then
              LastPulled := TextLocal;
          end
          else
          begin
            if TextLocal <> LastPulled then
            begin
              // PRZYPADEK A: uÅ¼ytkownik skopiowaÅ nowy tekst â PUSH Base64
              LogD('  -> CASE A: local changed â PUSH');
              Log('PUSH ' + IntToStr(Length(TextLocal)) + 'B' +
                  ' (' + IntToStr(Length(LocalB64)) + 'B b64)' +
                  ' expected_v=' + IntToStr(ServerVersion));

              PushBody :=
                'client='            + HTTPEncode(ClientID) +
                '&expected_version=' + IntToStr(ServerVersion) +
                '&data='             + HTTPEncode(LocalB64);

              PushResp := HttpPost(SERVER_URL + '/api/push', PushBody, HttpCode);

              if HttpCode = 200 then
              begin
                LastPulled := TextLocal;
                Log('PUSH OK v=' + Trim(PushResp));
                LogD('  LastPulled=' + IntToStr(Length(LastPulled)) + 'B');
              end
              else if HttpCode = 409 then
              begin
                // Optimistic locking: ktoÅ zdÄÅ¼yÅ przed nami
                // Nie aktualizuj LastPulled â retry w nastÄpnej iteracji
                Log('PUSH CONFLICT 409 â retry next iteration');
                LogD('  LastPulled NOT updated');
              end
              else
                Log('PUSH FAILED HTTP=' + IntToStr(HttpCode) + ': ' + PushResp);
            end
            else if ServerAuthor <> ClientID then
            begin
              // PRZYPADEK B: lokalny nie zmieniÅ siÄ, ktoÅ inny zmieniÅ serwer â PULL
              // ServerText juÅ¼ zdekodowany z Base64 â gotowy do wklejenia
              LogD('  -> CASE B: server changed â PULL');
              Log('PULL ' + IntToStr(Length(ServerText)) + 'B' +
                  ' from="' + ServerAuthor + '" v=' + IntToStr(ServerVersion));
              SetClipboardText(ServerText);
              LastPulled := ServerText;
              LogD('  LastPulled=' + IntToStr(Length(LastPulled)) + 'B');
            end
            else
            begin
              // PRZYPADEK C: lokalny == LastPulled AND author == ja â czekaj
              LogD('  -> CASE C: waiting');
            end;
          end;

          LogD('--- end decision ---');
        end;
      end;

    except
      on E: Exception do Log('LOOP ERROR: ' + E.Message);
    end;

    Inc(LoopN);
    Sleep(1000);
  end;

end.
