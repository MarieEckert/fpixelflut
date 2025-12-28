{$mode fpc}
program fpf;

{$H+}{$R+}
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

procedure shuffle_block_array(var a: TBlockArray);
var
	i,j:integer;
	t:TBlock;
begin
	randomize;
	i := length(a);
	while i >1 do
	begin
		dec(i);
		j :=randomrange(0,i);
		t:=a[i];a[i]:=a[j];a[j]:=t;
	end;
end;

function make_block_array(pixels: TTexture): TBlockArray;
var
	nwblocks, nhblocks										: Extended;
	{ rounded w/h blocks  remainder dimensions }
	rnwblocks, rnhblocks, remainder_width, remainder_height	: UInt64;
	total_wblocks, total_hblocks, total_blocks				: UInt64;

	x, y, ox, oy, wx, wy, xbsize, ybsize, pix: UInt64;
begin
	nwblocks := pixels.width / BSIZE;
	nhblocks := pixels.height / BSIZE;

	rnwblocks := floor(nwblocks);
	rnhblocks := floor(nhblocks);

	remainder_width := round((nwblocks - rnwblocks) * bsize);
	remainder_height := round((nhblocks - rnhblocks) * bsize);

	total_wblocks := round(min(1.0, remainder_width)) + rnwblocks;
	total_hblocks := round(min(1.0, remainder_height)) + rnhblocks;
	total_blocks := total_wblocks * total_hblocks;

	writeln('nwblocks: ', nwblocks);
	writeln('nhblocks: ', nhblocks);
	writeln('rnwblocks: ', rnwblocks);
	writeln('rnhblocks: ', rnhblocks);
	writeln('remainder w: ', remainder_width);
	writeln('remainder h: ', remainder_height);
	writeln('block dimension: ', total_wblocks, 'x', total_hblocks, ' (', total_blocks, ' total)');

	SetLength(make_block_array, total_blocks);

	for y := 0 to total_hblocks - 1 do
	begin
		ybsize := bsize;
		if y = rnhblocks then ybsize := remainder_height;

		wy := total_wblocks - 1;
		for x := 0 to total_wblocks - 1 do
		begin
			xbsize := bsize;
			if x = rnwblocks then xbsize := remainder_width;

			SetLength(make_block_array[y * total_wblocks + x].data, xbsize * ybsize * 4);
			make_block_array[y * total_wblocks + x].xorg := wy * xbsize;
			make_block_array[y * total_wblocks + x].yorg := y * ybsize;
			make_block_array[y * total_wblocks + x].w := xbsize;
			make_block_array[y * total_wblocks + x].h := ybsize;

			for oy := 0 to ybsize - 1 do
			begin
				wx := xbsize - 1;
				for ox := 0 to xbsize - 1 do
				begin
					pix := (((x * xbsize) + ox) * pixels.width + ((y * ybsize) + oy)) * 4;
					make_block_array[y * total_wblocks + x].data[(oy * xbsize + wx) * 4 + 0] := pixels.data[pix];
					make_block_array[y * total_wblocks + x].data[(oy * xbsize + wx) * 4 + 1] := pixels.data[pix + 1];
					make_block_array[y * total_wblocks + x].data[(oy * xbsize + wx) * 4 + 2] := pixels.data[pix + 2];
					make_block_array[y * total_wblocks + x].data[(oy * xbsize + wx) * 4 + 3] := pixels.data[pix + 3];
					dec(wx);
				end;
			end;

			dec(wy);
		end;
	end;
end;

procedure fluten(pixels: TTexture);
var
	sock_addr			: sockaddr;
	sock				: LongInt;
	command				: String;
	x, y, pix, fix		: UInt64;
	xoff				: UInt64;
	yoff				: Real;
	wix, saved_wix		: UInt64;
		//		: TStringDynArray;
	frames				: array of TStringDynArray;
	raw_blocks			: TBlockArray;
	block				: TBlock;
begin
	sock := fpSocket(AF_INET, SOCK_STREAM, 0);
	if sock = -1 then
	begin
		writeln('fpSocket');
		halt(1);
	end;

	sock_addr.sin_family := AF_INET;
	sock_addr.sin_port := htons(1234);
	sock_addr.sin_addr.s_addr := StrToNetAddr('151.219.13.203').s_addr;

	x := 0;

	raw_blocks := make_block_array(pixels);
	shuffle_block_array(raw_blocks);
	SetLength(frames, 192);

	writeln('block count ', Length(raw_blocks));

	wix := 0;
	for block in raw_blocks do
	begin
		writeln('block xorg ', block.xorg, ' yorg ', block.yorg);
		if Length(block.data) = 0 then
		begin
			halt(1);
			writeln('nil len, xorg ', block.xorg, ' yorg ', block.yorg);
			continue;
		end;

		xoff := 0;
		yoff := 1080 / 2;
		saved_wix := wix;
		for fix := 0 to High(frames) do
		begin
			wix := saved_wix;
			SetLength(frames[fix], pixels.width * pixels.height + Length(raw_blocks));
			frames[fix][wix] := Format('OFFSET %d %d'#10, [xoff+block.yorg,round(yoff)+block.xorg]);
			Inc(wix);

			for y := 0 to block.h - 1 do
			begin
				for x := 0 to block.w - 1 do
				begin
					pix := (y * block.w + x) * 4;
					if block.data[pix+3] = 0 then
						SetLength(frames[fix][wix], 0)
					else
					begin
						frames[fix][wix] := frames[fix][wix] + Format('PX %d %d %.2x%.2x%.2x'#10, [
							y,
							x,
							block.data[pix+2],
							block.data[pix + 1],
							block.data[pix]
						]);
					end;

					inc(wix);
				end;
			end;
			yoff := 1080 / 2 + (40 * sin(xoff / 100));
			xoff += 10;
			if xoff > 1920 then
				xoff := 0;
			end;
	end;

	writeln('wix ', wix, ' command capcity ', Length(frames[fix]));
	if fpConnect(sock, @sock_addr, sizeof(sock_addr)) < 0 then
	begin
		writeln('fpConnect');
		halt(2);
	end;

	writeln('connected');

	while True do
	begin
		for fix := 0 to High(frames) do
		begin
			for command in frames[fix] do
			begin
				if Length(command) = 0 then
					continue;
				if fpSend(sock, @command[1], Length(command), 0) < 0 then
				begin
					writeln('fpSend: ', SocketError);
					halt(123);
				end;
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

	fluten(pixels);
end.
