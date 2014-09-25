firmware.hex: firmware.elf
	avr-objcopy -j .text -j .data -O ihex firmware.elf firmware.hex

firmware.elf: firmware.S
	avr-gcc -mmcu=attiny88 firmware.S -o firmware.o
	avr-ld firmware.o -o firmware.elf
	avr-strip firmware.elf

program: firmware.hex
	avrdude -c avrispmkii -P usb -p attiny88 -e -U flash:w:firmware.hex

clean:
	rm -f firmware.elf firmware.hex firmware.o
