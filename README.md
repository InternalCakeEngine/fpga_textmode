# fpga_textmode

SystemVerilog implementation of a simple 80x30 text mode.

The interesting part is in textmode.sv. It consists of a VGA part which does timing and streams out 480 lines of 640 pixels 60 times a second. The pixels are read from a 640 pixel line buffer which is populated by a character generator just ahead of the pixels being streamed out. Character codes are read from a block memory, as are bitmap pattens for the characters.

The mem files constitute a ROM, of sorts...
- charset.mem is the bitmap for 96 8x8 characters.
- message.mem is (roughly) 2400 characters for the text itself
- stripes.mem is a test pattern loaded into the line buffer at initialisation.

This uses several modules and code fragments from the Project F website and repo (projf-explore on GitHub), which I highly recommend. All such code is made available under the MIT license. I may have made chanages for my use case, so beware; better go to the original repo!

