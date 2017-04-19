;******************************************************************* 
; Function:  Mains frequency display  
; Processor: PIC16F628 at 4 MHz using external xtal, 
; Revision:  $Id$
; Author:    Richard Mudhar 
; Date:      26 March 2016
; Notes:     rotating ring of LEDs display
; Notes:     uses HISIDE and LOSIDE to switch two banks of 8 LEDs to get 16 way output
; Notes:     principle is generate interrupts from MCLK at 1600Hz, incf display. Sample at 100Hz from mains, binary dec three LSB to PORTB 
; Notes:     adjust the padding between 155/156 periods in ISR to fine-tune, then fine tune again by varying the RRF register start. This is a good match
; Notes:     13/4/2017 v07 this is the first one to eliminate flickering on the LEDs
;******************************************************************* 
        ERRORLEVEL -302 ;remove message about using proper bank
        LIST P=16F628, R=DEC    ; Use the PIC16F628 and decimal system 

        #include "P16F628A.INC"  ; Include header file 

        __config  _XT_OSC & _LVP_OFF & _WDT_OFF & _PWRTE_ON & _BODEN_ON  & _CP_OFF & _MCLRE_OFF

;---------------------------------------------------------





;   PIC PINOUT
;                                         ------------------------------
;                                VREFOUT | 1 RA2          RA1        18 | C2 - in 
;                             HISIDE out | 2 RA3          RA0        17 | LOSIDE out
;                                        | 3 RA4          RA7        16 | OSC1 CLKIN
;                                        | 4 RA5(MCLR)    RA6        15 | OSC2 CLKOUT
;                                    GND | 5 GND          VCC        14 | +5V
;                                        | 6 RB0          RB7        13 | 
;                                        | 7 RX/RB1       RB6        12 | 
;                                        | 8 TX/RB2       RB5        11 |
;                                        | 9 RB3          RB4        12 |
;                                         ------------------------------
;

        CBLOCK 0x20             ; Declare variable addresses starting at 0x20 
			temp
            wreg
            sreg
			display
			bresenham
			trimatron
			d1
			d2
        ENDC 
    #define LOSIDE PORTA,0
    #define HISIDE PORTA,3
    #define ECHO PORTB,0



;---------------------------------------------------------
; Set the program origin for subsequent code.
      org 0x00
      GOTO          start

      ORG       0x04
      GOTO  ISR

;---------------------------------------------------------


makebin:
		addwf	PCL,		F
TABLE0:
		dt	.1,.2,.4,.8,.16,.32,.64,.128
	    IF ((HIGH ($)) != (HIGH (TABLE0)))
	         ERROR "TABLE0 CROSSES PAGE BOUNDARY!"
	    ENDIF




start:
        clrwdt
		banksel CMCON
        movlw b'00010101' 		; CMCON Comparator 1 is off. Comparator 2 on RA1 (-) RA4 (out - open drain) vref on RA2 out on cmcom bit 6,7
        movwf CMCON             
								; WARNING STUPENDOUS amounts of OSCILLATION on C1 inverted UNLESS Vref om RA2 decoupled to ground, 0.1uF will do
		banksel PIE1
		clrf	PIE1
		; bsf	PIE1, CMIE		; current plan is to poll this 100Hz signal, should be easy enough


; 		set vref
		banksel VRCON
		;movlw b'11101100'		; vref EN, OE, VRR-Lo, NA, 12 should give vcc/2 on RA2
		movlw b'11100011'		; vref EN, OE, VRR-Lo, NA, 3 should give 0.625V on RA2
		movwf	VRCON


        banksel T1CON
        movlw   b'00000001'     ; T1 prescale 1:1 T1OSC off, intOSC T1on
        movwf   T1CON

        banksel CCPR1H  		; interrupt at 2*6400 Hz. divide by 78 1/8
        movlw   .0
        movwf   CCPR1H
        movlw   .77
        movwf   CCPR1L

		clrf	bresenham
		bsf		bresenham,3		; put a 1 in slot 3

        banksel CCP1CON
        movlw   b'00001011'     ; compare mode, clear TMR1 on match
        movwf   CCP1CON


        banksel PIE1
        bsf     PIE1, CCP1IE


        banksel TRISA 

        movlw b'11100110'       ; 0 is output. A5 is always an input (no output driver) Vref on A2 (set as input) A1 is main comp input, A0, A3 and A4 are general outputs
        movwf TRISA             ; portA   
        ;clrf   TRISA           ; make all port a o/p       

        banksel TRISB 

        clrf   TRISB           ; make all port b o/p  


        bcf STATUS,RP0          ; RAM PAGE 0
		
		clrf	PORTB
		incf	PORTB,1			; set portb,0=1

        bsf INTCON, PEIE        ; enable peripheral interrups
        bsf INTCON, GIE         ; enable interrupt




forever:
        clrwdt
		btfss	CMCON,C2OUT		; comparator H (ie input L)?
		goto forever			; no, ignore
		movfw	display			; take a snapshot of counter into w
		movwf	temp
		clrf	PORTB			; blank flickering
		btfsc	temp,3			; check this to see which bank of LEDS to use
		goto	disphi
displlo		
		bcf		LOSIDE
		bsf		HISIDE
		goto	dispdone
disphi
		bsf		LOSIDE
		bcf		HISIDE

dispdone
		andlw	b'00000111'		; mask all but the lowest three bits of w
		call	makebin			; turn it into binary
		movwf	PORTB			; copy to port B	w was set way back un the call makebin
waitlo:
		call	Delay2ms		; wait 2ms to clear chatter
		btfsc	CMCON,C2OUT		; comparator L ?
		goto waitlo				; no, ignore
		call	Delay2ms		; wait 2ms to clear chatter
        goto forever


Delay2ms
			;1993 cycles
	movlw	0x8E
	movwf	d1
	movlw	0x02
	movwf	d2
Delay2ms_0
	decfsz	d1, f
	goto	$+2
	decfsz	d2, f
	goto	Delay2ms_0

			;3 cycles
	goto	$+1
	nop

			;4 cycles (including call)
	return






;the ISR

ISR     bcf     INTCON,GIE      ; disable all interrupts

                                ; save registers, swiped from microchip data sheet p105
        movwf   wreg            ; copy W to temp register, could be in either bank
        swapf   STATUS,w        ; swap status to be saved into W
        bcf     STATUS,RP0      ; change to bank 0 regardless of current bank
        movwf   sreg            ; save status to bank 0 register

        bcf     STATUS,RP0          ; RAM PAGE 0
        
        btfsc   PIR1,CCP1IF     ; test for timer 1  (PIR1 is still im ram page 0)
        goto    timer1isr
        goto    exit
        
timer1isr
        bcf     PIR1,CCP1IF

		incf	display,f
		rrf		bresenham,f		; shift right
		btfsc	bresenham,0		; test the lsb
		goto	long
		movlw	.77				; reset to normal
		movwf	CCPR1L			; this is in RAM page 1
		goto	exit




long:
		movlw	.78
		movwf	CCPR1L			; add one
		clrf	bresenham
		bsf		bresenham,6		; orig 7. Reduce this to nudge down the nominal target frequency
exit:
   
        bcf     STATUS,RP0      ; change to bank 0 regardless of current bank
                                ; restore wreg and status register, pinched from microchip datasheet p105
        swapf   sreg,w
        movwf   STATUS      
        swapf   wreg,f
        swapf   wreg,w  
        retfie                  ; gie should get set back on here





        END 

