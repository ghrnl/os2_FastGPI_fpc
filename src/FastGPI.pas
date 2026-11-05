program FastGPI;

{$APPTYPE GUI}

uses os2def, pmwin, pmgpi, pmbitmap, pmdev, doscalls;

const
  NUM_MASSES_X = 320;
  NUM_MASSES_Y = 240; // product is larger than MAXINT
  
  npal = 33; // entries in palette
  nrgb = 33; // entries in RGBmap

type
  HDC  = cardinal; // ! longword
  TID  = cardinal; // ! longword
  HMTX = longint;  // ! longint, not HTMX=longword
  Array3D = array of array of array of real;

var
  h_ab: HAB;
  h_wndFrame, h_wndClient: HWND;
  h_dc, h_dcMemory: HDC;
  h_ps, h_psMemory: HPS;
  h_mtxLock: HMTX;
  tidModel: TID;
  ModelSuspended: boolean = FALSE;
  h_bm: HBITMAP;
  bmih: BITMAPINFOHEADER2;
  bmp2data: BITMAPINFOHEADER2;
  pbmi: PBITMAPINFO2;
  // BYTE RGBmap[32]; so size 32, indices 0 to 31
  // Pascal: add one element (!)
  RGBmap: array [0..nrgb-1] of byte; // GRE change into 33 elements given code (e.g. DisplayPlane)
  
  Bitmap: array [0..NUM_MASSES_X*NUM_MASSES_Y-1] of byte;
  aptl: array [0..3-1] of POINTL = ((x:0;y:0),(x:NUM_MASSES_X;y:NUM_MASSES_Y),(x:0;y:0));

  node: Array3D;
  
var
  palette: array [0..npal-1] of longint;

{ void Model(ULONG dummy) }
{ Pascal: cardinal; cdecl;}
function Model(dummy: pointer): cardinal;

{ float *** Storage() }
procedure Storage;
{
	float ***node;
}
	// Allocate node storage from the heap.
	// if (!(node = New3DOffloat(0, 2, 0, NUM_MASSES_X-1, 0, NUM_MASSES_Y-1)))
	//
	//	printf("Can't allocate required memory from heap.\n");
	//	exit(1);
	//
	// return(node);

begin
  setlength(Node,3,NUM_MASSES_X,NUM_MASSES_Y);
end; {Storage}

{ void DisplayPlane(float **current) }

procedure DisplayPlane(current: integer);

const
  min_disp_val =      0;
  max_disp_val = nrgb-1;
  
var
  x, y: integer;
  disp_val: integer;

begin

  for y := 0 to NUM_MASSES_Y-1 do begin
    for x := 0 TO NUM_MASSES_X-1 do begin
      // disp_val = ((int) current[x][y] + 16);
      disp_val := round(node[current,x,y]) + 16;
      if (disp_val > max_disp_val) then
        disp_val := max_disp_val;
      if (disp_val < min_disp_val) then
        disp_val := min_disp_val;
      Bitmap[y*NUM_MASSES_X+x] := RGBmap[disp_val]; // so 33 elements in RGBmap !!
    end; {for x}
  end; {for y}
  
  DosRequestMutexSem(h_mtxLock, SEM_INDEFINITE_WAIT);

  {  This is the key to the speed. Instead of doing a GPI call to set the
     color and a GPI call to set the pixel for EACH pixel, we get by
     with only two GPI calls. }
  GpiSetBitmapBits(h_psMemory, 0, NUM_MASSES_Y-2, Bitmap[0], pbmi^);
  GpiBitBlt(h_ps, h_psMemory, 3, aptl[0], ROP_SRCCOPY, BBO_AND);

  DosReleaseMutexSem(h_mtxLock);
  
end; {DisplayPlane}

{ void PrepareGraphics(BYTE *RGBmap) }

procedure PrepareGraphics(var RGBmap: array of byte);

var
  coords: POINTL;
  x, y: integer;

begin

  // Give thread access to Gpi. 
  WinInitialize(0);

  // Determine mapping from logical color value to bitmap color table
  // index.  Anybody know a more direct way??? 
  DosRequestMutexSem(h_mtxLock, SEM_INDEFINITE_WAIT);
  // for (x := 0, y := 0; x < 33; x++) do
  // In Pascal this would be: for x:=0 to 32 do
  y:=0;
  for x:=0 to nrgb-1 do
  begin
      GpiSetColor(h_psMemory, x);
      coords.x := x;
      coords.y := y;
      GpiSetPel(h_psMemory, coords);
  end;
  
  bmp2data.cbFix := 16;
  GpiQueryBitmapInfoHeader(h_bm, bmp2data);
  {
  DosAllocMem((PPVOID)&pbmi, sizeof(BITMAPINFO2) +
		(sizeof(RGB2) * (1 << bmp2data.cPlanes) *
                (1 << bmp2data.cBitCount)),
                PAG_COMMIT or PAG_READ or PAG_WRITE);
                }
  DosAllocMem(pointer(pbmi), sizeof(BITMAPINFO2) +
		(sizeof(RGB2) * (1 shl {<<} bmp2data.cPlanes) *
                (1 shl {<<} bmp2data.cBitCount)),
                PAG_COMMIT or PAG_READ or PAG_WRITE);              
  with pbmi^ do begin
    cbFix           := bmp2data.cbFix;
    cx              := bmp2data.cx;
    cy              := bmp2data.cy;
    cPlanes         := bmp2data.cPlanes;
    cBitCount       := bmp2data.cBitCount;
    { 16 byte limit }
    ulCompression   := bmp2data.ulCompression;
    cbImage         := bmp2data.cbImage;
    cxResolution    := bmp2data.cxResolution;
    cyResolution    := bmp2data.cyResolution;
    cclrUsed        := bmp2data.cclrUsed;
    cclrImportant   := bmp2data.cclrImportant;
    usUnits         := bmp2data.usUnits;
    usReserved      := bmp2data.usReserved;
    usRecording     := bmp2data.usRecording;
    usRendering     := bmp2data.usRendering;
    cSize1          := bmp2data.cSize1;
    cSize2          := bmp2data.cSize2;
    ulColorEncoding := bmp2data.ulColorEncoding;
    ulIdentifier    := bmp2data.ulIdentifier;
  end;
  GpiQueryBitmapBits(h_psMemory, 0, NUM_MASSES_Y-2, Bitmap[0], pbmi^);
  DosReleaseMutexSem(h_mtxLock);
  // for (x := 0; x < 33; x++)
  // In Pascal this would be: for x:=0 to 32 do
  for x:=0 to nrgb-1 do
  begin
    RGBmap[x] := Bitmap[x];
  end
end; {PrepareGraphics}

var
  current, excitatory, inhibitory, tmp: integer;
  count: ULONG; 	// Epoch counter // unsigned long
  x,y: integer;		// Temporary variables and flags
  harm: real;
  
begin

  // Work out mapping from bitmap color table to our logical palette.
  PrepareGraphics(RGBmap);

  // Allocate node storage from the heap.
  Storage;

  // Start at time 0.
  count := 0;
  current    := 0; // node[0];
  excitatory := 1; // node[1];
  inhibitory := 2; // node[2];

  // Main simulation loop.
  while true do
  begin
    while ModelSuspended do
      DosSleep(100);

    // for (x = 1; x < NUM_MASSES_X-1; x++)
    for x := 1 to NUM_MASSES_X-2 do begin
      // for (y = 1; y < NUM_MASSES_Y-1; y++)
      for y := 1 to NUM_MASSES_Y-2 do begin
        // Difference equation for the 5-point wave equation.
        node[current,x,y] := 0.5*(node[excitatory,x+1,y] +
	                node[excitatory,x-1,y] +
	                node[excitatory,x,y+1] +
	                node[excitatory,x,y-1]) -
	                node[inhibitory,x,y];
      end {for y}
    end; {for x}

    // Apply harmonic inputs.
    harm := 30*sin(0.6*count);
    // current[130][120] += harm;
    node[current,130,120]:=node[current,130,120]+harm;
    // current[190][120] += harm;
    node[current,190,120]:=node[current,190,120]+harm;
    
    // Display results.
    DisplayPlane(current);
    
    // Advance epoch.
    // i.e. a cyclic shift
    count      := count+1;
    tmp        := inhibitory;
    inhibitory := excitatory;
    excitatory := current;
    current    := tmp;
    
  end; {while}
  
  Model:=0;
  
end; {Model}

{ mousutil.pas}

{ 20221211 several type integers > word }
{ 20221230 add/move some comments plus some opt }

function SHORT1FROMMP(MP: pointer): word;
{ map C name SHORT1... on fpc name integer1... }
{ pmwin.pas:    function Integer1FromMP (MP: pointer): word; cdecl; }
begin
  SHORT1FROMMP:=integer1frommp(mp)
end;

function SHORT2FROMMP(MP: pointer): word;
{ map C name SHORT2... on fpc name integer2... }
{ pmwin.pas:    function Integer2FromMP (MP: pointer): word; cdecl; }
begin
  SHORT2FROMMP:=integer2frommp(mp)
end;

{ MRESULT EXPENTRY
window_func(HWND handle, ULONG mess, MPARAM parm1, MPARAM parm2) }

function window_func(handle, mess: ULONG; parm1,parm2: pointer): pointer; cdecl; export;

var
//   palette: array [0..33-1] of longint = // cannot be cardinal

  i: integer;
  j: longint;
  sizl: SIZEL;
  
  { extra }
  xxx1: DevOpenStruc;
  xxx2: TBitmapInfo2;
  xxx3: byte;

begin
  case mess of
  
  WM_CREATE: begin
      // Create presentation space for screen.
      h_dc := WinOpenWindowDC(handle);
      sizl.cx := 0;
      sizl.cy := 0;
      h_ps := GpiCreatePS(h_ab, h_dc, sizl,
		PU_PELS or GPIT_MICRO or GPIA_ASSOC or GPIF_DEFAULT);

      // Create presentation space for memory image of screen.
      fillchar(xxx1,sizeof(xxx1),0);
      h_dcMemory := DevOpenDC(h_ab, OD_MEMORY, '*', 0, xxx1 {0}, 0);
      sizl.cx := 0;
      sizl.cy := 0;
      h_psMemory := GpiCreatePS(h_ab, h_dcMemory, sizl,
		PU_PELS or GPIT_MICRO or GPIA_ASSOC or GPIF_DEFAULT);

      // Create bitmap for memory image of screen.
      // memset(bmih, 0, sizeof(bmih));
      fillchar(bmih,sizeof(bmih),0); // swap args 2 & 3 wrt C
      bmih.cbFix := sizeof(bmih);
      bmih.cx := NUM_MASSES_X;
      bmih.cy := NUM_MASSES_Y;
      bmih.cPlanes := 1;
      bmih.cBitCount := 8;
      //fillchar(xxx2,sizeof(xxx2),0);
      //fillchar(xxx3,sizeof(xxx3),0);
      // hbm = GpiCreateBitmap(hpsMemory, &bmih, 0L, NULL, NULL);
      // h_bm := GpiCreateBitmap(h_psMemory, bmih, 0, nil {xxx3} {0}, {xxx2} nil);
      h_bm := GpiCreateBitmap(h_psMemory, bmih, 0, xxx3 {0}, xxx2);
      GpiSetBitmap(h_psMemory, h_bm);

      // Set up gray-scale palette for screen image.
      // for (i := 0; i < 32; i++)
      for i := 0 to npal-2 do begin // we have 33 values in palette
        j := i shl 3; // <<
        palette[i] := (j shl 16) or (j shl 8) or j; // << // RGB identical
      end; {for i}
      palette[npal-1] := $00ffffff; // highest byte zero
      GpiCreateLogColorTable(h_psMemory, LCOL_PURECOLOR,
		LCOLF_CONSECRGB, 0, npal, {(PLONG)} palette[0]); // npal or nrgb ? should be npal
      GpiSetBackMix(h_psMemory, BM_OVERPAINT);

      // Create a semaphore to control access to the memory image
      // presentation space. Only one thread can perform Gpi operations
      // on it at a time.
      DosCreateMutexSem('\SEM32\Lock', h_mtxLock, 0, 0);

      // Create a thread to run the system model.
      DosCreateThread(tidModel, @Model, nil, 0, 4096);
      
      // Take the input focus.
      WinFocusChange(HWND_DESKTOP, handle, 0);
      end;

  WM_ERASEBACKGROUND,
  WM_PAINT: begin
      // Copy the memory image of the screen out to the real screen.
      DosRequestMutexSem(h_mtxLock, SEM_INDEFINITE_WAIT);
      WinBeginPaint(handle, h_ps, nil);
      GpiBitBlt(h_ps, h_psMemory, 3, aptl[0], ROP_SRCCOPY, BBO_AND);
      WinEndPaint(h_ps);
      DosReleaseMutexSem(h_mtxLock);
      end;

  WM_CHAR: begin
      if (SHORT1FROMMP(parm1) and KC_KEYUP)>0 then
        { nothing to do }
      else if (SHORT2FROMMP(parm2) = VK_PAUSE) then
        ModelSuspended := not ModelSuspended;
      end;
  
  otherwise 
      window_func:= WinDefWindowProc(handle, mess, parm1, parm2);
  end; {case}
  window_func := nil; // FALSE;
end; {window_func}


var
  h_mq: HMQ;
  q_msg: QMSG;
  flFlags: ULONG;
  szClass: pChar = 'MyClass';

begin

  flFlags := FCF_TITLEBAR or
             FCF_MINBUTTON or
             FCF_TASKLIST or
             FCF_SYSMENU;

  h_ab := WinInitialize(0);
  if (h_ab = 0) then
  begin
    writeln('Error doing WinInitialize()');
    halt(1);
  end;
  
  h_mq := WinCreateMsgQueue(h_ab, 0);
  if ( h_mq = 0 ) then
  begin
    writeln('Error doing WinCreateMsgQueue()');
    halt(2);
  end;
  
  if not(WinRegisterClass(h_ab,  szClass, @window_func,
                        CS_SIZEREDRAW, 0)) then
  begin
    writeln('Error doing WinRegisterClass()');
    halt(3);
  end;
  
  h_wndFrame := WinCreateStdWindow(HWND_DESKTOP, WS_VISIBLE, @flFlags,
                                  szClass, '5-Point Wave Equation',
                                  WS_VISIBLE, 0, 0, @h_wndClient);
  if (h_wndFrame = 0) then
  begin
    writeln('Error doing WinCreateStdWindow()');
    halt(4);
  end;
  
  WinSetWindowPos(h_wndFrame,
                  0,
                  60,
                  WinQuerySysValue(HWND_DESKTOP, SV_CYSCREEN) - (NUM_MASSES_Y+60),
                  NUM_MASSES_X,
		  NUM_MASSES_Y + WinQuerySysValue(HWND_DESKTOP,
			SV_CYTITLEBAR) - 2, SWP_SIZE or SWP_MOVE);
  
  while WinGetMsg(h_ab, q_msg, 0, 0, 0) do
    WinDispatchMsg(h_ab, q_msg);
  
  WinDestroyWindow(h_wndFrame);
  WinDestroyMsgQueue(h_mq);
  WinTerminate(h_ab);
  
  halt(0);

end.


