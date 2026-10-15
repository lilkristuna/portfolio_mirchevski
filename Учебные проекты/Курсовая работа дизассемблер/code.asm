.model small
.386
.stack 100h
.data
	buffer	db	1024 DUP(?)
	_start 	db 	'com.com',0
	_end	db 	'kurs.asm',0
	_das 	db 	9, 'das', 13, 10, '$'
	_shl	db	9, 'shl', 9, '$'
	_or	db	9, 'or', 9, '$'
	_byte	db	'byte ptr ','$'
	_word	db	'word ptr ','$'
	_dword	db	'dword ptr ','$'
	reg	db	'  ','$'
	_symbol	db	' ','$'
	_e	db	'e','$'
	_plus	db	'+','$'
	_1	db	'1','$'
	_zap	db	', ','$'
	dpoint	db	':','$'
	_left	db	'[','$'
	_right	db	']','$'
	_enter	db	13, 10, '$'
	_small	db	'  h','$'	
	_middle	db	'    h','$'
	_big	db	'        h','$'
.code
start:
	mov 	ax,@data
	mov 	ds,ax
	mov	es,ax
	
	mov 	ax, 0600h
   	mov 	bh, 07
   	mov 	cx, 0000
   	mov 	dx, 184Fh
   	int 	10h

	lea	dx, _start
	mov	ax, 3d00h
	int	21h
	
	mov	bx, ax
	mov	ax, 3f00h
	mov	cx, 1024d
	lea	dx, buffer
	int	21h

	mov	ax, 3e00h
	int	21h
	
	lea	dx, _end
	mov	ax, 3c00h
	mov	cx, 0
	int	21h

	lea	si, buffer

beginning:
	xor	bp, bp
	xor	ah, ah
	lodsb

	cmp 	al, 66h
	jnz	seg_reg
	or	bp, 1000h
	lodsb

seg_reg:
	cmp    	al, 26h
  	jz	_yes
    	cmp    	al, 2Eh
 	jz	_yes
    	cmp    	al, 36h
	jz	_yes
	cmp    	al, 3Eh
	jz	_yes
	cmp    	al, 64h
	jz	_yes
    	cmp    	al, 65h
    	jnz    	_no
_yes:
	or	bp, ax		
	lodsb
_no:
	cmp 	al, 67h
	jnz	opcode
	or	bp, 0100h
	lodsb

opcode:
	cmp	al, 2Fh
	jz	write_das

	cmp	al, 0C0h
	jz	_shl_
	cmp	al, 0C1h
	jz	_shl_
	cmp	al, 0D0h
	jz	_shl_
	cmp	al, 0D1h
	jz	_shl_
	cmp	al, 0D2h
	jz	_shl_
	cmp	al, 0D3h
	jz	_shl_

	cmp	al, 08h
	jz	_or_08_09
	cmp	al, 09h
	jz	_or_08_09
	cmp	al, 0Ah
	jz	_or_0A_0B
	cmp	al, 0Bh
	jz	_or_0A_0B
	cmp	al, 0Ch
	jz	_or_0C_0D
	cmp	al, 0Dh
	jz	_or_0C_0D
	cmp	al, 80h
	jz	_or_80
	cmp	al, 81h
	jz	_or_81
	cmp	al, 83h
	jz	_or_83
	jmp	exit

_shl_:
	pusha
	mov	cx, 5
	lea	dx, _shl
	call	viv
	popa
	mov	cl,al
	sal	ecx,16			

	shr	al, 1			
	rcl	ah, 1			
	

	lodsb
	call	mod_reg_rm
	cmp	bh,3
	jnz	table_shl
	and	bp, 1000h
	cmp	bp, 1000h
	jnz	next
	pusha
	call	write_e
	popa
next:
	call	mod11

	jmp	operand_2_shl

table_shl:

	call	_size_
	pusha
	call	seg_ment
	popa
	
	and	bp,0100h		
	cmp	bp,0100h
	jz	t_32_shl
	call	table_16
	jmp	operand_2_shl
t_32_shl:
	call	table_32
	jmp	operand_2_shl

table_16:
	pusha
	call	_16_bit
	popa
	cmp	bh,0				
	jnz	next_mod_16
	cmp	bl,6			
	jz	_d16
	call	end_memory
	ret
next_mod_16:
	pusha
	call	_plus_
	popa
	cmp	bh,1
	jnz	_d16
	call	_disp8
	call	end_memory
	ret
_d16:
	call	_disp16
	call	end_memory
	ret
	
table_32:
	pusha
	call	_32_bit
	popa
	cmp	bl,4		
	jnz	not_sib
	inc	si		
	
not_sib:
	cmp	bh,0		
	jnz	next_mod_32
	cmp	bl,5		
	jz	_d32
	call	end_memory
	ret
next_mod_32:
	pusha
	call	_plus_
	popa
	cmp	bh,1
	jnz	_d32
	call	_disp8
	call	end_memory
	ret
_d32:
	call	_disp32
	call	end_memory
	ret

operand_2_shl:
	call	write_zap
	shr	ecx,16		

	cmp	cl,0C0h
	jz	C0_C1
	cmp	cl,0C1h
	jz	C0_C1
	cmp	cl,0D0h
	jz	D0_D1
	cmp	cl,0D1h
	jz	D0_D1
	cmp	cl,0D2h
	jz	D2_D3
	cmp	cl,0D3h
	jz	D2_D3
C0_C1:
	call	_disp8
	jmp	write_entr	
D0_D1:
	lea	dx, _1    	         
	mov	cx, 1
	call	viv
	jmp	write_entr
D2_D3:
	lea	di, reg
	lea	dx, reg
	mov	cx, 2
	mov	ax, 'lc'
	call	stosw_viv
	jmp	write_entr

_or_0C_0D:
	pusha
	call	write_or	
	popa

	shr	al, 1			
	rcl	ah, 1			

	and	bp, 1000h
	cmp	bp, 1000h
	jnz	next_or
	pusha
	call	write_e
	popa
next_or:
	lea	di, reg
	lea	dx, reg
	mov	cx, 2
	
	pusha
	cmp	ah,0
	jnz	_0D
	mov	ax, 'la'
	jmp	next_0C_0D
_0D:
	mov	ax, 'xa'
next_0C_0D:
	call	stosw_viv
	call	write_zap
	popa
	cmp	ah,0
	jnz	_16_32
	call	_disp8
	jmp	write_entr
_16_32:
	and	bp, 1000h
	cmp	bp, 1000h
	jz	_32_
	call	_disp16
	jmp	write_entr
_32_:
	call	_disp32
	jmp	write_entr

_or_08_09:
	pusha
	call	write_or	
	popa
	
	shr	al, 1
	rcl	ah, 1
	lodsb
	call	mod_reg_rm
	
	cmp	bh,3
	jnz	mem_or
	pusha
	and	bp, 1000h
	cmp	bp, 1000h
	popa
	jnz	next_mem_or
	pusha
	call	write_e
	popa
next_mem_or:
	pusha
	call	mod11
	popa
	jmp	operand_2_08_09
mem_or:
	call	_size_
	pusha
	call	seg_ment
	popa
	pusha
	and	bp,0100h		
	cmp	bp,0100h
	popa
	jz	t_32_or
	pusha
	call	table_16
	popa
	call	prov_16

	jmp	operand_2_08_09
t_32_or:
	pusha
	call	table_32
	popa
	call	prov_32
	jmp	operand_2_08_09
operand_2_08_09:
	pusha
	call	write_zap
	popa
	mov	bl,al
	and	bp, 1000h
	cmp	bp, 1000h
	jnz	next_reg_or
	pusha
	call	write_e
	popa
next_reg_or:
	call	mod11
	jmp	write_entr

_or_0A_0B:
	pusha
	call	write_or	
	popa
	
	shr	al, 1			
	rcl	ah, 1
	lodsb
	call	mod_reg_rm
	
	pusha
	mov	bl,al
	and	bp, 1000h
	cmp	bp, 1000h
	jnz	reg_or
	pusha
	call	write_e
	popa
reg_or:
	call	mod11
	popa

operand_2_0A_0B:
	pusha
	call	write_zap
	popa

	cmp	bh,3
	jnz	mem_or_2
	and	bp, 1000h
	cmp	bp, 1000h
	jnz	next_mem_or_2
	pusha
	call	write_e
	popa
next_mem_or_2:
	pusha
	call	mod11
	popa
	jmp	write_entr
mem_or_2:
	pusha
	call	seg_ment
	popa
	pusha
	and	bp,0100h		
	cmp	bp,0100h
	popa
	jz	t_32_or_2
	pusha
	call	table_16
	popa
	call	prov_16
	jmp	write_entr
t_32_or_2:
	pusha
	call	table_32
	popa
	call	prov_32
	jmp	write_entr

_or_80:
	pusha
	call	write_or	
	popa
	
	shr	al, 1			
	rcl	ah, 1
	lodsb
	call	mod_reg_rm
	
	cmp	bh,3
	jnz	mem_or_3
	pusha
	call	mod11
	popa
	jmp	operand_2_80
mem_or_3:
	call	_size_
	pusha
	call	seg_ment
	popa
	pusha
	and	bp,0100h		
	cmp	bp,0100h
	popa
	jz	t_32_or_3
	pusha
	call	table_16
	popa
	call	prov_16

	jmp	operand_2_80
t_32_or_3:
	pusha
	call	table_32
	popa
	call	prov_32
	jmp	operand_2_80
operand_2_80:
	pusha
	call	write_zap
	popa
	call	_disp8
	jmp	write_entr

_or_81:
	pusha
	call	write_or	
	popa
	
	shr	al, 1			
	rcl	ah, 1
	lodsb
	call	mod_reg_rm
	
	cmp	bh,3
	jnz	mem_or_4
	pusha
	and	bp, 1000h
	cmp	bp, 1000h
	popa
	jnz	next_mem_or_4
	pusha
	call	write_e
	popa
next_mem_or_4:
	pusha
	call	mod11
	popa
	jmp	operand_2_81
mem_or_4:
	call	_size_
	pusha
	call	seg_ment
	popa
	pusha
	and	bp,0100h		
	cmp	bp,0100h
	popa
	jz	t_32_or_4
	pusha
	call	table_16
	popa
	call	prov_16

	jmp	operand_2_81
t_32_or_4:
	pusha
	call	table_32
	popa
	call	prov_32
	jmp	operand_2_81
operand_2_81:
	pusha
	call	write_zap
	popa

	and	bp, 1000h
	cmp	bp, 1000h
	jz	_d32_yes
	call	_disp16
	jmp	write_entr
_d32_yes:
	call	_disp32
	jmp	write_entr

_or_83:
	pusha
	call	write_or	
	popa
	
	shr	al, 1			
	rcl	ah, 1
	lodsb
	call	mod_reg_rm
	
	cmp	bh,3
	jnz	mem_or_5
	pusha
	and	bp, 1000h
	cmp	bp, 1000h
	popa
	jnz	next_mem_or_5
	pusha
	call	write_e
	popa
next_mem_or_5:
	pusha
	call	mod11
	popa
	jmp	operand_2_83
mem_or_5:
	call	_size_
	pusha
	call	seg_ment
	popa
	pusha
	and	bp,0100h		
	cmp	bp,0100h
	popa
	jz	t_32_or_5
	pusha
	call	table_16
	popa
	call	prov_16

	jmp	operand_2_83
t_32_or_5:
	pusha
	call	table_32
	popa
	call	prov_32
	jmp	operand_2_83
operand_2_83:
	pusha
	call	write_zap
	popa
	call	_disp8
	jmp	write_entr


write_das:
	mov	cx, 6
	lea	dx, _das
	call	viv
	jmp	beginning
write_or:
	mov	cx, 4
	lea	dx, _or
	call	viv
	ret
mod_reg_rm:				
	mov	bl,al
	and	bl,7		
	mov	bh,al
	shr	bh,6		
	shr	al,3
	and	al,7		
	ret
write_e:
	lea	dx, _e    	        
	mov	cx, 1
	call	viv
	ret
write_zap:
	lea	dx, _zap    	      
	mov	cx, 2
	call	viv
	ret
_plus_:
	lea	dx, _plus		
	mov 	cx,1
	call	viv
	ret
end_memory:			
	lea	dx, _right			
	mov	cx, 1
	call	viv
	ret
write_entr:
	lea	dx, _enter    	        
	mov	cx, 2
	call	viv
	jmp	beginning
stosw_viv:
	stosw
	call	viv
	ret
_size_:				
	cmp	ah, 1
	jz	next_word
	lea	dx, _byte
	mov	cx, 9
	jmp	_size
next_word:
	pusha
	and	bp, 1000h
	cmp	bp, 1000h
	popa
	jz	next_dword
	lea	dx, _word
	mov	cx, 9
	jmp	_size
next_dword:
	lea	dx, _dword
	mov	cx, 10
_size:
	pusha
	call	viv
	popa
	ret
prov_16:
	cmp	bh,0
	jnz	_mod01
	cmp	bl,6
	jz	_mod10
	ret
_mod01:
	cmp	bh,1
	jnz	_mod10
	inc	si
	ret
_mod10:
	add	si,2
	ret
prov_32:
	cmp	bh,0
	jnz	_mod01_
	cmp	bl,5
	jz	_mod10_
	ret
_mod01_:
	cmp	bh,1
	jnz	_mod10_
	inc	si
	ret
_mod10_:
	add	si,4
	ret

_disp8:
	lodsb	
	lea	di,[_small]
	mov	cx, 2		
	mov	bh, al
	call	number
	lea	dx, _small
	mov	cx,3
	call	viv
	ret
_disp16:
	lodsw	
	lea	di,[_middle]
	mov	cx, 4		
	mov	bx,ax
	call	number
	lea	dx, _middle
	mov	cx,5
	call	viv
	ret
_disp32:
	lodsw
	lea	di,[_big+4]
	mov	cx, 4		
	mov	bx,ax
	call	number
	lodsw
	lea	di,[_big]
	mov	cx, 4		
	mov	bx,ax
	call	number
	lea	dx, _big	
	mov	cx,9
	call	viv
	ret
number:
	xor	al,al
	mov	dx,cx
	mov	cx,4
circle:
	shl 	bx,1
     	rcl 	al,1
	loop	circle
	cmp	al,0Ah
	jb	cifra
	add	al,7h
cifra:
	add	al, 30h
	stosb
	mov	cx,dx
	loop	number
	ret

mod11:
	lea	di, reg
	lea	dx, reg
	mov	cx, 2

	cmp	bl, 0
	jnz	p0
	cmp	ah, 0
	jz	a0
	mov	ax, 'xa'
	jmp	end_mod11
a0:
	mov	ax, 'la'	
	jmp	end_mod11
p0:
	cmp	bl, 1
	jnz	p1
	cmp	ah, 0
	jz	a1
	mov	ax, 'xc'
	jmp	end_mod11
a1:
	mov	ax, 'lc'	
	jmp	end_mod11
p1:
	cmp	bl, 2
	jnz	p2
	cmp	ah, 0
	jz	a2
	mov	ax, 'xd'
	jmp	end_mod11
a2:
	mov	ax, 'ld'	
	jmp	end_mod11
p2:
	cmp	bl, 3
	jnz	p3
	cmp	ah, 0
	jz	a3
	mov	ax, 'xb'
	jmp	end_mod11
a3:
	mov	ax, 'lb'	
	jmp	end_mod11
p3:
	cmp	bl, 4
	jnz	p4
	cmp	ah, 0
	jz	a4
	mov	ax, 'ps'
	jmp	end_mod11
a4:
	mov	ax, 'ha'	
	jmp	end_mod11
p4:
	cmp	bl, 5
	jnz	p5
	cmp	ah, 0
	jz	a5
	mov	ax, 'pb'
	jmp	end_mod11
a5:
	mov	ax, 'hc'	
	jmp	end_mod11
p5:
	cmp	bl, 6
	jnz	p6
	cmp	ah, 0
	jz	a6
	mov	ax, 'is'
	jmp	end_mod11
a6:
	mov	ax, 'hd'	
	jmp	end_mod11
p6:
	cmp	ah, 0
	jz	a7
	mov	ax, 'id'
	jmp	end_mod11
a7:
	mov	ax, 'hb'	
	jmp	end_mod11
end_mod11:
	call	stosw_viv
	ret

seg_ment:
	and	bp,00FFh		
	cmp	bp,0
	jz	m_7	

	lea	di, reg
	lea	dx, reg
	mov	cx, 2

	cmp	bp,0026h
	jnz	m_1
	mov	ax,'se'
	jmp	m_6
m_1:
	cmp	bp,002Eh
	jnz	m_2
	mov    	ax,'sc'
    	jmp    	m_6
m_2:
	cmp	bp,0036h
	jnz	m_3
	mov    	ax,'ss'                       
    	jmp    	m_6
m_3:
	cmp	bp,003Eh
	jnz	m_4
	mov	ax,'sd'
	jmp	m_6
m_4:
	cmp	bp,0064h
	jnz	m_5
	mov	ax,'sf'
	jmp	m_6
m_5:
	cmp	bp,0065h
	jnz	m_7
	mov	ax,'sg'
m_6:
	call	stosw_viv	
	lea	dx, dpoint
	mov	cx, 1
	call	viv
m_7:
	lea	dx, _left
	mov	cx, 1
	call	viv
	ret

_16_bit:	
	lea	di, reg
	lea	dx, reg
	mov	cx, 2

	cmp	bl,0
	jnz	_001

	mov	ax, 'xb'
	pusha
	call	stosw_viv
	call	_plus_
	popa
	mov	ax, 'is'
	call	stosw_viv
	ret
_001:
	cmp	bl,1
	jnz	_010

	mov	ax, 'xb'
	pusha
	call	stosw_viv
	call	_plus_
	popa
	mov	ax, 'id'
	call	stosw_viv
	ret
_010:
	cmp	bl,2
	jnz	_011
	
	mov	ax, 'pb'
	pusha
	call	stosw_viv
	call	_plus_
	popa
	mov	ax, 'is'
	call	stosw_viv
	ret
_011:
	cmp	bl,3
	jnz	_100
	
	mov	ax, 'pb'
	pusha
	call	stosw_viv
	call	_plus_
	popa
	mov	ax, 'id'
	call	stosw_viv
	ret
_100:
	lea	di, reg
	lea	dx, reg
	mov	cx, 2

	cmp	bl,4
	jnz	_101
	mov	ax, 'is'
	jmp	end_16_bit
_101:
	cmp	bl,5
	jnz	_110
	mov	ax, 'id'
	jmp	end_16_bit
_110:
	cmp	bl,6
	jnz	_111
	cmp	bh, 0
	jnz	_110_mod
	ret				
_110_mod:
	mov	ax, 'pb'
	jmp	end_16_bit
_111:
	mov	ax, 'xb'
end_16_bit:
	call	stosw_viv
	ret

_32_bit:	
	lea	di, reg
	lea	dx, reg

	cmp	bl,0
	jnz	_001_
	mov	ax, 'xa'
	jmp	end_32_bit
_001_:
	cmp	bl,1
	jnz	_010_
	mov	ax, 'xc'
	jmp	end_32_bit
_010_:
	cmp	bl,2
	jnz	_011_
	mov	ax, 'xd'
	jmp	end_32_bit
_011_:
	cmp	bl,3
	jnz	_100_
	mov	ax, 'xb'
	jmp	end_32_bit
_100_:					
	cmp	bl,4
	jnz	_101_			
	ret				
_101_:
	cmp	bl,5
	jnz	_110_
	cmp	bh,0
	jnz	_101_1_			
	ret
_101_1_:
	mov	ax, 'pb'
	jmp	end_32_bit
_110_:
	cmp	bl,6
	jnz	_111_
	mov	ax, 'is'
	jmp	end_32_bit
_111_:
	mov	ax, 'id'
end_32_bit:
	pusha
	lea	dx,_e             	
	mov	cx,1
	call	viv
	popa
	mov	cx, 2
	call	stosw_viv
	ret

viv:
	mov	ah, 40h
	mov	bx, 5
	int	21h
	mov 	ah, 09h
	int 	21h
	ret
exit:
	mov 	ax, 4c01h
	int 	21h
end	start