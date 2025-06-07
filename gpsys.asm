; getsys/putsys for AES103
; sector size is 155, this includes a 1 byte sync char
; a 3 byte sector header and a checksum byte
; for writing, we need an additional 16 zero bytes
; for the boot tracks, we use a 150 byte payload

;offsets in cpm.sys
;CCP: 0000h-0800h
;BDOS:0800h-1600h	CCP+BDOS 38 sectors = 1644h bytes, 44h zeros at start to have BIOS at sector boundary
;BIOS:1600h-1C00h	BIOS	11 sectors max



;Track 0 has reserved sector for romloader
;track 0 sectors 0, 1 bootloader
;track 0 sector 8 directory for ROM
;track 0, sectors 9-15 (7), track 1 sectors 0-15 (16), track2 sectors 0-14 (15):: CCP, BDOS, 44h=68 zero bytes at start, 38 sectors
;track 3 sectors 0-10 BIOS



	org	0200h
	
msize	equ	20
plsiz	equ	150	;sector payload size
ssiz	equ	155	;total sector data size
wrpre	equ	16	;write preamble (zeroes)
numseq	equ	16
numtrk	equ	4	;system occupies 4 tracks

bias	equ	(msize -20) * 1024
ccp	equ	3400h+bias
bdos	equ	ccp+0800h
bios	equ	ccp+1600h

;IO port definitions
pstat	equ	05h
psynwr	equ	10h
psynrd	equ 	11h
pstep 	equ	14h
psec	equ	15h
pcmd	equ	16h
pactive	equ	17h
pwradd	equ	20h
pwrcnt	equ	21h
prdadd	equ	22h
prdcnt	equ	23h
prmst	equ	28h

;status bits
rdy1	equ	01h
rdy2	equ	02h
wrp1	equ	04h
wrp2	equ	08h
trk0	equ	10h
activ	equ	80h

;command bits
head1	equ	01h
head2	equ	02h
mtr1	equ	04h
mtr2	equ	08h
acten	equ	10h
dirup	equ	20h
write	equ	40h
sel2	equ	80h

;syncbyte
synrd	equ	0DBh
synwr	equ	00h

gstart:
	lxi	sp,ccp-0080h
	lxi	h,ccp-0080h		; start of destination
	call	strtrdy
	mvi	b,0			; start at track 0
	call	seekzero
rd$trk:
	mvi	c,0			; start at sector 0
rd$sec:
	call	read$sec
	lxi	d,plsiz			; add sector payload size to data pointer
	dad	d
	inr	c			; next sector
	mov	a,c
	cpi	numseq			; last sector reached?
	jc	rd$sec

	call	nexttrk
	inr	b
	mov	a,b
	cpi	numtrk			; last track reached?
	jc	rd$trk

	hlt


	org	($+0100h) and 0ff00h	;putsys at next page boundary

put$sys:
	lxi	sp,ccp-0080h
	lxi	h,ccp-0080h		; start of source data
	call	strtrdy
	mvi	b,0			; start at track 0
	call	seekzero
wr$trk:
	mvi	c,0			; start at sector 0
wr$sec:
	call	write$sec
	lxi	d,plsiz			; add sector payload size to data pointer
	dad	d
	inr	c			; next sector
	mov	a,c
	cpi	numseq			; last sector reached?
	jc	wr$sec

	; next track
	call	nexttrk
	inr	b
	mov	a,b
	cpi	numtrk			; last track reached?
	jc	wr$trk

	hlt

	org	($+0100h) and 0ff00h	;next page boundary

read$sec:
	; read sector
	; track in <b>
	; sector in <c>
	; dmaaddr in <hl>

	push 	b
	push	h

	mov	a,c
	out	psec		;sector number
	mvi	a, synrd
	out	psynrd		; sync byte
	mvi	a, 042h ;DMA_MODESET_EN_CH1|DMA_MODESET_TCSTOP
	out	prmst		;dma controller mode
	mvi	a, ssiz		
	out	prdcnt		;number of bytes
	mvi	a, 040h		
	out	prdcnt		; DMA to RAM
	lxi	h, secbuf	;read to temporary buffer
	mov	a,l
	out	prdadd
	mov	a,h
	out	prdadd
	lda	cmdreg
	ori	acten
	ani 	not write
	sta	cmdreg
	out	pcmd
	out	pactive
	
rdwt:	in	pstat
	ral
	jc	rdwt

	
	
	;sync and header
	inx	h	;now at track#
	mvi	d,2
	call 	cschk
	jz      headok
	hlt		;Oops
headok:	
	;hl now at checksum byte
	inx	h	;now at data
	
	push	h 		;start address for checksum
	mvi	d, plsiz
	call    cschk
	pop	h		;restore dst address
	jz	dataok
	hlt			;oops
dataok:	
	pop	d	;destination addres
	push 	d

	mvi	b,plsiz
	call	cpymem

	pop	h
	pop	b

	ret

	org	($+0100h) and 0ff00h	;next page boundary

write$sec:
	; write sector
	; track in <b>
	; sector in <c>
	; dmaaddr in <hl>

	push 	b
	push	h

	mov	a,c
	out	psec		;sector number
	mvi	a, synwr
	out	psynwr		; sync byte
	mvi	a, 041h ;DMA_MODESET_EN_CH0|DMA_MODESET_TCSTOP
	out	prmst		;dma controller mode
	mvi	a, ssiz	+ wrpre	
	out	pwrcnt		;number of bytes
	mvi	a, 080h		
	out	pwrcnt		; DMA from RAM
	lxi	h, secbuf	;write from temporary buffer
	mov	a,l
	out	pwradd
	mov	a,h
	out	pwradd

	; build temporary buffer
	mvi	d, wrpre		;16 zero bytes at start	
	call	zeromem		;leaves hl pointing to right after zeroes
	mvi	a,synrd
	mov	m, a		;sync byte
	inx	h
	mov	m, b		;track
	inx	h
	mov	m, c		;sector
	dcx	h		;point to track again
	mvi	d,2
	call 	cschk
	mov	m, a		;checksum
	inx	h

	
	pop	d	;source addres
	push 	d
	xchg
	push	d	;start address fro checksum calculation
	mvi	b,plsiz
	call	cpymem

	pop	h 		;start address for checksum
	mvi	d, plsiz
	call    cschk
	mov	m, a		;checksum
	

	
	lda	cmdreg
	ori	acten or write 
	sta	cmdreg
	out	pcmd
	out	pactive
	
wrtwt:	in	pstat
	ral
	jc	wrtwt

	pop	h
	pop	b

	ret

;start disk1 and wait for ready
strtrdy:
	mvi	a, mtr1 and head1
	sta	cmdreg
	out	pcmd
wtrdy:	
	in	pstat
	ani	rdy1
	jnz	wtrdy
	ret

;delay
delay:

	mvi     e, 0CFh
inner:                        
	xthl
	xthl
	dcr     e
	jnz     inner
	dcr     a
	jnz     delay
	ret


seekzero:
	lda     cmdreg
	ani     not dirup
	out     pcmd
	sta     cmdreg
waitzero:                     
	in      pstat
	ani     trk0
	rnz         
	out     pstep
	mvi     a, 007h
	call    delay
	jmp     waitzero


cpymem:
	mov     a, m            ; load from mem hl
	stax    d               ; store at de
	inx     h
	inx     d               ; increment pointers
	dcr     b               ; decrement count
	jnz     cpymem        ; load from mem hl
	ret


; next track
nexttrk:
	lda	cmdreg
	ori	dirup
	out	pcmd
	sta 	cmdreg
	out	pstep
	mvi	a,7
	call	delay
	ret

;Zero memory at HL, for d bytes
;clobbers de
zeromem:
	mvi     e, 0
zerloop:
	mov     m, e
	inx     h
	dcr     d
	jnz     zerloop
	ret

;Calculate and check checksum
;data in hl, size in d
;returns with calculated checksum in a
;hl pointer checksum byte
;zero flag set if checksum ok
cschk:
	sub     a
csloop: 
	add     m               ; add to checksum
	inx     h               ; increment ptr
	dcr     d               ; decrement count
	jnz     csloop         ; add value at ptr HL to a
	cmp     m               ; compare sum in a with byte at ptr
	ret


;uninitialized data
cmdreg:	ds	1
secbuf:	ds	ssiz + wrpre
	