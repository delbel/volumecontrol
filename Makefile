firmware.hex: firmware.elf
	avr-objcopy -j .text -j .data -O ihex firmware.elf firmware.hex

firmware.elf: firmware.c
	avr-gcc -Wall -O3 -mmcu=attiny88 firmware.c -o firmware.elf
	avr-strip firmware.elf

program: firmware.hex
	avrdude -c avrispmkii -p attiny88 -e -U flash:w:firmware.hex

clean:
	rm -f firmware.elf firmware.hex
