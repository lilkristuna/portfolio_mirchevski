	das
	shl	al, 1
	shl	cl, 1
	shl	word ptr es:[bx+si], 1
	or	esi, gs:[edx]
	or	esp, fs:[eax+23h]
	das
	shl	word ptr [bp+di+11h], 1
	shl	eax, 1
	shl	edi, 1
	das
	shl	byte ptr ss:[bx+si], cl
	shl	byte ptr fs:[bx], cl
	or	ax, di
	or	byte ptr gs:[bx+si], al
	or	byte ptr es:[bx+di], dl
	shl	edi, cl
	shl	bx, 23h
	or	word ptr cs:[si], bx
	or	byte ptr ds:[bp+si], bh
	or	dword ptr gs:[di], esi
	das
	shl	al, cl
	shl	word ptr gs:[bx+si], cl
	shl	word ptr ss:[si+23h], 1
	or	ax, bx
	shl	word ptr fs:[bx+23h], cl
	shl	dword ptr fs:[bp+di+1223h], 1
	das
	shl	word ptr ss:[bx+si+1000h], cl
	shl	word ptr es:[bp+1732h], cl
	das
	shl	ax, cl
	shl	dword ptr gs:[bx+si], cl
	das
	shl	dword ptr ds:[bp+si+11h], cl
	shl	esi, cl
	shl	ax, 42h
	shl	eax, 1
	or	al, 21h
	or	ax, 8921h
	or	al, bh
