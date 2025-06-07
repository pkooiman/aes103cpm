; sector size is 155, this includes a 1 byte sync char
; a 3 byte sector header and a checksum byte
; we use standard 128 byte sector size


; sector size is 155, this includes a 1 byte sync char
; a 3 byte sector header and a checksum byte
; for writing, we need an additional 16 zero bytes
; for the boot tracks, we could use a 150 byte payload
; but it would still need 4 tracks so instead we use 128 byte sectors

;offsets in cpm.sys
;CCP: 0000h-0800h
;BDOS:0800h-1600h	CCP+BDOS 44 sectors
;BIOS:1600h-1C00h	BIOS	12 sectors max but code currently only 0x40f = 9 sectors



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
cpmb	equ	3400H+bias	;base of ccp
;cpmb    equ     6400
bdos    equ     806h+cpmb
bdose   equ     1A80h+cpmb
boot    equ     1600h+cpmb
rboot   equ     boot+3

ssiz	equ	155	;total sector data size
presiz  equ     4       ;number of sector header bytes before payload
sectrk	equ	16      ;sectors per track
cpmssiz	equ	128	;CP/M sector size

        org     200h
bdos1   equ     bdose-cpmb
ntrks   equ     4               ;tracks to read
bdoss   equ     bdos1/cpmssiz       ;num sectors to read
stack   equ     200h

;IO port definitions
premap	equ	03h
pstat	equ	05h
psynrd	equ 	11h
pstep 	equ	14h
psec	equ	15h
pcmd	equ	16h
pactive	equ	17h
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

start:
	in	premap			;map out boot ROM
        lxi     sp,stack
        lxi     d, cpmb        ;destination is start of ccp

	mvi	a, mtr1 or head1       ;start disk 1       
	sta	cmdreg
	out	pcmd

        ;wait for disk to become ready
wtrdy:	
	in	pstat
	ani	rdy1
	jz	wtrdy

        ;seek to track 0
	lda     cmdreg
	ani     not dirup
	out     pcmd
	sta     cmdreg
wttrzero:                     
	in      pstat
	ani     trk0
	jnz     atzero         
	out     pstep
	mvi     a, 007h
	call    delay
	jmp     wttrzero

atzero:
        mvi     a, 0
        sta     trck
        mvi     a, bdoss        ;total number of sectors to read
        sta     secrem

        mvi     c, 9            ;start at sector 9           
next:           
        lxi     h, secbuf
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
	mov	a,l             ;current ptr low
	out	prdadd
	mov	a,h             ;current pointer high
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

        ;copy to destination
        
	;skip over sync + header + "extra" header
	mov	a,c		;need to preserve c
	lxi	b, 22		;clobbers c
	dad	b
	mov	c,a		;restore c
	mvi     b, cpmssiz	;payload size, 128
cpymem:        
        mov     a, m            ; load from mem hl
	stax    d               ; store at de
	inx     h
	inx     d               ; increment pointers
	dcr     b               ; decrement count
	jnz     cpymem        ; load from mem hl
        

        ;are we done?
        lda     secrem
        dcr     a
        jz      done
        sta     secrem

nxtsec:        
        ;next sector
        inr     c
        mov	a,c
	cpi	sectrk			; last sector reached?
	jc	next

        ;next track
        lda	cmdreg
	ori	dirup
	out	pcmd
	sta 	cmdreg
	out	pstep
	
        mvi	a,7
        call    delay
	
        ;start at sector 0 again
        mvi     c, 0
        jmp     next

        
done:
        jmp     boot

	;delay for step
delay:
	mvi     b, 0CFh
inner:                        
	xthl
	xthl
	dcr     b
	jnz     inner
	dcr     a
	jnz     delay
        ret



;uninitialized data
cmdreg:	ds	1
secrem: ds      1
trck:   ds      1
secbuf:	ds	ssiz
