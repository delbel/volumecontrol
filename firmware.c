// Intercept volume commands from Samsung TV remote and use them to control a
// digital potentiometer connected to an amplifier
#include <avr/io.h>

typedef enum {
  left,
  right
} pos;

const uint8_t cust = 0x07; // Custom code
const uint8_t volu = 0x07; // Volume up code
const uint8_t vold = 0x0B; // Volume down code
const uint8_t mute = 0x0F; // Mute code

// Volume to wiper value lookup table (logarithmic)
const uint8_t wval[100] = {  0,   1,   1,   2,   2,   3,   4,   4,   5,   6,
                             6,   7,   8,   9,   9,  10,  11,  12,  13,  14,
                            15,  16,  17,  18,  19,  20,  21,  22,  23,  24,
                            25,  27,  28,  29,  31,  32,  33,  35,  36,  38,
                            39,  41,  43,  44,  46,  48,  49,  51,  53,  55,
                            57,  59,  61,  63,  66,  68,  70,  73,  75,  78,
                            80,  83,  86,  88,  91,  94,  97, 100, 103, 107,
                           110, 113, 117, 121, 124, 128, 132, 136, 140, 144,
                           148, 153, 157, 162, 167, 172, 177, 182, 187, 193,
                           198, 204, 210, 216, 222, 228, 235, 241, 248, 255};

// Digit to 7-segment value lookup table (last value is all segments off)
const uint8_t dseg[11] = {0x01, 0x8F, 0x12, 0x06, 0x8C,
                          0x24, 0x20, 0x0F, 0x00, 0x0C, 0xBF};

// Return the received command (0 for unrecognized)
inline uint8_t decode (uint8_t recv[4]) {
  if (recv[0] != cust || recv[1] != cust)
    return 0;
  if (recv[2] == volu && recv[3] == (uint8_t)(~volu))
    return volu;
  if (recv[2] == vold && recv[3] == (uint8_t)(~vold))
    return vold;
  if (recv[2] == mute && recv[3] == (uint8_t)(~mute))
    return mute;
  return 0;
}

// Display number on 7-segment display
inline void disp (uint8_t val, pos p) {
  if (p == left)
    PORTC = val ? dseg[val] : dseg[10];
  else if (p == right)
    PORTD = dseg[val];
}

// Set potentiometer wiper
inline void set_wiper (uint8_t val) {
  PORTB &= 0xFF ^ (1<<PB2);    // Set SS' low
  SPDR = 0x13;                 // Send write command byte
  while (!(SPSR & (1<<SPIF))); // Wait until tranmission is complete
  SPDR = wval[val];            // Send wiper data
  while (!(SPSR & (1<<SPIF))); // Wait until tranmission is complete
  PORTB |= 1<<PB2;             // Set SS' high
}

int main () {
  uint8_t i, j;
  uint8_t lead, recv[4], cmd, prev, pcnt;
  uint8_t vol, voll, volr;
  uint8_t volp, vollp, volrp;

  DDRB = (1<<PB5) | (1<<PB3) | (1<<PB2); // SCK, MOSI, and SS' are outputs
  DDRC = 0xFF ^ (1<<PC6); // PORTC is all outputs except RESET'
  DDRD = 0xFF ^ (1<<PD6); // PORTD is all outputs except PD6

  CLKPR = (1<<CLKPS1) | (1<<CLKPS0); // Drop clock to 1MHz
  TCCR0A = (1<<CS01) | (1<<CS00);    // Set timer0 to 15.625kHz
  TCCR1B = (1<<CS12) | (1<<CS10);    // Set timer1 to 976.5625Hz

  SPCR = (1<<MSTR) | (1<<SPE); // Enable SPI in master mode
  PORTB = 1<<PB2;              // Initialize SS' high

  // Initialize the volume to 0
  vol = 0;
  voll = 0;
  volr = 0;
  volp = 0;
  vollp = 0;
  volrp = 0;
  set_wiper(vol);
  disp(voll, left);
  disp(volr, right);

  // Initialize the previous command and count
  prev = 0;
  pcnt = 0;

  while (1) {
    detect:
    // Make sure timer1 doesn't overflow
    if (TCNT1 > 244) {
      TCNT1 = 244;
    }

    // Clear repeated command after 75ms
    if (pcnt == 5 && TCNT1 > 73) {
      prev = 0;
      pcnt = 0;
    }

    // Detect and process a command
    if (!(PINB&1)) {
      // Skip to the end of the leader, starting over if idle
      TCNT0 = 0;
      while (!(PINB&1))
        if (TCNT0 == 0xFF)
          goto detect;
      while (PINB&1)
        if (TCNT0 == 0xFF)
          goto detect;
      lead = TCNT0; // Record the leader length (9ms)

      // Process the four bytes in the command
      for (i = 0; i < 4; i++) {
        recv[i] = 0; // Initialize the received command byte
        for (j = 0; j < 8; j++) {
          // Skip to the end of the bit
          TCNT0 = 0;
          while (!(PINB&1))
            if (TCNT0 == 0xFF)
              goto detect;
          while (PINB&1)
            if (TCNT0 == 0xFF)
              goto detect;
          // Shift in a 1 or 0 depending on length of bit (2.25ms or 1.12ms)
          recv[i] = recv[i]>>1;
          recv[i] |= TCNT0 > (((lead>>2)+(lead>>3))>>1) ? (1<<7) : 0;
        }
      }

      // Skip the end bit
      while (!(PINB&1))
        if (TCNT0 == 0xFF)
          goto detect;

      // Decode the command
      cmd = decode(recv);
      if (!cmd)
        goto detect;

      // Ignore command if previous command was issued < 50ms ago
      if (TCNT1 < 49)
        goto detect;

      // If this command is the same as before, ignore if issued < 250ms
      // after the previous command unless repeated 5 times
      if (cmd == prev) {
        if ((pcnt < 5 || cmd == mute) && TCNT1 < 244)
          goto detect;
        pcnt += pcnt == 5 ? 0 : 1;
      }
      else {
        pcnt = 1;
        prev = cmd;
      }

      // Adjust the volume
      // Volume up
      if (cmd == volu && vol < 99) {
        vol++;
        volr++;
        if (volr == 10) {
          volr = 0;
          voll++;
        }
      }
      // Volume down
      else if (cmd == vold && vol > 0) {
        vol--;
        volr--;
        if (volr == UINT8_MAX) {
          volr = 9;
          voll--;
        }
      }
      // Mute
      else if (cmd == mute) {
        if (vol) {
          volp = vol;
          vollp = voll;
          volrp = volr;
          vol = 0;
          voll = 0;
          volr = 0;
        } else {
          vol = volp;
          voll = vollp;
          volr = volrp;
          volp = 0;
          vollp = 0;
          volrp = 0;
        }
      }

      // Set the potentiometer and update the display
      TCNT1 = 0;
      set_wiper(vol);
      disp(voll, left);
      disp(volr, right);
    }
  }

  return 0;
}
