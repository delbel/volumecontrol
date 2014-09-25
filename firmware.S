#include <avr/io.h>

; Define potentiometer write command
.equ POTW, 0x13

; Define IR constants
.equ CUST, 0x07                        ; Custom code
.equ VOLU, 0x07                        ; Volume up code
.equ VOLD, 0x0B                        ; Volume down code
.equ MUTE, 0x0F                        ; Mute code

; Define the entry point
.text
.org 0x0000
  rjmp main

.org 0x0038
.global main
main:
  ; Initialize the ports and other system registers
  ldi r16, 0b00101100
  out _SFR_IO_ADDR(DDRB), r16          ; SCK, MOSI, and SS' are outputs
  ldi r16, 0b10111111
  out _SFR_IO_ADDR(DDRC), r16          ; PORTC is all outputs except RESET'
  out _SFR_IO_ADDR(DDRD), r16          ; PORTD is all outputs except PD6

  ldi r16, 0b00000011
  sts CLKPR, r16                       ; Drop clock to 1MHz
  out _SFR_IO_ADDR(TCCR0A), r16        ; Set timer0 to 15.625kHz
  ldi r16, 0b00000101
  sts TCCR1B, r16                      ; Set timer1 to 976.5625Hz

  ldi r16, 0b01010000
  out _SFR_IO_ADDR(SPCR), r16          ; Enable SPI in master mode
  sbi _SFR_IO_ADDR(PORTB), PB2         ; Initialize SS' high

  ; Define and initialize registers
  clr r0                               ; Zero register
  in  r1, _SFR_IO_ADDR(SPL)            ; Pointer to empty stack
  in  r2, _SFR_IO_ADDR(SPH)
  ;   r3                               ; Leader length
  ;   r4                               ; Temporary register
  ;   r5                               ; Unused
  ;   r6
  ;   r7
  ;   r8
  ;   r9
  ;   r10
  ;   r11
  clr r12                              ; Previous command
  clr r13                              ; Previous volume
  clr r14                              ; Previous volume - left digit
  clr r15                              ; Previous volume - right digit
  ;   r16                              ; Temporary register
  ;   r17                              ; Temporary register
  clr r18                              ; Volume
  clr r19                              ; Volume - left digit
  clr r20                              ; Volume - right digit
  ;   r21                              ; Iterator i
  ;   r22                              ; Iterator j
  ;   r23                              ; Decoded command
  ldi r24, 244                         ; 250ms on timer1
  clr r25                              ; Repeated command count
  ldi XL, pm_lo8(wval)                 ; Pointer to wval
  ldi XH, pm_hi8(wval)
  lsl XL
  rol XH
  ldi YL, pm_lo8(sseg)                 ; Pointer to sseg
  ldi YH, pm_hi8(sseg)
  lsl YL
  rol YH
  ;   ZL                               ; Program memory pointer
  ;   ZH

  ; Initialize the wiper and display
  rcall wiper
  rcall disp

  ; Main loop
  main1:
    ; Make sure timer1 doesn't overflow
    lds r16, TCNT1L
    lds r17, TCNT1H
    cp r16, r24
    cpc r17, r0
    brlo clrrpt
    sts TCNT1H, r0
    sts TCNT1L, r24

    ; Clear repeated command after 75ms
    clrrpt:
    cpi r25, 5
    brne detect
    cpi r16, 74
    cpc r17, r0
    brlo detect
    clr r12
    clr r25

    ; Detect and process a command if IR pin is low
    detect:
    sbic _SFR_IO_ADDR(PINB), PB0
    rjmp main1

    ; Skip to the end of the leader, starting over if idle
    out _SFR_IO_ADDR(TCNT0), r0
    ; Wait for the IR pin to go high
    lead1:
      sbic _SFR_IO_ADDR(PINB), PB0
      rjmp lead2
      in r16, _SFR_IO_ADDR(TCNT0)
      cpi r16, 0xFF
      breq main1
      rjmp lead1
    ; Wait for the IR pin to go low
    lead2:
      sbis _SFR_IO_ADDR(PINB), PB0
      rjmp lead3
      in r16, _SFR_IO_ADDR(TCNT0)
      cpi r16, 0xFF
      breq main1
      rjmp lead2
    ; Record the leader length (should be 9ms)
    lead3:
    in r3, _SFR_IO_ADDR(TCNT0)

    ; Process the four bytes in the command
    clr r21
    iloop:
      ; Initialize the received command byte
      clr r17
      clr r22
      jloop:
        ; Skip to the end of the bit
        out _SFR_IO_ADDR(TCNT0), r0
        ; Wait for the IR pin to go high
        jloop1:
          sbic _SFR_IO_ADDR(PINB), PB0
          rjmp jloop2
          in r16, _SFR_IO_ADDR(TCNT0)
          cpi r16, 0xFF
          breq abort
          rjmp jloop1
        ; Wait for the IR pin to go low
        jloop2:
          sbis _SFR_IO_ADDR(PINB), PB0
          rjmp shift
          in r16, _SFR_IO_ADDR(TCNT0)
          cpi r16, 0xFF
          breq abort
          rjmp jloop2
        ; Flush the stack and restart main loop if timed out
        abort:
          out _SFR_IO_ADDR(SPL), r1
          out _SFR_IO_ADDR(SPH), r2
          rjmp main1

        ; Shift in a 1 or 0 depending on length of bit (2.25ms or 1.12ms)
        shift:
        mov r4, r3
        lsr r4
        adc r4, r3
        lsr r4
        lsr r4
        lsr r4
        inc r4
        in r16, _SFR_IO_ADDR(TCNT0)
        cp r4, r16
        ror r17
        inc r22
        cpi r22, 8
        brlo jloop

      ; Push the i-th command received byte
      push r17
      inc r21
      cpi r21, 4
      brlo iloop

    ; Skip the end bit
    end:
      sbic _SFR_IO_ADDR(PINB), PB0
      rjmp decode
      in r16, _SFR_IO_ADDR(TCNT0)
      cpi r16, 0xFF
      breq ignore
      rjmp end

    ; Ignore command and go back to the top of the main loop
    ignore:
      rjmp main1

    ; Decode the command
    decode:
    pop r16                            ; Fourth command received byte
    com r16
    cpi r16, VOLU
    breq volu1
    cpi r16, VOLD
    breq vold1
    cpi r16, MUTE
    breq mute1
    ; Flush the stack if unknown command
    unknown:
      rjmp abort
    volu1:
      pop r16                          ; Third command received byte
      cpi r16, VOLU
      brne unknown
      ldi r23, VOLU
      rjmp custom
    vold1:
      pop r16                          ; Third command received byte
      cpi r16, VOLD
      brne unknown
      ldi r23, VOLD
      rjmp custom
    mute1:
      pop r16                          ; Third command received byte
      cpi r16, MUTE
      brne unknown
      ldi r23, MUTE
    custom:
      pop r16                          ; Second command received byte
      cpi r16, CUST
      brne unknown
      pop r16                          ; First command received byte
      cpi r16, CUST
      brne unknown

    ; Ignore command if previous command was issued < 50ms ago
    lds r16, TCNT1L
    lds r17, TCNT1H
    cpi r16, 49
    cpc r17, r0
    brlo ignore

    ; If this command is the same as before, ignore if issued < 250ms
    ; after the previous command unless repeated 5 times
    cp r23, r12
    brne rpt2
      cp r16, r24
      cpc r17, r0
      brsh rpt1
      cpi r25, 5
      brlo ignore
      cpi r23, MUTE
      breq ignore
    rpt1:
      cpi r25, 5
      breq adjv
      inc r25
      rjmp adjv
    rpt2:
      clr r25
      inc r25
      mov r12, r23

    ; Adjust the volume
    adjv:
    cpi r23, VOLU
    breq volu2
    cpi r23, VOLD
    breq vold2
    cpi r23, MUTE
    breq mute2
    rjmp update
    volu2:                             ; Volume up
      cpi r18, 99
      breq update
      inc r18
      inc r20
      cpi r20, 10
      brne update
      clr r20
      inc r19
      rjmp update
    vold2:                             ; Volume down
      cpi r18, 0
      breq update
      dec r18
      dec r20
      cpi r20, 0xFF
      brne update
      ldi r20, 9
      dec r19
      rjmp update
    mute2:                             ; Mute
      cpi r18, 0
      breq mute3
      mov r13, r18
      mov r14, r19
      mov r15, r20
      clr r18
      clr r19
      clr r20
      rjmp update
    mute3:                             ; Unmute
      mov r18, r13
      mov r19, r14
      mov r20, r15
      clr r13
      clr r14
      clr r15

    ; Set the potentiometer and update the display
    update:
    sts TCNT1H, r0
    sts TCNT1L, r0
    rcall wiper
    rcall disp

    ; Go back to the top of the main loop
    rjmp main1

; Sets wiper to value in r18
wiper:
  ldi r16, POTW                        ; Load the write command
  movw ZL, XL                          ; Load the value to send to the wiper
  add ZL, r18
  adc ZH, r0
  lpm r17, Z
  cbi _SFR_IO_ADDR(PORTB), PB2         ; Set SS' low
  out _SFR_IO_ADDR(SPDR), r16          ; Send write command byte
  wiper1:
    in r16, _SFR_IO_ADDR(SPSR)
    sbrs r16, SPIF                     ; Wait until tranmission is complete
    rjmp wiper1
  out _SFR_IO_ADDR(SPDR), r17          ; Send wiper data
  wiper2:
    in r16, _SFR_IO_ADDR(SPSR)
    sbrs r16, SPIF                     ; Wait until tranmission is complete
    rjmp wiper2
  sbi _SFR_IO_ADDR(PORTB), PB2         ; Set SS' high
  ret

; Sets left and right 7-segment displays to values in r19 and r20, respectively
disp:
  movw ZL, YL                          ; Load value of left 7-seg
  adiw ZL, 10                          ; Tentatively load the off pattern
  add ZL, r19
  adc ZH, r0
  cpse r19, r0
  sbiw ZL, 10                          ; Not zero, subtract off pattern index
  lpm r16, Z
  out _SFR_IO_ADDR(PORTC), r16
  movw ZL, YL                          ; Load value of right 7-seg
  add ZL, r20
  adc ZH, r0
  lpm r16, Z
  out _SFR_IO_ADDR(PORTD), r16
  ret

; Volume to wiper value lookup table (logarithmic)
; Align first byte to word boundary
.p2align 1
wval:
  .byte   0,   1,   1,   2,   2,   3,   4,   4,   5,   6
  .byte   6,   7,   8,   9,   9,  10,  11,  12,  13,  14
  .byte  15,  16,  17,  18,  19,  20,  21,  22,  23,  24
  .byte  25,  27,  28,  29,  31,  32,  33,  35,  36,  38
  .byte  39,  41,  43,  44,  46,  48,  49,  51,  53,  55
  .byte  57,  59,  61,  63,  66,  68,  70,  73,  75,  78
  .byte  80,  83,  86,  88,  91,  94,  97, 100, 103, 107
  .byte 110, 113, 117, 121, 124, 128, 132, 136, 140, 144
  .byte 148, 153, 157, 162, 167, 172, 177, 182, 187, 193
  .byte 198, 204, 210, 216, 222, 228, 235, 241, 248, 255

; Digit to 7-segment value lookup table (last value is all segments off)
; Align first byte to word boundary
.p2align 1
sseg:
  .byte 0x01, 0x8F, 0x12, 0x06, 0x8C, 0x24, 0x20, 0x0F, 0x00, 0x0C, 0xBF
