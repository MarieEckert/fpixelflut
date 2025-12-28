{$mode fpc}
program fpf;

{$H+}{$R-}
{$R resources.rc}

uses classes, elfreader, math, resource, sockets, strutils, sysutils, types, uBMP;

type
	TBytes = array of Byte;

	TBlock = record
		data: TBytes;
		xorg: UInt64;
		yorg: UInt64;
		w	: UInt64;
		h	: UInt64;
	end;

	TBlockArray = array of TBlock;

const
	BSIZE = 10;

procedure ShuffleBlockArray(var a: TBlockArray);
var
	i,j	: Integer;
	t	: TBlock;
begin
	Randomize;
	i := Length(a);
	while i >1 do
	begin
		Dec(i);
		j	 := RandomRange(0,i);
		t	 := a[i];
		a[i] := a[j];
		a[j] := t;
	end;
end;

function MakeBlockArray(pixels: TTexture): TBlockArray;
var
	nwblocks, nhblocks										: Extended;
	{ rounded w/h blocks  remainder dimensions }
	rnwblocks, rnhblocks, remainderWidth, remainderHeight	: UInt64;
	totalWBlocks, totalHBlocks, totalBlocks					: UInt64;
	x, y, ox, oy, wx, wy, xbsize, ybsize, pix, n			: UInt64;
begin
	nwblocks := pixels.width / BSIZE;
	nhblocks := pixels.height / BSIZE;

	rnwblocks := floor(nwblocks);
	rnhblocks := floor(nhblocks);

	remainderWidth := round((nwblocks - rnwblocks) * bsize);
	remainderHeight := round((nhblocks - rnhblocks) * bsize);

	totalWBlocks := round(min(1.0, remainderWidth)) + rnwblocks;
	totalHBlocks := round(min(1.0, remainderHeight)) + rnhblocks;
	totalBlocks := totalWBlocks * totalHBlocks;

	WriteLn('[DEBUG] BSIZE: ', BSIZE);
	WriteLn('[DEBUG] nwblocks: ', nwblocks);
	WriteLn('[DEBUG] nhblocks: ', nhblocks);
	WriteLn('[DEBUG] rnwblocks: ', rnwblocks);
	WriteLn('[DEBUG] rnhblocks: ', rnhblocks);
	WriteLn('[DEBUG] remainder w: ', remainderWidth);
	WriteLn('[DEBUG] remainder h: ', remainderHeight);
	WriteLn('[DEBUG] block dimension: ', totalWBlocks, 'x', totalHBlocks, ' (', totalBlocks, ' total)');

	SetLength(MakeBlockArray, totalBlocks);
	n := 0;

	for y := 0 to totalHBlocks - 1 do
	begin
		ybsize := bsize;
		if y = rnhblocks then ybsize := remainderHeight;

		wy := totalWBlocks - 1;
		for x := 0 to totalWBlocks - 1 do
		begin
			xbsize := bsize;
			if x = rnwblocks then xbsize := remainderWidth;

			SetLength(MakeBlockArray[y * totalWBlocks + x].data, xbsize * ybsize * 4);
			MakeBlockArray[y * totalWBlocks + x].xorg := wy * xbsize;
			MakeBlockArray[y * totalWBlocks + x].yorg := y * ybsize;
			MakeBlockArray[y * totalWBlocks + x].w := xbsize;
			MakeBlockArray[y * totalWBlocks + x].h := ybsize;

			Inc(n);
			Write('[INFO] Preparing Block ', n, '/', Length(MakeBlockArray), #13);

			for oy := 0 to ybsize - 1 do
			begin
				wx := xbsize - 1;
				for ox := 0 to xbsize - 1 do
				begin
					{ subtract from pixels.width or height to flip the imag  correctly }
					pix := ( ( pixels.width - ((x * xbsize) + ox) ) + ( pixels.height - ((y * ybsize) + oy) ) * pixels.width ) * 4;
					MakeBlockArray[y * totalWBlocks + x].data[(oy * xbsize + wx) * 4 + 0] := pixels.data[pix];
					MakeBlockArray[y * totalWBlocks + x].data[(oy * xbsize + wx) * 4 + 1] := pixels.data[pix + 1];
					MakeBlockArray[y * totalWBlocks + x].data[(oy * xbsize + wx) * 4 + 2] := pixels.data[pix + 2];
					MakeBlockArray[y * totalWBlocks + x].data[(oy * xbsize + wx) * 4 + 3] := pixels.data[pix + 3];
					Dec(wx);
				end;
			end;

			Dec(wy);
		end;
	end;

	WriteLn;
end;

procedure Fluten(pixels: TTexture);
var
	sockAddress			: sockaddr;
	sock				: LongInt;
	command				: String;
	x, y, pix			: UInt64;
	wix					: UInt64;
	commandList			: TStringDynArray;
	rawBlocks			: TBlockArray;
	block				: TBlock;
begin
	if ParamCount < 2 then
	begin
		WriteLn('USAGE: fpf <IP> <PORT>');
		Halt(1);
	end;

	sock := fpSocket(AF_INET, SOCK_STREAM, 0);
	if sock = -1 then
	begin
		WriteLn('[FATAL] fpSocket: ', SocketError);
		halt(2);
	end;

	sockAddress.sin_family := AF_INET;
	sockAddress.sin_port := htons(StrToInt(ParamStr(2)));
	sockAddress.sin_addr.s_addr := StrToNetAddr(ParamStr(1)).s_addr;

	x := 0;

	rawBlocks := MakeBlockArray(pixels);
	ShuffleBlockArray(rawBlocks);

	SetLength(commandList, pixels.width * pixels.height + Length(rawBlocks));

	wix := 0;
	for block in rawBlocks do
	begin
		if Length(block.data) = 0 then
		begin
			WriteLn('[FATAL] nil len, xorg ', block.xorg, ' yorg ', block.yorg);
			halt(1);
		end;

		commandList[wix] := Format('OFFSET %d %d'#10, [block.xorg,block.yorg]);
		Inc(wix);

		for y := 0 to block.h - 1 do
		begin
			for x := 0 to block.w - 1 do
			begin
				pix := (y * block.w + x) * 4;
				if block.data[pix+3] = 0 then
					SetLength(commandList[wix], 0)
				else
				begin
					commandList[wix] := commandList[wix] + Format('PX %d %d %.2x%.2x%.2x'#10, [
						x,
						y,
						block.data[pix+2],
						block.data[pix + 1],
						block.data[pix]
					]);
				end;

				Inc(wix);
			end;
		end;
	end;

	if fpConnect(sock, @sockAddress, sizeof(sockAddress)) < 0 then
	begin
		WriteLn('[FATAL] fpConnect: ', SocketError);
		halt(2);
	end;

	WriteLn('connected');

	while True do
	begin
		for command in commandList do
		begin
			if Length(command) = 0 then
				continue;
			if fpSend(sock, @command[1], Length(command), 0) < 0 then
			begin
				WriteLn('fpSend: ', SocketError);
				halt(123);
			end;
		end;
end;
end;

var
	resources		: TResources;
	_resource		: TAbstractResource;
	i				: Integer;
	resource_name	: String;
	pixels			: TTexture;
begin
	resources := TResources.Create;
	resources.LoadFromFile(ParamStr(0));

	for i:= 0 to resources.count - 1 do
	begin
		_resource		:= resources.items[i];
		resource_name	:= _resource.name.name;

		if StartsStr('IMAGE', resource_name) then
			pixels := uBMP.LoadTexture(_resource);
	end;

	Fluten(pixels);
end.
