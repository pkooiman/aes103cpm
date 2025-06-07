;	Skeletal CBIOS for first level of CP/M 2.0 alteration
;
; sector size is 155, this includes a 1 byte sync char
; a 3 byte sector header and a checksum byte
; for writing, we need an additional 16 zero bytes
; for the boot tracks, we could use a 150 byte payload
; but it would still need 4 tracks so instead we use 128 byte sectors

;offsets in cpm.sys
;CCP: 0000h-0800h
;BDOS:0800h-1600h	CCP+BDOS 44 sectors
;BIOS:1600h-1C00h	BIOS	12 sectors max but code (minus uninit data)  currently only 0x451 = 9 sectors



;Track 0 has reserved sector for romloader
;track 0 sectors 0, 3 (aes103 logical track 0 sector 1) bootloader
;track 0 sector 8 directory for ROM
;track 0, sectors 9-15 (7), track 1 sectors 0-15 (16), track2 sectors 0-15 (16), track 3 sectors 0-4:: CCP, BDOS, 44 sectors
;track 3 sectors 5-15 BIOS (11 max)
;track 4 directory
;available blocks: (30 * 128 * 16) // 1024 = 60 (61440 used)


msize	equ	32	;cp/m version memory size in kilobytes
;
;	"bias" is address offset from 3400H for memory systems
;	than 16K (referred to as "b" throughout the text).
;
bias	equ	(msize-20)*1024
ccp	equ	3400H+bias	;base of ccp
bdos	equ	ccp+806h	;base of bdos
bios	equ	ccp+1600h	;base of bios
cdisk	equ	0004H	;current disk number 0=A,...,15=P
iobyte	equ	0003h	;intel i/o byte
;
	org	bios	;origin of this program
nsects	equ	38	;warm start sector count
offset	equ	4	;number of disk tracks used by cp/m

buff	equ	0080h	;default buffer address

plsiz	equ	150	;sector payload size
ssiz	equ	155	;total sector data size
cpmssiz	equ	128	;CP/M sector size
wrpre	equ	16	;write preamble (zeroes)

;
;IO port definitions
prirqpr	equ	00h	
prxoff	equ	01h
pryoff	equ	02h
prxmax	equ	03h
premap	equ	03h
pflags  equ	04h
pstat	equ	05h
pkeyb	equ	06h
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
wrtdsk	equ	40h
sel2	equ	80h

;syncbyte
synrd	equ	0DBh
synwr	equ	00h

;io flags
flvidena	equ	00h
fltimena 	equ	01h
flbell		equ	02h
fltick		equ	03h
flfg		equ	04h
flpaging	equ	05h
fluline		equ	06h
flhalft		equ	07h
flon		equ	08h
floff		equ	00h

;keyboard buffer
kbbufsiz	equ	8

;irq controller status register value to set
irqstval	equ	5

;size for interrupt stack
inststksiz	equ	8


;	jump vector for individual subroutines
	jmp	boot		;cold start
wboote:	jmp	wboot		;warm start
	jmp	const		;console status
	jmp	conin		;console character in
	jmp	conout		;console character out
	jmp	list		;list character out
	jmp	punch		;punch character out
	jmp	reader		;reader character out
	jmp	home		;move head to home position
	jmp	seldsk		;select disk
	jmp	settrk		;set track number
	jmp	setsec		;set sector number
	jmp	setdma		;set dma address
	jmp	read		;read disk
	jmp	write		;write disk
	jmp	listst		;return list status
	jmp	sectran		;sector translate
;
	maclib	diskdef	;load the disk definition library
	disks	2	;two disks
	diskdef	0,0,15,3,1024,60,64,64,offset
	diskdef	1,0
;	endef occurs at end of assembly


cr	equ	0dh	;carriage return
lf	equ	0ah	;line feed
bs	equ	08h	;backspace
del	equ	7fh	;rubout/del
vers	equ	22	;version 2.2
;
signon:	;signon message: xxk cp/m vers y.y
	db	cr,lf,lf
	db	'AES103 '
	db	'32'	;32k bios
	db	'k CP/M vers '
	db	vers/10+'0','.',vers mod 10+'0'
	db	cr,lf,0

;	individual subroutines to perform each function
boot:	;simplest case is to just perform parameter initialization
	
	in	premap			;map out boot ROM
	lxi	sp,buff+80h		;make sure we have a stack
	
	xra	a			;zero in the accum
	sta	iobyte			;clear the iobyte
	sta	cdisk			;select disk zero
	;clear the display
	sta	scrx
	sta	scry
	out 	prxoff
	out	pryoff
	mvi	a, 7
	out	prxmax			;80 char display
	lxi     h, 8000h
	mvi     a, 9Fh           	;end address for fill 0x9F00
	mvi	b, 20h
scrloop:	
	mov     m, b
	inx     h
	cmp     h
	jp      scrloop

	lxi	h,signon
	call	prmsg	;print message

	mvi     a, flvidena or flon	;display on
	out     pflags

	call	kbbufres		;Reset keyboard buffer

	mvi	a, irqstval
	out	prirqpr			;only allow keyboard interrupt
	jmp	gocpm			;initialize and go to cp/m
;
wboot:	;simplest case is to read the disk until all sectors loaded
	lxi	sp,80h		;use space below buffer for stack
	mvi	c,0		;select disk 0
	call	seldsk
	call	home		;go to track 00
;
	mvi	b,nsects	;b counts # of sectors to load
	mvi	c,0		;c has the current track number
	mvi	d,9		;d has the next sector to read
;	note that we begin by reading track 0, sector 9 

	lxi	h,ccp		;base of cp/m (initial load point)
load1:	;load one more sector
	push	b	;save sector count, current track
	push	d	;save next sector to read
	push	h	;save dma address
	mov	c,d	;get sector address to register c
	call	setsec	;set sector address from register c
	pop	b	;recall dma address to b,c
	push	b	;replace on stack for later recall
	call	setdma	;set dma address from b,c
;
;	drive set to 0, track set, sector set, dma address set
	call	read
	cpi	00h	;any errors?
	jnz	wboot	;retry the entire boot if an error occurs
;
;	no error, move to next sector
	pop	h	;recall dma address
	lxi	d,128	;dma=dma+128
	dad	d	;new dma address is in h,l
	pop	d	;recall sector address
	pop	b	;recall number of sectors remaining, and current trk
	dcr	b	;sectors=sectors-1
	jz	gocpm	;transfer to cp/m if all have been loaded
;
;	more sectors remain to load, check for track change
	inr	d
	mov	a,d	;sector=26?, if so, change tracks
	cpi	16
	jc	load1	;carry generated if sector<27
;
;	end of current track, go to next track
	mvi	d,0	;begin with first sector of next track
	inr	c	;track=track+1
;
;	save register state, and change tracks
	push	b
	push	d
	push	h
	call	settrk	;track address set from register c
	pop	h
	pop	d
	pop	b
	jmp	load1	;for another sector
;
;	end of load operation, set parameters and go to cp/m
gocpm:
	mvi	a,0c3h	;c3 is a jmp instruction
	sta	0	;for jmp to wboot
	lxi	h,wboote	;wboot entry point
	shld	1	;set address field for jmp at 0
;
	sta	5	;for jmp to bdos
	lxi	h,bdos	;bdos entry point
	shld	6	;address field of jump at 5 to bdos
;
	lxi	b,80h	;default dma address is 80h
	call	setdma

	sta	20h	;jump for keybaord interrupt handler
	lxi	h,kbirq
	shld	21h	;kb handler address
;
	ei		;enable the interrupt system
	lda	cdisk	;get current disk number
	mov	c,a	;send to the ccp
	jmp	ccp	;go to cp/m for further processing
;
;
;	simple i/o handlers (must be filled in by user)
;	in each case, the entry point is provided, with space reserved
;	to insert your own code
;
const:	;console status, return 0ffh if character ready, 00h if not
	call	kbempty
	mvi	a,00h
	jz	nochar
	mvi	a,0FFh
nochar:	
	ret
;
conin:	;console character into register a
	call	kbget
	mov	c,a
	ral
	mov	a,c
	jc	notcontrol
	;Control + key
	ani	1Fh	;make ascii value for control+key
notcontrol:
	cpi	85h	;delete key	
	jnz	notdel
	mvi	a,7fh

notdel:	
	ani	7fh	;strip parity bit
	ret
;
conout: ;console character output from register c
	lda	scrx	;x position
	mov	l,a
	inr	a	;next x position	
	sta	scrx
	lda	scry
	ori	80h
	mov	h, a	;hl contains vidmem address for current position
	;get rid of cursor at current position
	mvi	m,32
	mov	a,c	;get char to output to accumulator
	cpi	cr	;carriage return?
	jz      carret
	cpi	lf	;line feed?
	jz	linf
	cpi	bs	;backspace?
	jz	backsp
	mov	m,a	;output character
	jmp	chkxy
carret:
	xra	a	;clear accumulator
	sta	scrx
	jmp	chkxy
backsp
	lda	scrx	;already incremented x position
	dcr	a	;undo x increment
	jz	prevlin	;at start of line
	dcr	a	;1 character back
	sta	scrx
	jmp	chkxy	

prevlin:
	sta	scrx
	lda	scry
	ora	a
	jz	chkxy	;already at line 0, nothing left to do
	dcr	a
	sta	scry
	jmp	chkxy
linf:
	lda	scry
	inr	a
	sta     scry

	

chkxy:
	;Did we run off the end of the line?
	lda	scrx
	cpi	80
	jc	chky
	xra	a	;clear accumulator
	sta	scrx	;back to x=0
	lda	scry
	inr	a
	sta	scry	;and next line
chky:	
	lda	scry
	cpi	26
	jc	drwcur

	;need to scroll up
	mvi	c,25	;25 lines to copy
	mvi	d, 80h	;destination initially line 0
	mvi	h, 81h	;source initially line 1
doscroll:	
	mvi	e,0	;reset low pointer to 0
	mvi	l,0
	mvi	b, 80		;80 characters
	call	cpymem
	inr	d		;next dst line
	inr	h		;next src line
	dcr	c
	jnz	doscroll

	;clear bottom line
	lxi	h, 9900h	;vidmem address last line
	mvi	c, 20h
	mvi	b, 80		;80 characters
	mvi	a,25
	sta	scry

clrlin:	
	mov     m, c
	inx     h
	dcr	b
	jnz     clrlin

drwcur: mvi	a, flhalft or flon
	out	pflags
	lda	scrx	;x position
	mov	l,a
	lda	scry
	ori	80h
	mov	h, a
	mvi	m,32
	mvi	a, flhalft or floff
	out	pflags
	ret

;
list:	;list character from register c
	mov	a,c	;character to register a
	ret		;null subroutine
;
listst:	;return list status (0 if not ready, 1 if ready)
	xra	a	;0 is always ok to return
	ret
;
punch:	;punch character from register c
	mov	a,c	;character to register a
	ret		;null subroutine
;
;
reader: ;read character into register a from reader device
	mvi	a,1ah	;enter end of file for now (replace later)
	ani	7fh	;remember to strip parity bit
	ret
;
;
;	i/o drivers for the disk follow
;	for now, we will simply store the parameters away for use
;	in the read and write subroutines
;
home:	;move to the track 00 position of current drive

	call	seekzero
	ret		
;
seldsk:	;select disk given by register C
	lxi	h,0000h	;error return code
	mov	a,c
	sta	diskno
	cpi	2	;must be between 0 and 1
	rnc		;no carry if 2,3,...
;	disk number is in the proper range
	cpi	0	;disk 1?
	mvi	a, mtr1 or head1 ;disk 1
	mvi	c, rdy1
	jz 	dosel
	mvi	a, mtr2 or head2 or sel2 ; disk2
	mvi	c, rdy2
dosel:	
	sta	cmdreg
	out	pcmd
	mvi	b,7
wtrdy:	
	dcr	b
	rz 	;return error if timed out
	mvi	a,7
	call	delay
	in	pstat
	ana	c
	jz	wtrdy


;	compute proper disk parameter header address
	lda	diskno
	mov	l,a	;L=disk number 0,1,2,3
	mvi	h,0	;high order zero
	dad	h	;*2
	dad	h	;*4
	dad	h	;*8
	dad	h	;*16 (size of each header)
	lxi	d,dpbase
	dad	d	;HL=.dpbase(diskno*16)
	ret
;
settrk:	;set track given by register c
	mov	a,c
	sta	track
	call	seek
	ret
;
setsec:	;set sector given by register c
	mov	a,c
	sta	sector
	ret
;
sectran:
	;translate the sector given by BC using the
	;translate table given by DE
	xchg		;HL=.trans
	dad	b	;HL=.trans(sector)
	mov	l,m	;L = trans(sector)
	mvi	h,0	;HL= trans(sector)
	ret		;with value in HL
;
setdma:	;set dma address given by registers b and c
	mov	l,c	;low order address
	mov	h,b	;high order address
	shld	dmaad	;save the address
	ret
;
read:	;perform read operation 
	lda	sector
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
	ani 	not wrtdsk
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
	mvi	a,1	;Oops
	ret
headok:	
	;hl now at checksum byte
	inx	h	;now at data
	
	push	h 		;start address for checksum
	mvi	d, plsiz
	call    cschk
	pop	h		;restore dst address
	jz	dataok
	mvi	a,1	;Oops
	ret
dataok:	
	xchg
	lhld	dmaad
	xchg
	;We leave 18 zero bytes at start of payload
	;for consistency, this gives a correct extra header in sectors 0 and 8
	;without treating them specially
	lxi	b, 18		
	dad	b

	mvi	b,cpmssiz
	call	cpymem
	mvi	a,0
	ret

;
write:	;perform a write operation

	lda     cmdreg	;figure out which drive is current
	ani	sel2	
	mvi	b,wrp1
	jz	chkwrpr	;jump if drive 1 current
	mvi	b,wrp2  ;drive 2 current
	
chkwrpr:	
	in	pstat
	ana	b
	jz	wrok
	mvi	a,1	;Current disk is write protected
	ret

wrok:
	lda	sector
	mov	c,a
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
	mvi	d, wrpre	;Zero 16 pre bytes
	call	zeromem		
	push 	h		;hl points to first bytea fter sync, save it
	mvi	d, ssiz		;Zero buffer
	call	zeromem		
	pop	h 		;restore hl ptr first data byte
	mvi	a,synrd
	mov	m, a		;sync byte
	inx	h
	ora	a
	
	;convert to 103 "logical" track 
	lda	track
	ral			;times 2
	push	h
	lxi	h,secttab	;lookup table for sector #
	mvi	d, 0
	mov	e,c		;sector
	dad	d
	add	m		;add 1 to logcal trackno if sector belongs to track +1 	
	pop	h
	mov	m, a		;track
	
	
	inx	h
	mov	m, c		;sector
	dcx	h		;point to track again
	mvi	d,2
	call 	cschk
	mov	m, a		;checksum
	inx	h
	
	;We leave 18 zero bytes at start of payload
	;for consistency, this gives a correct extra header in sectors 0 and 8
	;without treating them specially
	push	h		;start address for payload checksum calculation
	lxi	b,18
	dad	b
	xchg
	lhld	dmaad		;source addres, de contains destination now
	
	mvi	b,cpmssiz
	call	cpymem

	pop	h 		;start address for checksum
	mvi	d, plsiz
	call    cschk
	mov	m, a		;checksum
	

	
	lda	cmdreg
	ori	acten or wrtdsk
	sta	cmdreg
	out	pcmd
	out	pactive
	
wrtwt:	in	pstat
	ral
	jc	wrtwt

	mvi	a,0
	ret		


	;delay routine
delay:

	mvi     e, 0CFh
inner:                        
	xchg
	xchg
	dcr     e
	jnz     inner
	dcr     a
	jnz     delay
	ret

	; seek current disk to track 0
seekzero:
	lda     cmdreg
	ani     not dirup
	out     pcmd
	sta     cmdreg
waitzero:                     
	in      pstat
	ani     trk0
	jnz	atzero         
	out     pstep
	mvi     a, 007h
	call    delay
	jmp     waitzero
atzero:
	lda     cmdreg	;figure out which drive is current
	ani	sel2	;and set current track to 0
	lxi	h, curtrd1	;drive 1 current, point hl to cur track disk 1
	jz	zer0	;is drive 1 current?
	inx	h	;hl now points to cur track disk 2
zer0:
	mvi	m,0
	ret

	; seek current disk to track in "track"
seek:
	lda     cmdreg	;figure out which drive is current
	ani	sel2	
	lxi	h, curtrd1	;drive 1 current, point hl to cur track disk 1
	jz	doseek
	lxi	h, curtrd2		;drive 2 current, point hl to cur track disk 2

doseek:	
	mvi     c, 50		;don't try more than 50 steps
	
nexttrack:
	mov	b,m		;track we are currently at
	lda	track		; trackno wanted
	cpi     35             ; track below 35?
	rnc     
	sub     b
	rz                      ; return if at wanted track
	lda     cmdreg
	jc      stepdown        ; current track too high
	ori     dirup 		; set bit 5 -> track up
	inr     m               ; increment current track
	jmp     dostep

stepdown:                             
	ani     not dirup 	;clear bit 5 -> track down
	dcr     m               ; decrement current track
dostep:     
	out     pcmd
	sta     cmdreg
	out     pstep
	mvi     a,7
	call    delay
	dcr     c
	jnz     nexttrack
	;something wrong, seek to track zero and try again
	call    seekzero
	jmp     seek

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

	;Copy memory from hl to de for b bytes
cpymem:
	mov     a, m            ; load from mem hl
	stax    d               ; store at de
	inx     h
	inx     d               ; increment pointers
	dcr     b               ; decrement count
	jnz     cpymem        ; load from mem hl
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


;print message at h,l to 0
prmsg:	
	mov	a,m
	ora	a	;zero?
	rz
;	more to print
	push	h
	mov	c,a
	call	conout
	pop	h
	inx	h
	jmp	prmsg

	;Keyboard interrupt handler
kbirq:
	push	psw
	shld	hltmp		;Save HL
	lxi	h, 0
	dad	sp		;sp to hl
	lxi	sp,intstk+inststksiz	;Switch to our own stack
	push	h		;old sp
	push	b
	push	d

	in	pkeyb		;Read character, clear interrupt
	mov	b,a
	call	kbstor
	mvi	a, irqstval
	out	prirqpr		;ack to interrupt controller
	
	pop	d
	pop	b
	pop 	h		;old sp
	sphl			;restore sp
	lhld	hltmp
	pop	psw
	ei
	ret		

	;Reset keyboard circular buffer
kbbufres:	
	di
	lxi	h, kbbuf
	shld	kbrdptr
	inx	h
	shld	kbwrptr
	ei
	ret

	;Store character in b in keyboard buffer
kbstor:
	lhld    kbwrptr		;Current write pointer value
	lda	kbrdptr		;Current read pointer value low byte
	cmp     l		;Same? then buffer is full
	rz                      ;return if full
	mov     m, b		;store character
	call    kbbufinc
	shld    kbwrptr
	ret

	;Increment circular buffer pointer in hl
kbbufinc:
	inx	h
	lda	kbstor+1	;Get low byte of first address after keyboard buffer
			      	;Dirty trick to get it from the operand in kbstor first ins
	cmp	l		;If equal, need to wrap buffer around
	rnz			;otherwise return
	lxi	h, kbbuf
	ret

	;return with zero flag set if keyboard buffer empty
kbempty:
	
	lhld	kbrdptr
	call	kbbufinc	;If readptr 1 below writeptr
				;there are no chars waiting
	di
	lda	kbwrptr		;Get low byte of write pointer
	ei
	cmp	l
	ret

	;Get character from keyboard buffer if present
kbget:
	call	kbempty
	jz	kbget
	lhld	kbrdptr
	call	kbbufinc
	mov	a,m
	shld	kbrdptr	
	ret

;map physical sector number to 103 logical track +1 or not
secttab:	db 0,1,0,0,1,0,0,1,1,0,1,1,0,1,1,0


;
;	the remainder of the CBIOS is reserved uninitialized
;	data area, and does not need to be a part of the
;	system memory image (the space must be available,
;	however, between "begdat" and "enddat").
;


track:	ds	2	;two bytes for expansion
sector:	ds	2	;two bytes for expansion
dmaad:	ds	2	;direct memory address
diskno:	ds	1	;disk number 0-15

;Next two must be kept together
curtrd1: ds	1	;current track disk 1
curtrd2: ds	1	;current track disk 2

cmdreg:	ds	1
secbuf:	ds	ssiz + wrpre
scrx:	ds	1
scry:	ds	1

;Keyboard buffer must not cross page boundary!!
kbbuf	ds	kbbufsiz	;Keyboard circular buffer
;kbwrptr must be immediately after kbbuf!
kbwrptr	ds	2		;Buffer write pointer
kbrdptr	ds	2		;Buffer read pointer

hltmp	ds	2
intstk	ds	inststksiz		;Interrupt stack

;
;	define ram areas for bdos operation
	endef
	end